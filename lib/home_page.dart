import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';
import 'audio_service.dart';
import 'transcription_service.dart';
import 'dialogue_editor.dart';
import 'tag_service.dart';
import 'export_service.dart';
import 'player_page.dart';
import 'settings_page.dart';
import 'summary_page.dart';
import 'summary_service.dart';


class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  bool _isRecording = false;
  var _recordings = [];
  int _recordSeconds = 0;
  double _amplitude = 0.0;
  String _searchQuery = '';
  bool _isSearching = false;
  bool _showFavoritesOnly = false;
  Timer? _timer;
  late AnimationController _pulseController;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _loadRecordings();
  }

  void _loadRecordings() {
    setState(() => _recordings = AudioService().getAllRecordings());
  }

  List<dynamic> get _filteredRecordings {
    var list = _recordings;
    if (_showFavoritesOnly) {
      list = list.where((rec) => rec.isFavorite == true).toList();
    }
    if (_searchQuery.isEmpty) return list;
    return list.where((rec) {
      final text = rec.transcription?.toLowerCase() ?? '';
      final title = (rec.title ?? '').toLowerCase();
      final name = 'Запись ${DateFormat('dd.MM HH:mm').format(rec.createdAt)}'
          .toLowerCase();
      return text.contains(_searchQuery.toLowerCase()) ||
          title.contains(_searchQuery.toLowerCase()) ||
          name.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  void _startTimer() {
    _recordSeconds = 0;
    _amplitude = 0.0;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      setState(() {
        _recordSeconds++;
        _amplitude = _isRecording ? 0.3 + (_recordSeconds % 10) / 20 : 0.0;
      });
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _recordSeconds = 0;
    _amplitude = 0.0;
  }

  String _fmtTime(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _fmtDuration(int ms) {
    final s = (ms ~/ 1000);
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  Future<void> _showSleepTimerDialog() async {
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Таймер остановки'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.timer_off),
              title: const Text('Без таймера'),
              onTap: () => Navigator.pop(ctx, 0),
            ),
            ListTile(
              leading: const Icon(Icons.timer),
              title: const Text('15 минут'),
              onTap: () => Navigator.pop(ctx, 15),
            ),
            ListTile(
              leading: const Icon(Icons.timer),
              title: const Text('30 минут'),
              onTap: () => Navigator.pop(ctx, 30),
            ),
            ListTile(
              leading: const Icon(Icons.timer),
              title: const Text('60 минут'),
              onTap: () => Navigator.pop(ctx, 60),
            ),
          ],
        ),
      ),
    );

    if (selected == null) return;
    if (selected == 0) {
      AudioService().cancelSleepTimer();
      setState(() {});
      return;
    }

    AudioService().setSleepTimer(selected, () {
      if (mounted) {
        setState(() => _isRecording = false);
        _stopTimer();
        _loadRecordings();
      }
    });
    setState(() {});
  }

  bool _isTranscribing = false;

  void _showTranscribingDialog() {
    _isTranscribing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Обработка записи...'),
          ],
        ),
      ),
    );
  }

  void _hideTranscribingDialog() {
    if (_isTranscribing && mounted) {
      _isTranscribing = false;
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _toggleRecord() async {
    if (_isRecording) {
      AudioService().stopLiveTranscription();
      final liveText = AudioService().lastLiveText;
      await AudioService().stopRecording();
      _stopTimer();
      setState(() => _isRecording = false);
      _loadRecordings();
      
      // Full batch transcription — much better quality than live preview
      _showTranscribingDialog();
      try {
        final recordings = AudioService().getAllRecordings();
        if (recordings.isNotEmpty) {
          final latest = recordings.first;
          final result = await TranscriptionService().transcribeFile(latest.filePath);
          final fullText = result.fullText;
          
          latest.transcription = fullText;
          latest.segments = result.segments.map((s) => s.toMap()).toList();
          latest.tags = TagService.extractTags(fullText);
          latest.summary = SummaryService.getSummary(fullText, sentencesCount: 3).join('\n');
          latest.decisions = SummaryService.getDecisions(fullText);
          await AudioService().updateRecording(latest);
          _loadRecordings();
        }
      } catch (e) {
        // Fallback to live text if batch fails
        final recordings = AudioService().getAllRecordings();
        if (recordings.isNotEmpty) {
          final latest = recordings.first;
          latest.transcription = liveText;
          latest.tags = TagService.extractTags(liveText);
          latest.summary = SummaryService.getSummary(liveText, sentencesCount: 3).join('\n');
          latest.decisions = SummaryService.getDecisions(liveText);
          await AudioService().updateRecording(latest);
          _loadRecordings();
        }
      } finally {
        _hideTranscribingDialog();
      }
    } else {
      await AudioService().startRecording();
      AudioService().startLiveTranscription();
      _startTimer();
      setState(() => _isRecording = true);
    }
  }

  void _playRecording(rec) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerPage(recording: rec),
      ),
    );
  }

  Future<void> _deleteRecording(String id) async {
    await AudioService().deleteRecording(id);
    _loadRecordings();
  }

  Future<void> _transcribeRecording(rec) async {
    // Проверяем, что файл существует
    if (!File(rec.filePath).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Файл не найден: ${rec.filePath}'),
          backgroundColor: Colors.red.shade900,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final result = await TranscriptionService().transcribeFile(rec.filePath);

      rec.transcription = result.fullText;
      rec.segments = result.segments.map((s) => s.toMap()).toList();
      rec.tags = TagService.extractTags(result.fullText);
      rec.summary = SummaryService.getSummary(result.fullText, sentencesCount: 3).join('\n');
      rec.decisions = SummaryService.getDecisions(result.fullText);
      rec.speakerStats = SummaryService.getSpeakerStats(result.segments.map((s) => s.toMap()).toList());
      await AudioService().updateRecording(rec);

      Navigator.pop(context);
      _openDialogueEditor(rec);
    } on PlatformException catch (e) {
      Navigator.pop(context);
      final msg = e.message ?? 'Ошибка платформы';
      final details = e.details?.toString() ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: $msg${details.isNotEmpty ? " ($details)" : ""}'),
          backgroundColor: Colors.red.shade900,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка транскрибации: $e'),
          backgroundColor: Colors.red.shade900,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _openDialogueEditor(rec) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DialogueEditor(recording: rec),
      ),
    ).then((saved) {
      if (saved == true) {
        _loadRecordings();
      }
    });
  }

  Future<void> _importFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
      allowCompression: false,
    );

    if (result == null || result.files.isEmpty) return;

    int successCount = 0;
    int failCount = 0;

    final allowedExts = ['wav', 'mp3', 'm4a', 'aac', 'ogg', 'flac', 'wma'];

    for (final picked in result.files) {
      final sourcePath = picked.path;
      final fileBytes = picked.bytes;
      
      final ext = (picked.extension ?? picked.name.split('.').last).toLowerCase();
      if (!allowedExts.contains(ext)) {
        failCount++;
        continue;
      }

      try {
        final dir = await getApplicationDocumentsDirectory();
        final id = DateTime.now().millisecondsSinceEpoch.toString();
        final destPath = '${dir.path}/imported_${id}_${successCount}.$ext';
        
        if (sourcePath != null && sourcePath.isNotEmpty) {
          await File(sourcePath).copy(destPath);
        } else if (fileBytes != null && fileBytes.isNotEmpty) {
          await File(destPath).writeAsBytes(fileBytes);
        } else {
          failCount++;
          continue;
        }

        final file = File(destPath);
        final size = await file.length();
        final now = DateTime.now();

        int durationMs = 0;
        try {
          final player = AudioPlayer();
          await player.setFilePath(destPath);
          final dur = await player.durationStream.firstWhere(
            (d) => d != null && d.inMilliseconds > 0,
            orElse: () => null,
          );
          if (dur != null) {
            durationMs = dur.inMilliseconds;
          }
          await player.dispose();
        } catch (_) {}

        final recording = Recording(
          id: now.millisecondsSinceEpoch.toString() + '_$successCount',
          filePath: destPath,
          createdAt: now,
          durationMs: durationMs,
          fileSize: size,
          title: picked.name,
        );

        await AudioService().updateRecording(recording);
        successCount++;
      } catch (e) {
        failCount++;
      }
    }

    _loadRecordings();

    if (mounted) {
      String msg = 'Импортировано: $successCount';
      if (failCount > 0) msg += ', ошибок: $failCount';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  void _exportRecording(rec) {
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Формат экспорта'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.text_snippet, color: Colors.green),
              title: const Text('TXT — текст с таймкодами'),
              onTap: () => Navigator.pop(ctx, 'txt'),
            ),
            ListTile(
              leading: const Icon(Icons.code, color: Colors.blue),
              title: const Text('HTML — красивый документ'),
              onTap: () => Navigator.pop(ctx, 'html'),
            ),
            ListTile(
              leading: const Icon(Icons.content_copy),
              title: const Text('Скопировать текст'),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
          ],
        ),
      ),
    ).then((format) {
      if (format == null || !mounted) return;

      switch (format) {
        case 'txt':
          final text = ExportService.formatTranscriptTxt(rec);
          ExportService.shareFile(text, '${rec.title ?? "transcript"}.txt');
          break;
        case 'html':
          final text = ExportService.formatTranscriptHtml(rec);
          ExportService.shareFile(text, '${rec.title ?? "transcript"}.html');
          break;
        case 'copy':
          ExportService.copyToClipboard(rec.transcription ?? '');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Текст скопирован')),
            );
          }
          break;
      }
    });
  }

  Future<void> _showShareOptions(rec) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Поделиться'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (rec.transcription != null && rec.transcription!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.text_snippet, color: Colors.blue),
                title: const Text('Текст транскрипции'),
                onTap: () => Navigator.pop(ctx, 'text'),
              ),
            ListTile(
              leading: const Icon(Icons.audio_file, color: Colors.purple),
              title: const Text('Аудиозапись'),
              onTap: () => Navigator.pop(ctx, 'audio'),
            ),
          ],
        ),
      ),
    );

    if (choice == 'text') {
      // Показываем диалог формата экспорта для текста
      final format = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Отправить текст'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.text_snippet, color: Colors.green),
                title: const Text('TXT — текст с таймкодами'),
                onTap: () => Navigator.pop(ctx, 'txt'),
              ),
              ListTile(
                leading: const Icon(Icons.code, color: Colors.blue),
                title: const Text('HTML — красивый документ'),
                onTap: () => Navigator.pop(ctx, 'html'),
              ),
              ListTile(
                leading: const Icon(Icons.content_copy),
                title: const Text('Скопировать текст'),
                onTap: () => Navigator.pop(ctx, 'copy'),
              ),
            ],
          ),
        ),
      );

      if (format == null || !mounted) return;

      switch (format) {
        case 'txt':
          final text = ExportService.formatTranscriptTxt(rec);
          ExportService.shareFile(text, '${rec.title ?? "transcript"}.txt');
          break;
        case 'html':
          final text = ExportService.formatTranscriptHtml(rec);
          ExportService.shareFile(text, '${rec.title ?? "transcript"}.html');
          break;
        case 'copy':
          ExportService.copyToClipboard(rec.transcription ?? '');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Текст скопирован')),
            );
          }
          break;
      }
    } else if (choice == 'audio') {
      ExportService.shareAudioFile(rec.filePath);
    }
  }

  void _openSummaryPage(rec) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SummaryPage(recording: rec),
      ),
    );
  }

  void _shareTranscript(rec) {
    final text = ExportService.formatTranscript(rec);
    ExportService.shareText(text);
  }

  Future<void> _toggleFavorite(rec) async {
    rec.isFavorite = !rec.isFavorite;
    await AudioService().updateRecording(rec);
    _loadRecordings();
  }

  Future<void> _renameRecording(rec) async {
    final controller = TextEditingController(text: rec.title);

    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Переименовать'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Название записи...',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (newTitle != null && newTitle.isNotEmpty) {
      rec.title = newTitle;
      await AudioService().updateRecording(rec);
      _loadRecordings();
    }
  }

  Widget _highlightSearchInPreview(String text) {
    if (_searchQuery.isEmpty) {
      return Text(
        text,
        style: const TextStyle(color: Colors.green, fontSize: 12),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = _searchQuery.toLowerCase();
    final index = lowerText.indexOf(lowerQuery);

    if (index == -1) {
      return Text(
        text,
        style: const TextStyle(color: Colors.green, fontSize: 12),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    int start = (index - 15).clamp(0, text.length);
    int end = (index + _searchQuery.length + 15).clamp(0, text.length);

    String preview = text.substring(start, end);
    if (start > 0) preview = '...$preview';
    if (end < text.length) preview = '$preview...';

    final spans = <TextSpan>[];
    final lowerPreview = preview.toLowerCase();
    int searchIndex = lowerPreview.indexOf(lowerQuery);

    if (searchIndex > 0) {
      spans.add(TextSpan(
        text: preview.substring(0, searchIndex),
        style: const TextStyle(color: Colors.green, fontSize: 12),
      ));
    }

    spans.add(TextSpan(
      text: preview.substring(searchIndex, searchIndex + _searchQuery.length),
      style: const TextStyle(
        color: Colors.black,
        fontSize: 12,
        backgroundColor: Colors.yellow,
        fontWeight: FontWeight.bold,
      ),
    ));

    if (searchIndex + _searchQuery.length < preview.length) {
      spans.add(TextSpan(
        text: preview.substring(searchIndex + _searchQuery.length),
        style: const TextStyle(color: Colors.green, fontSize: 12),
      ));
    }

    return RichText(
      text: TextSpan(children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    _searchController.dispose();
    AudioService().dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRecordings;

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Поиск по транскрипциям...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              )
            : const Center(
                child: Text('ДиктаПро',
                    style: TextStyle(fontWeight: FontWeight.bold))),
        centerTitle: !_isSearching,
        elevation: 0,
        leading: _isSearching
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _isSearching = false;
                    _searchQuery = '';
                    _searchController.clear();
                  });
                },
              )
            : null,
        actions: [
          if (!_isSearching) ...[
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white),
              tooltip: 'Настройки',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.folder_open),
              onPressed: _importFile,
            ),
            IconButton(
              icon: Icon(_showFavoritesOnly ? Icons.star : Icons.star_border),
              color: _showFavoritesOnly ? Colors.amber : null,
              onPressed: () {
                setState(() {
                  _showFavoritesOnly = !_showFavoritesOnly;
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => setState(() => _isSearching = true),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                Text(
                  _isRecording ? '● Идет запись...' : 'Нажмите для записи',
                  style: TextStyle(
                    color: _isRecording ? Colors.red : Colors.white54,
                    fontSize: 14,
                    fontWeight:
                        _isRecording ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 12),
                if (_isRecording) ...[
                  Container(
                    width: 160,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: _amplitude.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final scale = _isRecording
                        ? 1.0 + _pulseController.value * 0.15
                        : 1.0;
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isRecording
                              ? Colors.red.withOpacity(0.15)
                              : Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.15),
                          border: Border.all(
                            color: _isRecording
                                ? Colors.red
                                : Theme.of(context).colorScheme.primary,
                            width: 3,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            _isRecording ? Icons.mic : Icons.mic_none,
                            size: 48,
                            color: _isRecording
                                ? Colors.red
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  _fmtTime(_recordSeconds ~/ 10),
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: _isRecording ? Colors.red : Colors.white30,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 16),
                if (AudioService().sleepDurationMinutes != null)
                  Text(
                    'Таймер: ${AudioService().sleepDurationMinutes} мин',
                    style: const TextStyle(color: Colors.amber, fontSize: 12),
                  ),
                if (AudioService().sleepDurationMinutes != null)
                  const SizedBox(height: 4),
                
                // Live transcription text
                if (_isRecording)
                  StreamBuilder<String>(
                    stream: AudioService().liveTextStream,
                    builder: (context, snapshot) {
                      final text = snapshot.data ?? '';
                      if (text.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Text(
                          text,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            height: 1.4,
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                
                GestureDetector(
                  onTap: _toggleRecord,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: _isRecording ? 64 : 80,
                    height: _isRecording ? 64 : 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isRecording ? Colors.white : Colors.red,
                      boxShadow: [
                        BoxShadow(
                          color: (_isRecording ? Colors.white : Colors.red)
                              .withOpacity(0.4),
                          blurRadius: 20,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Icon(
                      _isRecording ? Icons.stop : Icons.fiber_manual_record,
                      size: _isRecording ? 32 : 36,
                      color: _isRecording ? Colors.red : Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (!_isRecording)
                  GestureDetector(
                    onTap: _showSleepTimerDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.timer, size: 16, color: Colors.white54),
                          const SizedBox(width: 4),
                          Text(
                            AudioService().sleepDurationMinutes != null
                                ? '${AudioService().sleepDurationMinutes} мин'
                                : 'Таймер сна',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.library_music,
                            size: 20, color: Colors.white54),
                        const SizedBox(width: 8),
                        Text(
                          _searchQuery.isEmpty
                              ? (_showFavoritesOnly ? 'Избранное (${filtered.length})' : 'Записи (${_recordings.length})')
                              : 'Найдено: ${filtered.length}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              _searchQuery.isEmpty
                                  ? 'Нет записей'
                                  : 'Ничего не найдено',
                              style: const TextStyle(color: Colors.white30),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(
                                left: 16, right: 16, top: 8, bottom: 80),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final rec = filtered[index];
                              final hasTranscription =
                                  rec.transcription != null &&
                                      rec.transcription!.isNotEmpty;
                              final dateStr =
                                  DateFormat('dd.MM').format(rec.createdAt);
                              final timeStr =
                                  DateFormat('HH:mm').format(rec.createdAt);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E2E),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.05),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 12, 16, 0),
                                      child: Row(
                                        children: [
                                          GestureDetector(
                                            onTap: () => _renameRecording(rec),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                    .withOpacity(0.15),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                rec.title ??
                                                    '$dateStr $timeStr',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          GestureDetector(
                                            onTap: () => _toggleFavorite(rec),
                                            child: Icon(
                                              rec.isFavorite
                                                  ? Icons.star
                                                  : Icons.star_border,
                                              size: 20,
                                              color: rec.isFavorite
                                                  ? Colors.amber
                                                  : Colors.white30,
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            '${_fmtDuration(rec.durationMs)} • ${_fmtSize(rec.fileSize)}',
                                            style: const TextStyle(
                                              color: Colors.white38,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (hasTranscription)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            16, 8, 16, 0),
                                        child: _highlightSearchInPreview(
                                            rec.transcription!),
                                      ),
                                    if (rec.tags != null && rec.tags!.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                                        child: Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: rec.tags!.map<Widget>((tag) =>
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.amber.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: Colors.amber.withOpacity(0.3),
                                                  width: 1,
                                                ),
                                              ),
                                              child: Text(
                                                '#$tag',
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.amber,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ).toList(),
                                        ),
                                      ),
                                    // AI Summary Preview
                                    if (hasTranscription)
                                      GestureDetector(
                                        onTap: () => _openSummaryPage(rec),
                                        child: Container(
                                          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.cyan.withOpacity(0.08),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: Colors.cyan.withOpacity(0.2)),
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Icon(Icons.auto_awesome, size: 14, color: Colors.cyan),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  (rec.summary != null && rec.summary!.isNotEmpty)
                                                      ? rec.summary!
                                                      : (rec.transcription!.length > 100
                                                          ? '${rec.transcription!.substring(0, 100)}...'
                                                          : rec.transcription!),
                                                  style: const TextStyle(
                                                    color: Colors.white60,
                                                    fontSize: 12,
                                                    height: 1.3,
                                                  ),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),

                                    Padding(
                                      padding:
                                          const EdgeInsets.fromLTRB(4, 4, 4, 8),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceEvenly,
                                        children: [
                                          _ActionButton(
                                            icon: hasTranscription
                                                ? Icons.text_snippet
                                                : Icons.transcribe,
                                            color: Colors.green,
                                            label: hasTranscription
                                                ? 'Диалог'
                                                : 'В текст',
                                            onTap: () => hasTranscription
                                                ? _openDialogueEditor(rec)
                                                : _transcribeRecording(rec),
                                          ),
                                          if (hasTranscription)
                                            _ActionButton(
                                              icon: Icons.auto_awesome,
                                              color: Colors.cyan,
                                              label: 'Суть',
                                              onTap: () => _openSummaryPage(rec),
                                            ),
                                          _ActionButton(
                                            icon: Icons.share,
                                            color: Colors.blue,
                                            label: 'Отправить',
                                            onTap: () => _showShareOptions(rec),
                                          ),
                                          _ActionButton(
                                            icon: Icons.play_arrow,
                                            color: Colors.white,
                                            label: 'Слушать',
                                            onTap: () => _playRecording(rec),
                                          ),
                                          _ActionButton(
                                            icon: Icons.delete_outline,
                                            color: Colors.red.withOpacity(0.7),
                                            label: 'Удалить',
                                            onTap: () =>
                                                _deleteRecording(rec.id),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: color.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
