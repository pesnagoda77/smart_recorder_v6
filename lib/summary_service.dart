import 'dart:math';

import 'dart:math' as math;

/// AI-саммари записей через TextRank.
///
/// Извлекает:
/// 1. Краткое содержание (ключевые предложения)
/// 2. Ключевые решения (по маркерам)
/// 3. Сводка по говорящим
class SummaryService {

  // ========== TextRank: Краткое содержание ==========

  static List<String> getSummary(String text, {int sentencesCount = 3}) {
    final sentences = _splitSentences(text);

    // Короткий текст — просто берём первые N фраз
    if (sentences.length <= sentencesCount) {
      if (sentences.isNotEmpty) return sentences;
      // Fallback: если совсем короткий — первые 150 символов
      final clean = text.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (clean.length > 10) {
        final end = clean.length.clamp(30, 200);
        // Не обрезаем посередине слова
        final cut = clean.substring(0, end);
        final lastSpace = cut.lastIndexOf(' ');
        if (lastSpace > end * 0.7) {
          return [clean.substring(0, lastSpace)];
        }
        return [cut];
      }
      return ['Текст слишком короткий для саммари'];
    }

    final wordsPerSentence = sentences.map(_tokenize).toList();

    // Если после токенизации почти ничего не осталось
    final nonEmptyCount = wordsPerSentence.where((w) => w.isNotEmpty).length;
    if (nonEmptyCount < 2) {
      return sentences.take(sentencesCount).toList();
    }

    final wordFreq = _buildWordFreq(wordsPerSentence);
    final weights = _calcSentenceWeights(wordsPerSentence, wordFreq);

    final scored = <Map<String, dynamic>>[];
    for (int i = 0; i < sentences.length; i++) {
      scored.add({'index': i, 'sentence': sentences[i], 'weight': weights[i]});
    }

    scored.sort((a, b) => (b['weight'] as double).compareTo(a['weight'] as double));

    final topIndices = scored
        .take(sentencesCount)
        .map((e) => e['index'] as int)
        .toList()
      ..sort();

    return topIndices.map((i) => sentences[i]).toList();
  }

  // ========== Ключевые решения ==========

  static final _decisionPatterns = RegExp(
    r'(решили|договорились|приняли решение|нужно|необходимо|должны|обязаны|'
    r'будем|планируем|запланировано|дедлайн|срок|до \d+|'
    r'поручил|ответственный|ответственность|'
    r'следующий шаг|action item|задача:|'
    r'надо|стоит|лучше|давай|купи|позвони|напомни|сделай|запиши|'
    r'пойд[её]м|поедем|встретимся|забудь|не забудь|'
    r'приходи|приезжай|отправь|напиши|скажи|передай'
    r')([^.,!?]*[.,!?]?)',
    caseSensitive: false,
  );

  static List<String> getDecisions(String text) {
    final matches = _decisionPatterns.allMatches(text);
    final results = <String>[];
    for (final m in matches) {
      var phrase = m.group(0)!.trim();
      if (phrase.length > 300) phrase = phrase.substring(0, 300);
      results.add(phrase);
    }
    return results.isEmpty ? [] : results;
  }

  // ========== Кто что сказал ==========

  static Map<String, List<String>> getSpeakerSummary(
    List<Map<String, dynamic>> segments,
  ) {
    final map = <String, List<String>>{};
    for (final seg in segments) {
      final speaker = seg['speaker'] as String? ?? '?';
      final text = seg['text'] as String? ?? '';
      map.putIfAbsent(speaker, () => []);
      map[speaker]!.add(text);
    }
    return map;
  }

  static List<Map<String, dynamic>> getSpeakerStats(
    List<Map<String, dynamic>> segments,
  ) {
    final speakerMap = getSpeakerSummary(segments);
    final stats = <Map<String, dynamic>>[];

    for (final entry in speakerMap.entries) {
      final allText = entry.value.join(' ');
      final wordCount = _tokenize(allText).length;
      final topWords = _topWords(allText, 5);

      stats.add({
        'speaker': entry.key,
        'utteranceCount': entry.value.length,
        'wordCount': wordCount,
        'topWords': topWords,
        'summary': getSummary(allText, sentencesCount: 2),
      });
    }

    stats.sort((a, b) => (b['wordCount'] as int).compareTo(a['wordCount'] as int));
    return stats;
  }

  // ========== Внутренние утилиты TextRank ==========

