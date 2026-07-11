import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

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

    final rawOptions = json['options'] ?? json['answers'];
    final List<String> options;
    if (rawOptions is List) {
      options = rawOptions.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
    } else if (rawOptions is String) {
      options = rawOptions.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    } else {
      options = const [];
    }

    final correctAnswer = (json['correctAnswer'] ?? json['answer'] ?? '').toString();
    final analysis = (json['analysis'] ?? json['解析'] ?? '').toString();
    final question = (json['question'] ?? '').toString();

    return QuizBankItem(
      id: (json['id'] ?? UniqueQuizKeyGenerator.key(question)).toString(),
      question: question,
      type: type,
      options: options,
      correctAnswer: correctAnswer,
      analysis: analysis.isEmpty ? null : analysis,
      source: (json['source'] ?? '录入').toString(),
      createdAt: json['createdAt'] == null ? null : DateTime.tryParse(json['createdAt'].toString()),
    );
  }

  factory QuizBankItem.fromDb(Map<String, Object?> row) {
    return QuizBankItem(
      id: row['id']?.toString() ?? '',
      question: row['question']?.toString() ?? '',
      type: row['type']?.toString() == 'true_false'
          ? QuizQuestionType.trueFalse
          : QuizQuestionType.singleChoice,
      options: _decodeOptions(row['options']?.toString()),
      correctAnswer: row['correctAnswer']?.toString() ?? '',
      analysis: (row['analysis']?.toString() ?? '').trim().isEmpty ? null : row['analysis']?.toString(),
      source: row['source']?.toString() ?? '录入',
      createdAt: row['createdAt'] == null ? null : DateTime.tryParse(row['createdAt'].toString()),
    );
  }

  static List<String> _decodeOptions(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
      }
    } catch (_) {}
    return raw.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
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

  Map<String, Object?> toDb() => {
        'id': id,
        'question': question,
        'type': type == QuizQuestionType.trueFalse ? 'true_false' : 'single_choice',
        'options': jsonEncode(options),
        'correctAnswer': correctAnswer,
        'analysis': analysis,
        'source': source,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };
}

class UniqueQuizKeyGenerator {
  static String key(String question) {
    final normalized = question.replaceAll(RegExp(r'\s+'), '').trim();
    final digest = _fnv1a32(normalized).toRadixString(16).padLeft(8, '0');
    return 'quiz_${normalized.length.toString().padLeft(4, '0')}$digest';
  }

  static int _fnv1a32(String text) {
    var hash = 0x811c9dc5;
    for (final unit in utf8.encode(text)) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }
}

class QuizBankCache {
  QuizBankCache._();

  static final QuizBankCache instance = QuizBankCache._();
  List<QuizBankItem> _items = const [];
  Map<String, List<QuizBankItem>> _index = const {};
  bool _loaded = false;

  List<QuizBankItem> get items => _items;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    assign(await QuizBankStorage.loadAll());
  }

  Future<void> reload() async {
    assign(await QuizBankStorage.loadAll());
  }

  void assign(List<QuizBankItem> items) {
    _items = List.unmodifiable(items);
    _index = _buildIndex(_items);
    _loaded = true;
  }

  List<QuizBankItem> candidatesFor(String normalizedQuestion) {
    if (normalizedQuestion.length < 2) return _items;
    final tokens = _tokens(normalizedQuestion).take(8).toList();
    if (tokens.isEmpty) return _items;
    final merged = <String, QuizBankItem>{};
    for (final token in tokens) {
      for (final item in _index[token] ?? const <QuizBankItem>[]) {
        merged[item.id] = item;
      }
    }
    return merged.isEmpty ? _items : merged.values.toList(growable: false);
  }

  void reset() {
    _items = const [];
    _index = const {};
    _loaded = false;
  }

  static Map<String, List<QuizBankItem>> _buildIndex(List<QuizBankItem> items) {
    final index = <String, List<QuizBankItem>>{};
    for (final item in items) {
      final normalized = QuizBankTextNormalizer.cleanForMatch(item.question);
      for (final token in _tokens(normalized)) {
        (index[token] ??= <QuizBankItem>[]).add(item);
      }
    }
    return index;
  }

  static Iterable<String> _tokens(String text) sync* {
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    final words = RegExp(r'[\u4e00-\u9fa5]{2,}|[a-zA-Z0-9]{2,}').allMatches(compact);
    for (final match in words) {
      final word = match.group(0)!;
      if (word.length <= 6) {
        yield word;
      } else {
        for (var i = 0; i <= word.length - 4; i += 2) {
          yield word.substring(i, i + 4);
        }
      }
    }
  }
}

