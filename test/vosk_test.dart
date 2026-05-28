import 'package:flutter_test/flutter_test.dart';
import 'package:dictapro/services/vosk_custom_words_extended.dart';
import 'package:dictapro/services/vosk_auto_correction_extended.dart';

void main() {
  group('VoskCustomWordsExtended', () {
    test('has 620 words', () {
      expect(VoskCustomWordsExtended.allWords.length, 620);
    });

    test('contains space words', () {
      expect(VoskCustomWordsExtended.wordCategories['space'], contains('Роскосмос'));
      expect(VoskCustomWordsExtended.wordCategories['space'], contains('космонавтика'));
    });

    test('contains brand words', () {
      expect(VoskCustomWordsExtended.wordCategories['brands_ru'], contains('Газпром'));
      expect(VoskCustomWordsExtended.wordCategories['brands_ru'], contains('Сбербанк'));
    });

    test('contains city words', () {
      expect(VoskCustomWordsExtended.wordCategories['cities'], contains('Москва'));
      expect(VoskCustomWordsExtended.wordCategories['cities'], contains('Петербург'));
    });
  });

  group('VoskAutoCorrectionExtended', () {
    test('fixes split words', () {
      expect(
        VoskAutoCorrectionExtended.correctText('рос космос'),
        'Роскосмос',
      );
    });

    test('fixes transcription errors', () {
      expect(
        VoskAutoCorrectionExtended.correctText('табачного'),
        'табачного',
      );
    });

    test('fixes transliteration', () {
      expect(
        VoskAutoCorrectionExtended.correctText('джаваскрипт'),
        'JavaScript',
      );
    });

    test('fixes brands', () {
      expect(
        VoskAutoCorrectionExtended.correctText('сбер банк'),
        'Сбербанк',
      );
    });

    test('fixes cities', () {
      expect(
        VoskAutoCorrectionExtended.correctText('питер'),
        'Петербург',
      );
    });

    test('preserves correct text', () {
      expect(
        VoskAutoCorrectionExtended.correctText('привет мир'),
        'привет мир',
      );
    });

    test('fixes capitalization after period', () {
      expect(
        VoskAutoCorrectionExtended.correctText('привет. мир'),
        'привет. Мир',
      );
    });

    test('fixes repeated spaces', () {
      expect(
        VoskAutoCorrectionExtended.correctText('привет  мир'),
        'привет мир',
      );
    });
  });
}
