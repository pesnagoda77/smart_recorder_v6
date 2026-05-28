import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive/hive.dart';

import 'settings_page.dart';
import 'transcription_service.dart';

class DialogueSegment {
  String speaker;
  String text;

  DialogueSegment({
    required this.speaker,
    required this.text,
  });

  Map<String, dynamic> toMap() => {
        'speaker': speaker,
        'text': text,
      };

  factory DialogueSegment.fromMap(Map<String, dynamic> map) => DialogueSegment(
        speaker: map['speaker'] as String,
        text: map['text'] as String,
      );
}

class Recording {
  String id;
  String filePath;
  DateTime createdAt;
  int durationMs;
  int fileSize;
  String? title;
  String? transcription;
  List<Map<String, dynamic>>? segments;
  bool isFavorite;

  List<String>? tags;
  String? summary;
  List<String>? decisions;
  List<Map<String, dynamic>>? speakerStats;

  Recording({
    required this.id,
    required this.filePath,
    required this.createdAt,
    required this.durationMs,
    required this.fileSize,
    this.title,
    this.transcription,
    this.segments,
    this.isFavorite = false,
    this.tags,
    this.summary,
    this.decisions,
    this.speakerStats,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'filePath': filePath,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'durationMs': durationMs,
        'fileSize': fileSize,
        'title': title,
        'transcription': transcription,
        'segments': segments,
        'isFavorite': isFavorite,
        'tags': tags,
        'summary': summary,
        'decisions': decisions,
        'speakerStats': speakerStats?.map((s) => s.map((k, v) => MapEntry(k, v.toString()))).toList(),
      };

  factory Recording.fromMap(Map<String, dynamic> map) => Recording(
        id: map['id'] as String,
        filePath: map['filePath'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
        durationMs: map['durationMs'] as int,
        fileSize: map['fileSize'] as int,
        title: map['title'] as String?,
        transcription: map['transcription'] as String?,
        segments: map['segments'] != null
            ? (map['segments'] as List)
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList()
            : null,
        isFavorite: map['isFavorite'] as bool? ?? false,
        tags: map['tags'] != null
            ? (map['tags'] as List).cast<String>()
            : null,
        summary: map['summary'] as String?,
        decisions: map['decisions'] != null
            ? (map['decisions'] as List).cast<String>()
            : null,
        speakerStats: map['speakerStats'] != null
            ? (map['speakerStats'] as List)
                .map((item) => (item as Map).map((k, v) => MapEntry<String, dynamic>(k as String, v)))
                .toList()
            : null,
      );
}

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  bool _isInit = false;
  Box<Map>? _box;
  DateTime? _startTime;
  Timer? _sleepTimer;
  int? _sleepDurationMinutes;

  // Live transcription
  final StreamController<String> _liveTextController = StreamController<String>.broadcast();
  Stream<String> get liveTextStream => _liveTextController.stream;
  String _lastLiveText = '';
  String get lastLiveText => _lastLiveText;

  Timer? _liveTranscriptionTimer;
  String _liveRecordingPath = '';
  int _liveBytesRead = 0;
  bool _isLiveTranscribing = false;

  Future<void> init() async {
    if (_isInit) return;

    await Permission.microphone.request();
    await Permission.storage.request();

    _box = await Hive.openBox<Map>('recordings');
    _isInit = true;
  }

  Future<String> startRecording() async {
    final dir = await getApplicationDocumentsDirectory();
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final path = '${dir.path}/recording_$id.wav';

    // Читаем настройки из Hive
    int sampleRate = 16000;
    int numChannels = 1;
    try {
      final settingsBox = await Hive.openBox<dynamic>('settings');
      final raw = settingsBox.get('recorder');
      if (raw != null) {
        final settings = RecorderSettings.fromMap(Map<String, dynamic>.from(raw));
        sampleRate = settings.sampleRate;
        numChannels = settings.numChannels;
      }
    } catch (_) {
      // fallback к дефолтам
    }

    _startTime = DateTime.now();
    _liveRecordingPath = path;
    _liveBytesRead = 0;
    _lastLiveText = '';

    // Сброс VOSK перед новой записью
    await TranscriptionService().resetRecognizer();

    await _recorder.start(
      RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: sampleRate,
        numChannels: numChannels,
      ),
      path: path,
    );

    return path;
  }

