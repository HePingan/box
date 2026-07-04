/// 词典释义数据模型
library;

/// 查词结果
class DictionaryDefinition {
  final String word;
  final String phonetic;
  final List<DictionarySense> senses;
  final String source;

  const DictionaryDefinition({
    required this.word,
    this.phonetic = '',
    this.senses = const [],
    this.source = '',
  });

  bool get isEmpty => senses.isEmpty && phonetic.isEmpty;

  Map<String, dynamic> toJson() => {
        'word': word,
        'phonetic': phonetic,
        'senses': senses.map((s) => s.toJson()).toList(),
        'source': source,
      };

  factory DictionaryDefinition.fromJson(Map<String, dynamic> json) =>
      DictionaryDefinition(
        word: json['word'] as String? ?? '',
        phonetic: json['phonetic'] as String? ?? '',
        senses: (json['senses'] as List?)
                ?.map((e) =>
                    DictionarySense.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        source: json['source'] as String? ?? '',
      );
}

/// 单个释义
class DictionarySense {
  final String partOfSpeech;
  final String definition;
  final String? example;

  const DictionarySense({
    this.partOfSpeech = '',
    required this.definition,
    this.example,
  });

  Map<String, dynamic> toJson() => {
        'partOfSpeech': partOfSpeech,
        'definition': definition,
        'example': example,
      };

  factory DictionarySense.fromJson(Map<String, dynamic> json) =>
      DictionarySense(
        partOfSpeech: json['partOfSpeech'] as String? ?? '',
        definition: json['definition'] as String? ?? '',
        example: json['example'] as String?,
      );
}
