import 'dart:math' as math;

/// Улучшенное саммари с контекстным анализом
/// Определяет тип текста и применяет соответствующий алгоритм
class EnhancedSummaryService {
  
  // ========== Определение типа текста ==========
  
  static TextType detectTextType(String text) {
    final lower = text.toLowerCase();
    
    // Признаки совещания/делового разговора
    final businessMarkers = [
      'решили', 'договорились', 'приняли решение', 'дедлайн', 'срок',
      'ответственный', 'задача', 'поручение', 'совещание', 'встреча',
      'обсудили', 'утвердили', 'согласовали', 'план', 'бюджет',
      'отчёт', 'презентация', 'клиент', 'заказчик', 'проект',
    ];
    
    // Признаки художественного текста
    final narrativeMarkers = [
      'шёл', 'пришёл', 'пошёл', 'взял', 'дал', 'сказал', 'ответил',
      'спросил', 'попросил', 'стал', 'сел', 'лежал', 'стоял',
      'старуха', 'солдат', 'царь', 'царевна', 'баба', 'дед',
      'раз', 'два', 'три', 'жили-были', 'однажды', 'давным-давно',
    ];
    
    // Признаки лекции/образовательного
    final educationalMarkers = [
      'означает', 'представляет', 'является', 'состоит', 'включает',
      'например', 'то есть', 'другими словами', 'следовательно',
      'теория', 'метод', 'алгоритм', 'процесс', 'система',
      'функция', 'параметр', 'переменная', 'константа',
    ];
    
    int businessScore = businessMarkers.where((m) => lower.contains(m)).length;
    int narrativeScore = narrativeMarkers.where((m) => lower.contains(m)).length;
    int educationalScore = educationalMarkers.where((m) => lower.contains(m)).length;
    
    if (businessScore >= 2) return TextType.business;
    if (educationalScore >= 2) return TextType.educational;
    if (narrativeScore >= 3) return TextType.narrative;
    
    return TextType.general;
  }
  
  // ========== Главный метод ==========
  
  static SummaryResult generateSummary(String text, {int maxSentences = 5}) {
    final type = detectTextType(text);
    
    switch (type) {
      case TextType.narrative:
        return _summarizeNarrative(text, maxSentences);
      case TextType.business:
        return _summarizeBusiness(text, maxSentences);
      case TextType.educational:
        return _summarizeEducational(text, maxSentences);
      case TextType.general:
        return _summarizeGeneral(text, maxSentences);
    }
  }
  
  // ========== Сказка / Художественный текст ==========
  
  static SummaryResult _summarizeNarrative(String text, int maxSentences) {
    final sentences = _splitIntoSentences(text);
    if (sentences.isEmpty) return SummaryResult.empty();
    
    // Находим героев
    final characters = _extractCharacters(text);
    
    // Находим ключевые события (глаголы действия)
    final events = _extractKeyEvents(sentences);
    
    // Структура: завязка → кульминация → развязка
    final beginning = sentences.first;
    final middle = sentences.length > 2 
        ? sentences[sentences.length ~/ 2] 
        : null;
    final ending = sentences.last;
    
    final summaryPoints = <String>[];
    
    if (characters.isNotEmpty) {
      summaryPoints.add('Герои: ${characters.take(3).join(', ')}');
    }
    
    summaryPoints.add('Начало: $_cleanSentence(beginning)');
    
    if (events.length > 1) {
      summaryPoints.add('Ключевые события:');
      for (var i = 0; i < math.min(events.length - 1, 3); i++) {
        summaryPoints.add('  • ${_cleanSentence(events[i])}');
      }
    }
    
    summaryPoints.add('Конец: $_cleanSentence(ending)');
    
    // Мораль (последние 2 предложения часто содержат)
    final moral = _extractMoral(sentences);
    if (moral != null) {
      summaryPoints.add('Вывод: $_cleanSentence(moral)');
    }
    
    return SummaryResult(
      title: _generateTitle(characters, events),
      type: TextType.narrative,
      points: summaryPoints,
      fullText: text,
    );
  }
  
  // ========== Совещание / Деловой текст ==========
  
