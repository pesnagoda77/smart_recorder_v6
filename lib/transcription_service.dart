import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

class DialogueSegment {
  final String speaker;
  final String text;
  final double startTime;
  final double endTime;

  DialogueSegment({
    required this.speaker,
    required this.text,
    required this.startTime,
    required this.endTime,
  });

  Map<String, dynamic> toMap() => {
        'speaker': speaker,
        'text': text,
        'startTime': startTime,
        'endTime': endTime,
      };

  factory DialogueSegment.fromMap(Map<String, dynamic> map) => DialogueSegment(
        speaker: map['speaker'],
        text: map['text'],
        startTime: map['startTime'],
        endTime: map['endTime'],
      );
}

class TranscriptionResult {
  final String fullText;
  final List<DialogueSegment> segments;

  TranscriptionResult({
    required this.fullText,
    required this.segments,
  });
}

class TranscriptionService {
  static final TranscriptionService _instance =
      TranscriptionService._internal();
  factory TranscriptionService() => _instance;
  TranscriptionService._internal();

  final _vosk = VoskFlutterPlugin.instance();
  Recognizer? _recognizer;
  bool _isModelLoaded = false;
  static const _platform = MethodChannel('smart_recorder/convert');

  Future<void> initModel() async {
    if (_isModelLoaded) return;

    final modelPath = await ModelLoader()
        .loadFromAssets('assets/models/vosk-model-small-ru-0.22.zip');

    final model = await _vosk.createModel(modelPath);
    _recognizer = await _vosk.createRecognizer(
      model: model,
      sampleRate: 16000,
    );

    _isModelLoaded = true;
  }

  Future<TranscriptionResult> transcribeFile(String audioPath) async {
    if (!_isModelLoaded) await initModel();
    await resetRecognizer(); // Сброс перед новой транскрибацией

    final ext = audioPath.toLowerCase().split('.').last;
    Uint8List audioBytes;

    if (ext == 'wav') {
      final wavBytes = await File(audioPath).readAsBytes();
      // Конвертируем любой WAV в 16kHz mono 16-bit PCM
      audioBytes = _convertWavToPcm16_16k_mono(wavBytes);
    } else {
      // Проверяем ID3-теги в MP3 — они крашат MediaExtractor на native уровне
      if (ext == 'mp3') {
        final fileBytes = await File(audioPath).readAsBytes();
        if (fileBytes.length >= 3) {
          final header = String.fromCharCodes(fileBytes.sublist(0, 3));
          // ID3v2 в начале файла
          if (header == 'ID3') {
            throw Exception(
              'MP3 содержит ID3v2-теги (обложка/метаданные). Извлеките "чистое" аудио и повторите.',
            );
          }
          // ID3v1 в конце файла (последние 128 байт начинаются с "TAG")
          if (fileBytes.length >= 128) {
            final tail = String.fromCharCodes(fileBytes.sublist(fileBytes.length - 128, fileBytes.length - 125));
            if (tail == 'TAG') {
              throw Exception(
                'MP3 содержит ID3v1-теги (метаданные). Извлеките "чистое" аудио и повторите.',
              );
            }
          }
          // Проверяем, что файл вообще похож на MP3 (начинается с sync word 0xFFF или ID3)
          final firstByte = fileBytes[0];
          final secondByte = fileBytes[1];
          if ((firstByte & 0xFF) != 0xFF || ((secondByte & 0xE0) != 0xE0)) {
            // Не похоже на MP3 — всё равно попробуем, но предупредим
            // Не бросаем исключение, т.к. это может быть валидный MP3 с другой структурой
          }
        }
      }

      final tempDir = await getTemporaryDirectory();
      final tempWav = '${tempDir.path}/temp_convert_${DateTime.now().millisecondsSinceEpoch}.wav';

      final result = await _platform.invokeMethod<Map<dynamic, dynamic>>(
        'convertToWav',
        {'inputPath': audioPath, 'outputPath': tempWav},
      );

      if (result == null || result['success'] != true) {
        throw Exception(result?['error'] ?? 'Conversion failed');
      }

      final wavBytes = await File(tempWav).readAsBytes();
      audioBytes = _convertWavToPcm16_16k_mono(wavBytes);
      await File(tempWav).delete();
    }

    final rawResults = await _processAudioRaw(audioBytes);

    // Собираем полный текст
    String fullText = '';
    for (var result in rawResults) {
      if (result['text'] != null && result['text'].toString().isNotEmpty) {
        fullText += ' ${result['text']}';
      }
    }
    fullText = fullText.trim();

    // Разбиваем на диалог — по предложениям, чередуем говорящих
    final segments = _splitIntoDialogue(fullText);

    return TranscriptionResult(
      fullText: fullText,
      segments: segments,
    );
  }