class QuizBankTextNormalizer {
  QuizBankTextNormalizer._();

  static String stripQuestionPrefix(String text) {
    var t = text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    t = t.replaceAll(RegExp(r'^(\[单选题\]|\[多选题\]|\[判断题\]|\[选择题\]|\[问答题\]|【单选题】|【多选题】|【判断题】|【选择题】|\[单选\]|\[判断\]|单选题|多选题|判断题|选择题)'), '');
    t = t.replaceAll(RegExp(r'(\([^)]*\)|（[^）]*）|【[^】]*】)'), '');
    t = t.replaceAll(RegExp(r'^第?\d+[题.、．、]'), '');
    return t.trim();
  }

  static bool isOptionLine(String line) {
    final compact = line.trim();
    return RegExp(r'^[A-Ha-h][.、．:]').hasMatch(compact) ||
        RegExp(r'^[①②③④⑤⑥⑦⑧]').hasMatch(compact) ||
        RegExp(r'^(正确|错误|对|错)$').hasMatch(compact);
  }

  static bool isNoiseLine(String line) {
    const labels = ['正确答案', '我的答案', '解析', '答案', '查看解析', '上一题', '下一题', '收藏', '交卷'];
    return labels.any(line.contains);
  }

  static String cleanForMatch(String text) {
    final usefulLines = text
        .split(RegExp(r'\n+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => !isOptionLine(line))
        .where((line) => !isNoiseLine(line))
        .map((line) => stripQuestionPrefix(line)
            .replaceAll(RegExp(r'^(问题|题目|试题|第\d+题|\d+/\d+|\d+题)[:：]?'), '')
            .trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final joined = usefulLines.isEmpty ? text : usefulLines.take(2).join('');
    return stripQuestionPrefix(joined);
  }
}

class QuizBankStorage {
  QuizBankStorage._();

  static const _legacyPrefsKey = 'quiz_bank_items';
  static const _migrationKey = 'quiz_bank_sqlite_migrated_v1';
  static const _table = 'quiz_bank_items';
  static Database? _db;

  static Future<Database> _database() async {
    final existing = _db;
    if (existing != null) return existing;
    final dbPath = p.join(await getDatabasesPath(), 'quiz_bank.db');
    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (database, _) async {
        await database.execute('''
CREATE TABLE $_table (
  id TEXT PRIMARY KEY,
  question TEXT NOT NULL,
  type TEXT NOT NULL,
  options TEXT NOT NULL,
  correctAnswer TEXT NOT NULL,
  analysis TEXT,
  source TEXT NOT NULL,
  createdAt TEXT,
  updatedAt TEXT
)
''');
        await database.execute('CREATE INDEX idx_quiz_bank_question ON $_table(question)');
      },
    );
    _db = db;
    await _migrateLegacyPrefsIfNeeded(db);
    return db;
  }

  static Future<void> _migrateLegacyPrefsIfNeeded(Database db) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_migrationKey) == true) return;
    final raw = prefs.getString(_legacyPrefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final batch = db.batch();
          for (final entry in decoded) {
            if (entry is Map) {
              final item = QuizBankItem.fromJson(Map<String, dynamic>.from(entry));
              if (item.question.trim().isNotEmpty) {
                batch.insert(_table, item.toDb(), conflictAlgorithm: ConflictAlgorithm.replace);
              }
            }
          }
          await batch.commit(noResult: true);
        }
      } catch (_) {}
    }
    await prefs.setBool(_migrationKey, true);
  }

  static Future<List<QuizBankItem>> loadAll() async {
    final db = await _database();
    final rows = await db.query(_table, orderBy: 'createdAt DESC, question ASC');
    return rows.map(QuizBankItem.fromDb).toList(growable: false);
  }

  static Future<void> saveAll(List<QuizBankItem> items) async {
    final db = await _database();
    final batch = db.batch();
    batch.delete(_table);
    for (final item in items) {
      batch.insert(_table, item.toDb(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    QuizBankCache.instance.assign(items);
  }

  static Future<List<QuizBankItem>> importItems(List<QuizBankItem> items) async {
    final db = await _database();
    final batch = db.batch();
    for (final item in items) {
      if (item.question.trim().isNotEmpty) {
        batch.insert(_table, item.toDb(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    await batch.commit(noResult: true);
    final result = await loadAll();
    QuizBankCache.instance.assign(result);
    return result;
  }

  static Future<void> clearAll() async {
    final db = await _database();
    await db.delete(_table);
    QuizBankCache.instance.reset();
  }
}