  static SummaryResult _summarizeBusiness(String text, int maxSentences) {
    final sentences = _splitIntoSentences(text);
    final decisions = _extractDecisions(text);
    final deadlines = _extractDeadlines(text);
    final responsible = _extractResponsible(text);
    
    final summaryPoints = <String>[];
    
    if (decisions.isNotEmpty) {
      summaryPoints.add('Решения:');
      for (final d in decisions.take(5)) {
        summaryPoints.add('  • $d');
      }
    }
    
    if (deadlines.isNotEmpty) {
      summaryPoints.add('Сроки:');
      for (final dl in deadlines.take(3)) {
        summaryPoints.add('  • $dl');
      }
    }
    
    if (responsible.isNotEmpty) {
      summaryPoints.add('Ответственные:');
      for (final r in responsible.take(3)) {
        summaryPoints.add('  • $r');
      }
    }
    
    // Если ничего не нашли — обычное саммари
    if (summaryPoints.isEmpty) {
      return _summarizeGeneral(text, maxSentences);
    }
    
    return SummaryResult(
      title: 'Результаты совещания',
      type: TextType.business,
      points: summaryPoints,
      fullText: text,
    );
  }
  
  // ========== Лекция / Образовательный ==========
  
  static SummaryResult _summarizeEducational(String text, int maxSentences) {
    final sentences = _splitIntoSentences(text);
    final definitions = _extractDefinitions(text);
    final keyConcepts = _extractKeyConcepts(text);
    
    final summaryPoints = <String>[];
    
    if (definitions.isNotEmpty) {
      summaryPoints.add('Определения:');
      for (final d in definitions.take(3)) {
        summaryPoints.add('  • $d');
      }
    }
    
    if (keyConcepts.isNotEmpty) {
      summaryPoints.add('Ключевые понятия: ${keyConcepts.take(5).join(', ')}');
    }
    
    // Основные тезисы через TextRank
    final mainPoints = _textRankSummary(sentences, maxSentences);
    if (mainPoints.isNotEmpty) {
      summaryPoints.add('Основные тезисы:');
      for (final p in mainPoints) {
        summaryPoints.add('  • $p');
      }
    }
    
    return SummaryResult(
      title: 'Краткое содержание лекции',
      type: TextType.educational,
      points: summaryPoints,
      fullText: text,
    );
  }
  
  // ========== Общий случай ==========
  
  static SummaryResult _summarizeGeneral(String text, int maxSentences) {
    final sentences = _splitIntoSentences(text);
    final summary = _textRankSummary(sentences, maxSentences);
    
    return SummaryResult(
      title: 'Краткое содержание',
      type: TextType.general,
      points: summary.isEmpty ? [text.substring(0, math.min(200, text.length))] : summary,
      fullText: text,
    );
  }
  
  // ========== Вспомогательные методы ==========
  
  static List<String> _splitIntoSentences(String text) {
    // Пробуем разделить по знакам препинания
    final pattern = RegExp(r'[.!?]+\s*');
    var sentences = text
        .split(pattern)
        .map((s) => s.trim())
        .where((s) => s.length > 3)
        .toList();
    
    // Если мало предложений — режем по длине
    if (sentences.length <= 2 && text.length > 40) {
      final words = text.split(RegExp(r'\s+'));
      sentences = [];
      final chunkSize = words.length <= 20 ? 8 : 12;
      for (int i = 0; i < words.length; i += chunkSize) {
        final end = (i + chunkSize).clamp(0, words.length);
        final chunk = words.sublist(i, end).join(' ');
        if (chunk.length > 3) sentences.add(chunk);
      }
    }
    
    return sentences;
  }
  
  static List<String> _extractCharacters(String text) {
    // Ищем имена собственные (заглавные буквы)
    final names = RegExp(r'\b[А-Я][а-яё]{2,}\b');
    final matches = names.allMatches(text);
    final unique = <String>{};
    for (final m in matches) {
      final name = m.group(0)!;
      // Исключаем общеупотребительные
      if (!_isCommonWord(name)) {
        unique.add(name);
      }
    }
    return unique.toList();
  }
  