  Future<List<Map<String, dynamic>>> _processAudioRaw(
      Uint8List audioBytes) async {
    final List<Map<String, dynamic>> results = [];
    int chunkSize = 8192;
    int pos = 0;

    while (pos + chunkSize < audioBytes.length) {
      final chunk = Uint8List.fromList(
        audioBytes.getRange(pos, pos + chunkSize).toList(),
      );
      final resultReady = await _recognizer!.acceptWaveformBytes(chunk);
      pos += chunkSize;

      if (resultReady) {
        final resultJson = await _recognizer!.getResult();
        final result = jsonDecode(resultJson);
        results.add(result);
      }
    }

    final lastChunk = Uint8List.fromList(
      audioBytes.getRange(pos, audioBytes.length).toList(),
    );
    await _recognizer!.acceptWaveformBytes(lastChunk);
    final finalJson = await _recognizer!.getFinalResult();
    final finalResult = jsonDecode(finalJson);
    results.add(finalResult);

    return results;
  }

  List<DialogueSegment> _splitIntoDialogue(String fullText) {
    // Сначала пробуем по пунктуации
    var sentences = fullText
        .split(RegExp(r'[.!?]+\s*'))
        .map((s) => s.trim())
        .where((s) => s.length > 3)
        .toList();

    // Если мало предложений (нет пунктуации) — режем по длине
    if (sentences.length <= 2 && fullText.length > 40) {
      final words = fullText.split(RegExp(r'\s+'));
      sentences = [];
      final chunkSize = words.length <= 20 ? 8 : 12;
      for (int i = 0; i < words.length; i += chunkSize) {
        final end = (i + chunkSize).clamp(0, words.length);
        final chunk = words.sublist(i, end).join(' ');
        if (chunk.length > 3) sentences.add(chunk);
      }
    }

    if (sentences.isEmpty) {
      return [
        DialogueSegment(speaker: 'A', text: fullText, startTime: 0, endTime: 0)
      ];
    }

    return sentences.asMap().entries.map((entry) {
      final isA = entry.key % 2 == 0;
      return DialogueSegment(
        speaker: isA ? 'A' : 'B',
        text: entry.value,
        startTime: 0,
        endTime: 0,
      );
    }).toList();
  }

  // ========== Live Transcription ==========

  Future<Map<String, dynamic>> getPartialResult() async {
    if (!_isModelLoaded) await initModel();
    final partialJson = await _recognizer!.getPartialResult();
    return jsonDecode(partialJson);
  }

  Future<void> acceptWaveform(Uint8List chunk) async {
    if (!_isModelLoaded) await initModel();
    await _recognizer!.acceptWaveformBytes(chunk);
  }

  Future<void> resetRecognizer() async {
    if (_recognizer != null) {
      await _recognizer!.reset();
    }
  }

  void dispose() {
    _recognizer?.dispose();
  }

  // ========== WAV конвертер: любой WAV → 16kHz mono 16-bit PCM ==========

