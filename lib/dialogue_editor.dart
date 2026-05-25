import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'audio_service.dart';
import 'export_service.dart';

class DialogueEditor extends StatefulWidget {
  final Recording recording;

  const DialogueEditor({super.key, required this.recording});

  @override
  State<DialogueEditor> createState() => _DialogueEditorState();
}

class _DialogueEditorState extends State<DialogueEditor> {
  late List<DialogueSegment> _segments;
  final _textControllers = <TextEditingController>[];
  final _focusNodes = <FocusNode>[];
  final _lastCursorPositions = <int>[];

  @override
  void initState() {
    super.initState();
    _segments = widget.recording.segments?.map((s) {
          return DialogueSegment.fromMap(Map<String, dynamic>.from(s));
        }).toList() ??
        [];

    if (_segments.isEmpty && widget.recording.transcription != null) {
      _segments = [
        DialogueSegment(speaker: 'A', text: widget.recording.transcription!)
      ];
    }

    _initControllers();
  }

  void _initControllers() {
    for (var c in _textControllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    _textControllers.clear();
    _focusNodes.clear();
    _lastCursorPositions.clear();

    for (var segment in _segments) {
      final controller = TextEditingController(text: segment.text);
      final focusNode = FocusNode();

      controller.addListener(() {
        final cursorPos = controller.selection.baseOffset;
        if (cursorPos >= 0) {
          final idx = _textControllers.indexOf(controller);
          if (idx >= 0 && idx < _lastCursorPositions.length) {
            _lastCursorPositions[idx] = cursorPos;
          }
        }
      });

      _textControllers.add(controller);
      _focusNodes.add(focusNode);
      _lastCursorPositions.add(segment.text.length);
    }
  }

  void _splitAtCursor(int index) {
    final controller = _textControllers[index];
    final cursorPos = controller.selection.baseOffset;

    if (cursorPos <= 0 || cursorPos >= controller.text.length) {
      final savedPos = _lastCursorPositions[index];
      if (savedPos <= 0 || savedPos >= controller.text.length) {
        _splitSegment(index, controller.text.length ~/ 2);
        return;
      }
      _splitSegment(index, savedPos);
      return;
    }

    _splitSegment(index, cursorPos);
  }

  void _splitSegment(int index, int cursorPosition) {
    final text = _textControllers[index].text;
    if (cursorPosition <= 0 || cursorPosition >= text.length) return;

    final before = text.substring(0, cursorPosition).trim();
    final after = text.substring(cursorPosition).trim();

    if (before.isEmpty || after.isEmpty) return;

    setState(() {
      _segments[index].text = before;
      final newSpeaker = _segments[index].speaker == 'A' ? 'B' : 'A';
      _segments.insert(
          index + 1, DialogueSegment(speaker: newSpeaker, text: after));
      _initControllers();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (index + 1 < _focusNodes.length) {
        _focusNodes[index + 1].requestFocus();
      }
    });
  }

  void _mergeWithPrevious(int index) {
    if (index <= 0) return;

    setState(() {
      _segments[index - 1].text += ' ${_segments[index].text}';
      _segments.removeAt(index);
      _initControllers();
    });
  }

  void _toggleSpeaker(int index) {
    setState(() {
      _segments[index].speaker = _segments[index].speaker == 'A' ? 'B' : 'A';
    });
  }

  void _deleteSegment(int index) {
    if (_segments.length <= 1) return;

    setState(() {
      _segments.removeAt(index);
      _initControllers();
    });
  }

  Future<void> _save() async {
    for (int i = 0; i < _segments.length; i++) {
      _segments[i].text = _textControllers[i].text;
    }

    final fullText = _segments.map((s) => '${s.speaker}: ${s.text}').join('\n');
    widget.recording.transcription = fullText;
    widget.recording.segments = _segments.map((s) => s.toMap()).toList();

    await AudioService().updateRecording(widget.recording);

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  void _copyToClipboard() {
    final text = _segments.map((s) => '${s.speaker}: ${s.text}').join('\n');
    ExportService.copyToClipboard(text);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Скопировано в буфер обмена')),
    );
  }

  void _shareText() {
    final text = _segments.map((s) => '${s.speaker}: ${s.text}').join('\n');
    ExportService.shareText(text);
  }

  void _exportHtml() async {
    final html = ExportService.formatTranscriptHtml(widget.recording);
    final fileName = 'transcript_${widget.recording.id}';
    final path = await ExportService.saveAsTxt(html, fileName);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('HTML сохранён: $path')),
    );
  }

  @override
  void dispose() {
    for (var c in _textControllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Редактировать диалог'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Копировать текст',
            onPressed: _copyToClipboard,
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Поделиться',
            onPressed: _shareText,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'html') _exportHtml();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'html',
                child: Row(
                  children: [
                    Icon(Icons.code, size: 20),
                    SizedBox(width: 8),
                    Text('Экспорт HTML'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Сохранить',
            onPressed: _save,
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _segments.length,
        itemBuilder: (context, index) {
          final segment = _segments[index];
          final isA = segment.speaker == 'A';

          return Align(
            alignment: isA ? Alignment.centerLeft : Alignment.centerRight,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isA
                    ? Colors.blue.withOpacity(0.3)
                    : Colors.green.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isA ? Colors.blue : Colors.green,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Говорящий ${segment.speaker}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isA ? Colors.blue[300] : Colors.green[300],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.call_split, size: 18),
                            color: Colors.white70,
                            tooltip: 'Разделить по курсору',
                            onPressed: () => _splitAtCursor(index),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(
                              isA ? Icons.person_2 : Icons.person,
                              size: 18,
                            ),
                            color: Colors.white70,
                            tooltip: 'Поменять говорящего',
                            onPressed: () => _toggleSpeaker(index),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          if (_segments.length > 1) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete,
                                  size: 18, color: Colors.red),
                              tooltip: 'Удалить',
                              onPressed: () => _deleteSegment(index),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                          if (index > 0) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.merge_type, size: 18),
                              color: Colors.white70,
                              tooltip: 'Объединить с предыдущей',
                              onPressed: () => _mergeWithPrevious(index),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _textControllers[index],
                    focusNode: _focusNodes[index],
                    maxLines: null,
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'Введите текст...',
                      hintStyle: TextStyle(color: Colors.white30),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