  static List<String> _extractKeyEvents(List<String> sentences) {
    // Ищем предложения с глаголами действия
    final actionVerbs = RegExp(
      r'\b(шёл|пришёл|взял|дал|сказал|спросил|попросил|'
      r'стал|сел|лежал|пошёл|пришёл|ушёл|вернулся|'
      r'сварил|пожарил|съел|выпил|купил|продал|'
      r'нашёл|потерял|спас|победил|проиграл)\b',
      caseSensitive: false,
    );
    
    return sentences
        .where((s) => actionVerbs.hasMatch(s))
        .toList();
  }
  
  static String? _extractMoral(List<String> sentences) {
    // Мораль часто в конце (последние 2 предложения)
    if (sentences.length < 2) return null;
    
    final last = sentences.last;
    final secondLast = sentences.length > 1 ? sentences[sentences.length - 2] : null;
    
    // Признаки морали
    final moralMarkers = [
      'вот и', 'так и', 'с тех пор', 'с того времени',
      'а ты', 'знай', 'помни', 'не забывай',
      'вот вам', 'вот тебе', 'вот и сказке',
    ];
    
    for (final marker in moralMarkers) {
      if (last.toLowerCase().contains(marker)) return last;
      if (secondLast != null && secondLast.toLowerCase().contains(marker)) {
        return secondLast;
      }
    }
    
    return last.length < 100 ? last : null;
  }
  
  static List<String> _extractDecisions(String text) {
    final decisionPatterns = RegExp(
      r'\b(решили|договорились|приняли решение|утвердили|'
      r'согласовали|назначили|определили|установили|'
      r'поручили|поручил|поручила|поручено|'
      r'нужно|необходимо|требуется|следует|'
      r'будем|планируем|собираемся|намерены)\b'
      r'[^.!?]{10,150}[.!?]?',
      caseSensitive: false,
    );
    
    final matches = decisionPatterns.allMatches(text);
    return matches.map((m) => m.group(0)!.trim()).toList();
  }
  
  static List<String> _extractDeadlines(String text) {
    final deadlinePatterns = RegExp(
      r'\b(до\s+\d+|в\s+\d+|к\s+\d+|срок|дедлайн|'
      r'завтра|послезавтра|в\s+понедельник|во\s+вторник|'
      r'в\s+среду|в\s+четверг|в\s+пятницу|'
      r'в\s+субботу|в\s+воскресенье|'
      r'через\s+\d+\s+(дн|час|недел|месяц))\b'
      r'[^.!?]{5,100}[.!?]?',
      caseSensitive: false,
    );
    
    final matches = deadlinePatterns.allMatches(text);
    return matches.map((m) => m.group(0)!.trim()).toList();
  }
  
  static List<String> _extractResponsible(String text) {
    final respPatterns = RegExp(
      r'\b(ответственный|ответственная|ответственные|'
      r'куратор|кураторы|исполнитель|исполнители|'
      r'руководитель|руководители|координатор)\b'
      r'[^.!?]{5,100}[.!?]?',
      caseSensitive: false,
    );
    
    final matches = respPatterns.allMatches(text);
    return matches.map((m) => m.group(0)!.trim()).toList();
  }
  
  static List<String> _extractDefinitions(String text) {
    final defPatterns = RegExp(
      r'\b([А-Я][а-яё\s]+)\s+(это|—|–|−|есть|представляет|'
      r'является|означает|обозначает)\s+'
      r'[^.!?]{10,200}[.!?]?',
      caseSensitive: false,
    );
    
    final matches = defPatterns.allMatches(text);
    return matches.map((m) => m.group(0)!.trim()).toList();
  }
  
  static List<String> _extractKeyConcepts(String text) {
    // Ищем термины (словосочетания с заглавными или в кавычках)
    final concepts = RegExp(
      r'\b[А-Я][а-яёA-Za-z\s\-]{2,30}\b|'
      r'"[^"]{2,30}"|'
      r'«[^»]{2,30}»',
    );
    
    final matches = concepts.allMatches(text);
    final unique = <String>{};
    for (final m in matches) {
      final concept = m.group(0)!.trim();
      if (concept.length > 3 && !_isCommonWord(concept)) {
        unique.add(concept);
      }
    }
    return unique.toList();
  }
  