  void startLiveTranscription() {
    _isLiveTranscribing = true;
    _liveBytesRead = 0;
    _lastLiveText = '';
    _liveTextController.add('');
    
    _liveTranscriptionTimer?.cancel();
    _liveTranscriptionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _processLiveAudioChunk();
    });
  }

  void stopLiveTranscription() {
    _liveTranscriptionTimer?.cancel();
    _liveTranscriptionTimer = null;
    _isLiveTranscribing = false;
    _liveTextController.add('');
  }

  Future<void> _processLiveAudioChunk() async {
    if (_liveRecordingPath.isEmpty) return;
    
    final file = File(_liveRecordingPath);
    if (!await file.exists()) return;
    
    final fileSize = await file.length();
    if (fileSize <= 44) return; // WAV header minimum
    
    if (_liveBytesRead == 0) {
      // First time - skip WAV header
      _liveBytesRead = 44;
    }
    
    if (fileSize <= _liveBytesRead) return;
    
    // Read new bytes
    final raf = await file.open();
    await raf.setPosition(_liveBytesRead);
    final newBytes = await raf.read(fileSize - _liveBytesRead);
    await raf.close();
    
    _liveBytesRead = fileSize;
    
    if (newBytes.isEmpty) return;
    
    try {
      await TranscriptionService().acceptWaveform(newBytes);
      final result = await TranscriptionService().getPartialResult();
      
      final partial = result['partial'] as String? ?? '';
      final text = result['text'] as String? ?? '';
      
      // Combine final + partial
      final combined = text.isNotEmpty
          ? '$text ${partial.isNotEmpty ? ' $partial' : ''}'
          : partial;
      
      _liveTextController.add(combined.trim());
      _lastLiveText = combined.trim();
    } catch (_) {
      // Ignore errors during live transcription
    }
  }

  void setSleepTimer(int minutes, Function onComplete) {
    _sleepTimer?.cancel();
    _sleepDurationMinutes = minutes;
    _sleepTimer = Timer(Duration(minutes: minutes), () {
      stopRecording().then((_) => onComplete());
    });
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepDurationMinutes = null;
  }

  int? get sleepDurationMinutes => _sleepDurationMinutes;

  Future<dynamic> stopRecording() async {
    final path = await _recorder.stop();

    final duration = _startTime != null
        ? DateTime.now().difference(_startTime!)
        : Duration.zero;
    _startTime = null;

    final file = File(path!);
    final size = await file.length();
    final now = DateTime.now();

    final recording = Recording(
      id: now.millisecondsSinceEpoch.toString(),
      filePath: path,
      createdAt: now,
      durationMs: duration.inMilliseconds,
      fileSize: size,
    );

    await _box!.put(recording.id, recording.toMap());
    return recording;
  }

  Future<void> playRecording(String path) async {
    await _player.stop();
    await _player.setFilePath(path);
    await _player.play();
  }

  Future<void> stopPlaying() async {
    await _player.stop();
  }

  Future<void> deleteRecording(String id) async {
    final map = _box!.get(id);
    if (map != null) {
      final file = File(map['filePath'] as String);
      if (await file.exists()) await file.delete();
      await _box!.delete(id);
    }
  }

  Future<void> updateRecording(Recording recording) async {
    await _box!.put(recording.id, recording.toMap());
  }

  List<dynamic> getAllRecordings() {
    final maps = _box!.values.toList();
    maps.sort(
        (a, b) => (b['createdAt'] as int).compareTo(a['createdAt'] as int));
    return maps
        .map((m) => Recording.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  void dispose() {
    _liveTextController.close();
    _liveTranscriptionTimer?.cancel();
    _sleepTimer?.cancel();
    _recorder.dispose();
    _player.dispose();
  }
}
