/// 可配置的 API 词典源
///
/// 用户可自定义：
/// - API URL（支持 `{{word}}` 占位符）
/// - 请求头（如 API Key）
/// - JSON 响应路径提取规则
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/dictionary_definition.dart';
import '../models/dictionary_source.dart';

/// API 词典源配置
class ApiDictionarySourceConfig {
  final String apiUrl;
  final Map<String, String> headers;
  final String wordField;
  final String phoneticField;
  final String definitionField;
  final String partOfSpeechField;
  final String exampleField;
  final String sourceName;

  const ApiDictionarySourceConfig({
    required this.apiUrl,
    this.headers = const {},
    this.wordField = 'word',
    this.phoneticField = 'phonetic',
    this.definitionField = 'definition',
    this.partOfSpeechField = 'part_of_speech',
    this.exampleField = 'example',
    this.sourceName = '自定义词典',
  });

  Map<String, dynamic> toJson() => {
        'apiUrl': apiUrl,
        'headers': headers,
        'wordField': wordField,
        'phoneticField': phoneticField,
        'definitionField': definitionField,
        'partOfSpeechField': partOfSpeechField,
        'exampleField': exampleField,
        'sourceName': sourceName,
      };

  factory ApiDictionarySourceConfig.fromJson(Map<String, dynamic> json) =>
      ApiDictionarySourceConfig(
        apiUrl: json['apiUrl'] as String? ?? '',
        headers: Map<String, String>.from(json['headers'] as Map? ?? {}),
        wordField: json['wordField'] as String? ?? 'word',
        phoneticField: json['phoneticField'] as String? ?? 'phonetic',
        definitionField: json['definitionField'] as String? ?? 'definition',
        partOfSpeechField: json['partOfSpeechField'] as String? ?? 'part_of_speech',
        exampleField: json['exampleField'] as String? ?? 'example',
        sourceName: json['sourceName'] as String? ?? '自定义词典',
      );
}

/// 可配置的 API 词典源
class ApiDictionarySource extends DictionarySource {
  final ApiDictionarySourceConfig config;

  ApiDictionarySource({required this.config});

  @override
  String get name => config.sourceName;

  @override
  String get id => 'api_${config.apiUrl.hashCode}';

  @override
  bool get isConfigurable => true;

  @override
  Future<DictionaryDefinition> lookup(String word) async {
    final trimmed = word.trim();
    if (trimmed.isEmpty) {
      return DictionaryDefinition(word: '', source: name);
    }

    final url = config.apiUrl.replaceAll('{{word}}', Uri.encodeComponent(trimmed));
    final uri = Uri.parse(url);

    try {
      final resp = await http
          .get(uri, headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            ...config.headers,
          })
          .timeout(const Duration(seconds: 8));

      if (resp.statusCode != 200) {
        return DictionaryDefinition(word: trimmed, source: name);
      }

      final body = jsonDecode(resp.body);
      return _extractDefinition(trimmed, body);
    } catch (_) {
      return DictionaryDefinition(word: trimmed, source: name);
    }
  }

  DictionaryDefinition _extractDefinition(String word, dynamic data) {
    if (data is! Map<String, dynamic>) {
      // 尝试取列表第一项
      if (data is List && data.isNotEmpty && data[0] is Map<String, dynamic>) {
        return _parseEntry(word, data[0] as Map<String, dynamic>);
      }
      return DictionaryDefinition(word: word, source: name);
    }

    // 直接是条目
    return _parseEntry(word, data);
  }

  DictionaryDefinition _parseEntry(String word, Map<String, dynamic> entry) {
    final rawWord = _getString(entry, config.wordField);
    final phonetic = _getString(entry, config.phoneticField);
    final rawDef = _getString(entry, config.definitionField);

    final senses = <DictionarySense>[];
    if (rawDef.isNotEmpty) {
      final pos = _getString(entry, config.partOfSpeechField);
      final example = _getString(entry, config.exampleField);
      senses.add(DictionarySense(
        partOfSpeech: pos,
        definition: rawDef,
        example: example.isNotEmpty ? example : null,
      ));
    }

    // 尝试从 definitions/senses 数组读取
    final definitions = entry['definitions'] as List?;
    if (definitions != null) {
      for (final d in definitions) {
        if (d is Map<String, dynamic>) {
          senses.add(DictionarySense(
            partOfSpeech: _getString(d, config.partOfSpeechField),
            definition: _getString(d, config.definitionField),
            example: _getString(d, config.exampleField).nullIfEmpty,
          ));
        }
      }
    }

    return DictionaryDefinition(
      word: rawWord.isNotEmpty ? rawWord : word,
      phonetic: phonetic,
      senses: senses,
      source: name,
    );
  }

  String _getString(Map<String, dynamic> map, String field) {
    if (field.isEmpty) return '';
    // 支持点号嵌套路径：data.word
    final parts = field.split('.');
    dynamic current = map;
    for (final part in parts) {
      if (current is! Map<String, dynamic>) return '';
      current = current[part];
    }
    return current?.toString() ?? '';
  }
}

extension _StringExt on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