  Uint8List _convertWavToPcm16_16k_mono(Uint8List wavBytes) {
    if (wavBytes.length < 44) {
      throw Exception('WAV file too small');
    }

    final reader = ByteData.sublistView(wavBytes);
    var pos = 0;

    // RIFF header
    if (String.fromCharCodes(wavBytes.sublist(0, 4)) != 'RIFF') {
      throw Exception('Not a valid WAV file');
    }
    pos += 12; // skip RIFF...WAVE

    int? channels;
    int? sampleRate;
    int? bitsPerSample;
    int? dataOffset;
    int? dataSize;

    // Parse chunks
    while (pos + 8 <= wavBytes.length) {
      final chunkId = String.fromCharCodes(wavBytes.sublist(pos, pos + 4));
      final chunkSize = reader.getUint32(pos + 4, Endian.little);

      if (chunkId == 'fmt ') {
        channels = reader.getUint16(pos + 10, Endian.little);
        sampleRate = reader.getUint32(pos + 12, Endian.little);
        bitsPerSample = reader.getUint16(pos + 22, Endian.little);
        pos += 8 + chunkSize;
      } else if (chunkId == 'data') {
        dataOffset = pos + 8;
        dataSize = chunkSize;
        break; // data is the last chunk we care about
      } else {
        pos += 8 + chunkSize;
      }
    }

    if (channels == null || sampleRate == null || bitsPerSample == null ||
        dataOffset == null || dataSize == null) {
      throw Exception('Invalid WAV header');
    }

    // If already 16kHz mono 16-bit — just skip header and return data portion
    if (sampleRate == 16000 && channels == 1 && bitsPerSample == 16) {
      final end = (dataOffset + dataSize).clamp(0, wavBytes.length);
      return Uint8List.sublistView(wavBytes, dataOffset, end);
    }

    // Clamp dataSize to actual file bounds
    final actualDataSize = (dataOffset + dataSize > wavBytes.length)
        ? wavBytes.length - dataOffset
        : dataSize;

    return _resampleAndConvert(
      wavBytes,
      dataOffset,
      actualDataSize,
      sampleRate,
      channels,
      bitsPerSample,
    );
  }

  Uint8List _resampleAndConvert(
    Uint8List bytes,
    int offset,
    int length,
    int inSampleRate,
    int inChannels,
    int inBits,
  ) {
    final outSampleRate = 16000;
    final outChannels = 1;
    final outBits = 16;

    // Total input samples (per channel)
    final bytesPerSample = inBits ~/ 8;
    final totalInputFrames = length ~/ (bytesPerSample * inChannels);
    if (totalInputFrames == 0) return Uint8List(0);

    final ratio = inSampleRate / outSampleRate;
    final totalOutputFrames = (totalInputFrames / ratio).ceil();

    final result = BytesBuilder();

    for (int i = 0; i < totalOutputFrames; i++) {
      final srcFrame = (i * ratio).toInt().clamp(0, totalInputFrames - 1);
      final srcBytePos = offset + srcFrame * bytesPerSample * inChannels;

      // Read and average all channels to mono
      double sampleSum = 0;
      for (int ch = 0; ch < inChannels; ch++) {
        final pos = srcBytePos + ch * bytesPerSample;
        if (pos + bytesPerSample > bytes.length) break;

        double sampleVal;
        if (inBits == 8) {
          sampleVal = bytes[pos] - 128; // unsigned to signed
        } else if (inBits == 16) {
          sampleVal = ByteData.sublistView(bytes, pos, pos + 2)
              .getInt16(0, Endian.little)
              .toDouble();
        } else if (inBits == 24) {
          final b0 = bytes[pos];
          final b1 = bytes[pos + 1];
          final b2 = bytes[pos + 2];
          int val = b0 | (b1 << 8) | (b2 << 16);
          if (val & 0x800000 != 0) val -= 0x1000000;
          sampleVal = val.toDouble();
        } else if (inBits == 32) {
          sampleVal = ByteData.sublistView(bytes, pos, pos + 4)
              .getInt32(0, Endian.little)
              .toDouble();
        } else {
          sampleVal = 0;
        }
        sampleSum += sampleVal;
      }

      final monoSample = (sampleSum / inChannels).toInt().clamp(-32768, 32767);

      // Write as 16-bit little-endian
      final bd = ByteData(2);
      bd.setInt16(0, monoSample, Endian.little);
      result.add(bd.buffer.asUint8List());
    }

    return result.toBytes();
  }
}
