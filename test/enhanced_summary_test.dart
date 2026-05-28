import 'package:flutter_test/flutter_test.dart';
import 'package:dictapro/services/enhanced_summary_service.dart';

void main() {
  group('EnhancedSummaryService', () {
    test('detects narrative text', () {
      final text = 'Шёл солдат на побывку. Притомился в пути. Есть хочется.';
      final type = EnhancedSummaryService.detectTextType(text);
      expect(type, TextType.narrative);
    });

    test('detects business text', () {
      final text = 'Мы решили запустить проект. Дедлайн — пятница. Ответственный — Иван.';
      final type = EnhancedSummaryService.detectTextType(text);
      expect(type, TextType.business);
    });

    test('summarizes narrative', () {
      final text = 'Шёл солдат на побывку. Притомился в пути. Есть хочется. '
          'Дошёл до деревни. Постучал в избу. Пустите дорожного человека. '
          'Дверь открыла старуха. Заходи служивый.';
      
      final summary = EnhancedSummaryService.generateSummary(text);
      
      expect(summary.type, TextType.narrative);
      expect(summary.title, contains('Солдат'));
      expect(summary.points.any((p) => p.contains('Герои')), true);
      expect(summary.points.any((p) => p.contains('Начало')), true);
    });

    test('summarizes business with decisions', () {
      final text = 'Мы решили запустить новый проект. '
          'Договорились о сроках. Дедлайн — 15 мая. '
          'Ответственный — Петров. Нужно подготовить презентацию.';
      
      final summary = EnhancedSummaryService.generateSummary(text);
      
      expect(summary.type, TextType.business);
      expect(summary.points.any((p) => p.contains('Решения')), true);
    });

    test('handles short text', () {
      final text = 'Привет мир';
      final summary = EnhancedSummaryService.generateSummary(text);
      
      expect(summary.points.isNotEmpty, true);
    });

    test('formats output', () {
      final result = SummaryResult(
        title: 'Тест',
        type: TextType.general,
        points: ['Пункт 1', 'Пункт 2'],
        fullText: 'Текст',
      );
      
      expect(result.formatted, contains('=== Тест ==='));
      expect(result.formatted, contains('Пункт 1'));
    });
  });
}
