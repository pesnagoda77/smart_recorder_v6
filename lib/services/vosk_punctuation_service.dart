import 'package:flutter/material.dart';

/// Пунктуация для VOSK транскрипции
/// Добавляет точки и запятые на основе пауз в речи
class VoskPunctuationService {
  static const double PAUSE_SENTENCE = 1.2;  // сек — конец предложения
  static const double PAUSE_COMMA = 0.4;     // сек — запятая
  static const double CONFIDENCE_THRESHOLD = 0.7;

  /// Структура слова из VOSK JSON
  static String punctuate(List<VoskWord> words) {
    if (words.isEmpty) return '';

    StringBuffer result = StringBuffer();
    
    for (int i = 0; i < words.length; i++) {
      VoskWord word = words[i];
      
      // Заглавная буква в начале или после точки
      String text = word.word;
      if (i == 0 || _isAfterSentenceEnd(result)) {
        text = _capitalize(text);
      }
      
      result.write(text);
      
      // Пунктуация между словами
      if (i < words.length - 1) {
        double pause = words[i + 1].start - word.end;
        String punctuation = _getPunctuation(pause, word.confidence);
        result.write(punctuation);
      }
    }
    
    // Точка в конце, если нет знака
    if (!_endsWithPunctuation(result.toString())) {
      result.write('.');
    }
    
    return result.toString();
  }

  /// Определяет знак препинания на основе паузы
  static String _getPunctuation(double pause, double confidence) {
    if (pause > PAUSE_SENTENCE) return '. ';
    if (pause > PAUSE_COMMA) return ', ';
    return ' ';
  }

  /// Проверяет, заканчивается ли текст знаком препинания
  static bool _isAfterSentenceEnd(StringBuffer buffer) {
    String text = buffer.toString().trimRight();
    return text.endsWith('.') || text.endsWith('?') || text.endsWith('!');
  }

  /// Делает первую букву заглавной
  static String _capitalize(String word) {
    if (word.isEmpty) return word;
    return word[0].toUpperCase() + word.substring(1);
  }

  /// Проверяет, заканчивается ли текст знаком препинания
  static bool _endsWithPunctuation(String text) {
    return text.trimRight().endsWith('.') || 
           text.trimRight().endsWith('?') || 
           text.trimRight().endsWith('!');
  }
}

/// Структура слова из VOSK JSON
class VoskWord {
  final String word;
  final double start;
  final double end;
  final double confidence;

  VoskWord({
    required this.word,
    required this.start,
    required this.end,
    required this.confidence,
  });

  /// Создаёт из JSON
  factory VoskWord.fromJson(Map<String, dynamic> json) {
    return VoskWord(
      word: json['word'] as String,
      start: (json['start'] as num).toDouble(),
      end: (json['end'] as num).toDouble(),
      confidence: (json['conf'] as num).toDouble(),
    );
  }
}
