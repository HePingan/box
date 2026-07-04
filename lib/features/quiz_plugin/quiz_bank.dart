import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum QuizQuestionType { singleChoice, trueFalse }

class QuizBankItem {
  const QuizBankItem({
    required this.id,
    required this.question,
    required this.type,
    required this.options,
    required this.correctAnswer,
    this.analysis,
    this.source = '录入',
    this.createdAt,
  });

  final String id;
  final String question;
  final QuizQuestionType type;
  final List<String> options;
  final String correctAnswer;
  final String? analysis;
  final String source;
  final DateTime? createdAt;

  QuizBankItem copyWith({
    String? id,
    String? question,
    QuizQuestionType? type,
    List<String>? options,
    String? correctAnswer,
    String? analysis,
    String? source,
    DateTime? createdAt,
  }) {
    return QuizBankItem(
      id: id ?? this.id,
      question: question ?? this.question,
      type: type ?? this.type,
      options: options ?? this.options,
      correctAnswer: correctAnswer ?? this.correctAnswer,
      analysis: analysis ?? this.analysis,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory QuizBankItem.fromJson(Map<String, dynamic> json) {
    final typeRaw = (json['type'] ?? '').toString().toLowerCase();
    final type = typeRaw == 'true_false' || typeRaw == '判断'
        ? QuizQuestionType.trueFalse
        : QuizQuestionType.singleChoice;

    final answers = json['answers'];
    final List<String> options;
    if (answers is List) {
      options = answers.map((e) => e.toString()).toList();
    } else if (answers is String) {
      options = answers.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    } else {
      options = const [];
    }

    final correctAnswer = (json['correctAnswer'] ?? json['answer'] ?? '').toString();
    final analysis = (json['analysis'] ?? json['解析'] ?? '').toString();

    return QuizBankItem(
      id: (json['id'] ?? json['question'] ?? UniqueQuizKeyGenerator.key(json['question'] ?? '')).toString(),
      question: (json['question'] ?? '').toString(),
      type: type,
      options: options,
      correctAnswer: correctAnswer,
      analysis: analysis.isEmpty ? null : analysis,
      source: (json['source'] ?? '录入').toString(),
      createdAt: json['createdAt'] == null ? null : DateTime.tryParse(json['createdAt'].toString()),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'question': question,
        'type': type == QuizQuestionType.trueFalse ? 'true_false' : 'single_choice',
        'options': options,
        'correctAnswer': correctAnswer,
        if (analysis != null && analysis!.isNotEmpty) 'analysis': analysis,
        'source': source,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      };
}

class UniqueQuizKeyGenerator {
  static String key(String question) {
    final normalized = question.replaceAll(RegExp(r'\s+'), '').trim();
    final digest = normalized.length.toString().padLeft(4, '0');
    return 'quiz_$digest${normalized.hashCode}';
  }
}

class QuizBankCache {
  QuizBankCache._();

  static final QuizBankCache instance = QuizBankCache._();
  List<QuizBankItem> _items = const [];
  bool _loaded = false;

  List<QuizBankItem> get items => _items;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _items = await QuizBankStorage.loadAll();
    _loaded = true;
  }

  Future<void> reload() async {
    _items = await QuizBankStorage.loadAll();
    _loaded = true;
  }

  void assign(List<QuizBankItem> items) {
    _items = List.unmodifiable(items);
    _loaded = true;
  }

  void reset() {
    _items = const [];
    _loaded = false;
  }
}

class QuizBankStorage {
  QuizBankStorage._();

  static const _key = 'quiz_bank_items';

  static Future<List<QuizBankItem>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => QuizBankItem.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<void> saveAll(List<QuizBankItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  static Future<List<QuizBankItem>> importItems(List<QuizBankItem> items) async {
    final existing = await loadAll();
    final merged = <String, QuizBankItem>{};
    for (final item in [...existing, ...items]) {
      merged[item.id] = item;
    }
    final result = merged.values.toList();
    await saveAll(result);
    return result;
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
