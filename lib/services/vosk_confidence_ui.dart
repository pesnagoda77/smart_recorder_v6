import 'package:flutter/material.dart';

/// Confidence UI для VOSK транскрипции
/// Подсвечивает слова с низкой уверенностью
class ConfidenceTextWidget extends StatelessWidget {
  final String text;
  final double confidence;
  final bool isEditing;

  const ConfidenceTextWidget({
    required this.text,
    required this.confidence,
    this.isEditing = false,
  });

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color borderColor;
    
    if (confidence > 0.9) {
      backgroundColor = Colors.transparent;
      borderColor = Colors.transparent;
    } else if (confidence >= 0.7) {
      backgroundColor = Color(0xFFFFF3CD);
      borderColor = Color(0xFFFFC107);
    } else {
      backgroundColor = Color(0xFFF8D7DA);
      borderColor = Color(0xFFDC3545);
    }

    return Container(
      padding: isEditing ? EdgeInsets.symmetric(horizontal: 4, vertical: 2) : EdgeInsets.zero,
      decoration: isEditing ? BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: borderColor, width: 1),
        borderRadius: BorderRadius.circular(4),
      ) : null,
      child: Text(
        text,
        style: TextStyle(
          color: Colors.black,
          backgroundColor: isEditing ? null : backgroundColor,
        ),
      ),
    );
  }
}

/// Алерт о низкой уверенности
class ConfidenceAlertWidget extends StatelessWidget {
  final int lowConfidenceCount;
  final VoidCallback onFixPressed;

  const ConfidenceAlertWidget({
    required this.lowConfidenceCount,
    required this.onFixPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (lowConfidenceCount == 0) return SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(12),
      margin: EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Color(0xFFFFF3CD),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Color(0xFFFFC107)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFFFC107)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '$lowConfidenceCount ${lowConfidenceCount == 1 ? 'слово' : 'слова'} с низкой уверенностью',
              style: TextStyle(color: Color(0xFF856404)),
            ),
          ),
          TextButton(
            onPressed: onFixPressed,
            child: Text('Исправить'),
          ),
        ],
      ),
    );
  }
}

/// Настройки отображения confidence
class ConfidenceSettings {
  bool showConfidenceColors = true;
  bool showFixButton = true;
  double confidenceThreshold = 0.7;
}