  static List<String> _splitSentences(String text) {
    // Сначала пробуем разделить по знакам препинания
    final pattern = RegExp(r'[.!?]+\s*');
    final raw = text.split(pattern);
    var sentences = raw
        .map((s) => s.trim())
        .where((s) => s.length > 3 && s.contains(RegExp(r'[а-яА-Я\w]')))
        .toList();

    // Если получилось мало предложений (VOSK не ставит точки),
    // разбиваем по длине — каждые 8-12 слов
    if (sentences.length <= 1 && text.length > 40) {
      final words = text.split(RegExp(r'\s+'));
      sentences = [];
      final chunkSize = words.length <= 20 ? 8 : 12;
      for (int i = 0; i < words.length; i += chunkSize) {
        final end = (i + chunkSize).clamp(0, words.length);
        final chunk = words.sublist(i, end).join(' ');
        if (chunk.length > 3) {
          sentences.add(chunk);
        }
      }
    }

    return sentences;
  }

  static List<String> _tokenize(String sentence) {
    return sentence
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s\-]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && !_isStopWord(w))
        .toList();
  }

  static bool _isStopWord(String word) {
    const stopWords = {
      'и', 'в', 'во', 'не', 'что', 'он', 'на', 'я', 'с', 'со', 'как', 'а', 'то',
      'все', 'она', 'так', 'его', 'но', 'да', 'ты', 'к', 'у', 'же', 'вы', 'за',
      'бы', 'по', 'только', 'ее', 'мне', 'было', 'вот', 'от', 'меня', 'еще',
      'нет', 'о', 'из', 'ему', 'теперь', 'когда', 'даже', 'ну', 'вдруг', 'ли',
      'если', 'уже', 'или', 'ни', 'быть', 'был', 'него', 'до', 'вас', 'нибудь',
      'опять', 'уж', 'вам', 'ведь', 'там', 'потом', 'себя', 'ничего', 'ей',
      'может', 'они', 'тут', 'где', 'есть', 'надо', 'ней', 'для', 'мы', 'тебя',
      'их', 'чем', 'была', 'сам', 'чтоб', 'без', 'будто', 'чего', 'раз',
      'тоже', 'себе', 'под', 'будет', 'ж', 'тогда', 'кто', 'этот', 'того',
      'потому', 'этого', 'какой', 'совсем', 'ним', 'здесь', 'этом', 'один',
      'почти', 'мой', 'тем', 'чтобы', 'нее', 'сейчас', 'были', 'куда',
      'зачем', 'всех', 'можно', 'про', 'наконец', 'два', 'об', 'другой',
      'хоть', 'после', 'над', 'больше', 'тот', 'через', 'эти', 'нас',
      'всего', 'них', 'какая', 'много', 'разве', 'три', 'эту', 'моя',
      'впрочем', 'хорошо', 'свою', 'этой', 'перед', 'иногда', 'лучше',
      'чуть', 'том', 'нельзя', 'такой', 'им', 'более', 'всегда', 'конечно',
      'всю', 'между',
    };
    return stopWords.contains(word);
  }

  static Map<String, int> _buildWordFreq(List<List<String>> wordsPerSentence) {
    final freq = <String, int>{};
    for (final words in wordsPerSentence) {
      for (final w in words) {
        freq[w] = (freq[w] ?? 0) + 1;
      }
    }
    return freq;
  }

  static List<double> _calcSentenceWeights(
    List<List<String>> wordsPerSentence,
    Map<String, int> wordFreq,
  ) {
    final n = wordsPerSentence.length;
    final weights = List<double>.filled(n, 0.0);

    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        if (i == j) continue;
        final sim = _cosineSimilarity(wordsPerSentence[i], wordsPerSentence[j], wordFreq);
        weights[i] += sim;
      }
    }

    // Нормализуем
    final maxWeight = weights.reduce(math.max);
    if (maxWeight > 0) {
      for (int i = 0; i < n; i++) {
        weights[i] /= maxWeight;
      }
    }

    return weights;
  }

  static double _cosineSimilarity(
    List<String> a,
    List<String> b,
    Map<String, int> wordFreq,
  ) {
    final allWords = <String>{...a, ...b};
    double dot = 0;
    double normA = 0;
    double normB = 0;

    for (final w in allWords) {
      final idf = math.log(1 + (wordFreq[w] ?? 0));
      final wa = a.where((x) => x == w).length * idf;
      final wb = b.where((x) => x == w).length * idf;
      dot += wa * wb;
      normA += wa * wa;
      normB += wb * wb;
    }

    if (normA == 0 || normB == 0) return 0;
    return dot / (math.sqrt(normA) * math.sqrt(normB));
  }

  static List<MapEntry<String, int>> _topWords(String text, int count) {
    final tokens = _tokenize(text);
    final freq = <String, int>{};
    for (final t in tokens) {
      freq[t] = (freq[t] ?? 0) + 1;
    }
    final sorted = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(count).toList();
  }
}