  static List<String> _textRankSummary(List<String> sentences, int count) {
    if (sentences.length <= count) return sentences;
    
    // Упрощённый TextRank
    final wordsPerSentence = sentences.map((s) => 
      s.toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && !_isStopWord(w))
        .toList()
    ).toList();
    
    final wordFreq = <String, int>{};
    for (final words in wordsPerSentence) {
      for (final w in words) {
        wordFreq[w] = (wordFreq[w] ?? 0) + 1;
      }
    }
    
    final weights = <double>[];
    for (int i = 0; i < sentences.length; i++) {
      double weight = 0;
      for (int j = 0; j < sentences.length; j++) {
        if (i == j) continue;
        weight += _similarity(wordsPerSentence[i], wordsPerSentence[j], wordFreq);
      }
      weights.add(weight);
    }
    
    final indexed = List.generate(sentences.length, (i) => 
      {'index': i, 'weight': weights[i]}
    );
    indexed.sort((a, b) => (b['weight'] as double).compareTo(a['weight'] as double));
    
    final topIndices = indexed
        .take(count)
        .map((e) => e['index'] as int)
        .toList()
      ..sort();
    
    return topIndices.map((i) => sentences[i]).toList();
  }
  
  static double _similarity(List<String> a, List<String> b, Map<String, int> freq) {
    final all = <String>{...a, ...b};
    double dot = 0, normA = 0, normB = 0;
    
    for (final w in all) {
      final idf = math.log(1 + (freq[w] ?? 0));
      final wa = a.where((x) => x == w).length * idf;
      final wb = b.where((x) => x == w).length * idf;
      dot += wa * wb;
      normA += wa * wa;
      normB += wb * wb;
    }
    
    if (normA == 0 || normB == 0) return 0;
    return dot / (math.sqrt(normA) * math.sqrt(normB));
  }
  
  static String _generateTitle(List<String> characters, List<String> events) {
    if (characters.isNotEmpty && events.isNotEmpty) {
      return '${characters.first}: ${events.first.substring(0, math.min(50, events.first.length))}...';
    }
    if (characters.isNotEmpty) {
      return 'История о ${characters.first}';
    }
    return 'Краткое содержание';
  }
  
  static String _cleanSentence(String sentence) {
    return sentence
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .substring(0, math.min(150, sentence.length));
  }
  
  static bool _isCommonWord(String word) {
    const common = {
      'этот', 'тот', 'такой', 'какой', 'который', 'которая', 'которые',
      'один', 'два', 'три', 'первый', 'второй', 'третий',
      'только', 'даже', 'уже', 'ещё', 'всё', 'все', 'ничего',
      'здесь', 'там', 'тут', 'где', 'когда', 'потому', 'поэтому',
    };
    return common.contains(word.toLowerCase());
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
}

// ========== Типы данных ==========

enum TextType {
  narrative,    // Сказка, история
  business,     // Совещание, деловой разговор
  educational,  // Лекция, урок
  general,      // Общий случай
}

class SummaryResult {
  final String title;
  final TextType type;
  final List<String> points;
  final String fullText;
  
  SummaryResult({
    required this.title,
    required this.type,
    required this.points,
    required this.fullText,
  });
  
  factory SummaryResult.empty() => SummaryResult(
    title: 'Нет данных',
    type: TextType.general,
    points: ['Текст слишком короткий для саммари'],
    fullText: '',
  );
  
  String get formatted {
    final buffer = StringBuffer();
    buffer.writeln('=== $title ===');
    buffer.writeln();
    for (final point in points) {
      buffer.writeln(point);
    }
    return buffer.toString();
  }
}

// ========== Пример использования ==========

/// ```dart
/// final text = "Шёл солдат на побывку...";
/// final summary = EnhancedSummaryService.generateSummary(text);
/// 
/// print(summary.title); // "Солдат: шёл солдат на побывку..."
/// print(summary.formatted);
/// // === Солдат: шёл солдат на побывку... ===
/// // 
/// // Герои: Солдат, Старуха
/// // Начало: Шёл солдат на побывку
/// // Ключевые события:
/// //   • Солдат попросил поесть
/// //   • Сварили кашу из топора
/// // Конец: Вот и сказке конец
/// ```
