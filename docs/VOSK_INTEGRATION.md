# VOSK Integration Guide for DictaPro

## Файлы
- `lib/services/vosk_custom_words_extended.dart` — 620 слов
- `lib/services/vosk_auto_correction_extended.dart` — 80+ паттернов
- `lib/services/transcription_service_updated.dart` — пример интеграции

## Как встроить

### Шаг 1: Добавить custom words в initModel()
```dart
import 'services/vosk_custom_words_extended.dart';

Future<void> initModel() async {
  // ... загрузка модели VOSK ...
  
  // Добавляем слова ПОСЛЕ загрузки модели
  VoskCustomWordsExtended.initWords(_recognizer);
}
```

### Шаг 2: Добавить авто-замену в processResult()
```dart
import 'services/vosk_auto_correction_extended.dart';

String processResult(String rawText) {
  // Авто-замена ошибок
  String corrected = VoskAutoCorrectionExtended.correctText(rawText);
  
  // ... остальная обработка ...
  
  return corrected;
}
```

## Что делает
- **Custom words:** Добавляет 620 слов в словарь VOSK (бренды, города, IT, медицина, юриспруденция)
- **Auto-correction:** Исправляет частые ошибки (разрывы слов, транслитерация, пропущенные буквы)

## Тестирование
- Записать фразу с "Роскосмос" → должно распознаться правильно
- Записать "рос космос" → авто-замена исправит на "Роскосмос"

## Дата: 2026-05-28
