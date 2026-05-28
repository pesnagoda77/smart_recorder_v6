import 'package:flutter/material.dart';
import 'vosk_custom_words_extended.dart';
import 'vosk_auto_correction_extended.dart';

class TranscriptionService {
  dynamic _recognizer;
  bool _isInitialized = false;

  /// Инициализация модели VOSK
  /// Вызывается один раз при старте приложения
  Future<void> initModel() async {
    // ... существующая инициализация VOSK ...
    
    // Добавляем custom words в словарь модели
    // Важно: вызывать ПОСЛЕ загрузки модели, но ДО начала распознавания
    VoskCustomWordsExtended.initWords(_recognizer);
    
    _isInitialized = true;
  }

  /// Обработка результата транскрипции
  /// Вызывается при каждом chunk'е
  String processResult(String rawText) {
    // 1. Авто-замена ошибок распознавания
    String corrected = VoskAutoCorrectionExtended.correctText(rawText);
    
    // 2. Пунктуация (делает Фил — timestamps из VOSK JSON)
    // String punctuated = VoskPunctuationService.punctuate(words);
    
    return corrected;
  }

  /// Перезагрузка custom words (если пользователь меняет список)
  Future<void> reloadCustomWords(List<String> newWords) async {
    // Перезагружаем модель с новым списком слов
    // TODO: реализовать если нужно
  }
}
