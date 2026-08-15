import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

enum QuizQuestionType { singleChoice, trueFalse }

/// 本地题 → 云端投稿状态（不影响搜题 canonical id）。
class QuizSyncStatus {
  static const localOnly = 'local_only';
  static const pendingReview = 'pending_review';
  static const published = 'published';
  static const rejected = 'rejected';
  static const merged = 'merged';

  static String normalize(
    String? raw, {
    required String origin,
    String source = '',
  }) {
    final value = (raw ?? '').trim();
    final isCloud = origin == 'cloud' || source.contains('云端');
    if (value.isEmpty) return isCloud ? published : localOnly;
    // 云端镜像不应停留在 local_only（构造默认值 / 旧数据）。
    if (isCloud && value == localOnly) return published;
    return value;
  }

  static String label(String status) {
    switch (status) {
      case pendingReview:
        return '审核中';
      case published:
        return '已上云';
      case rejected:
        return '已拒绝';
      case merged:
        return '云端已有';
      case localOnly:
      default:
        return '未推送';
    }
  }
}

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
    this.imageUrl,
    this.category = '',
    this.origin = 'local',
    this.syncStatus = QuizSyncStatus.localOnly,
    this.lastSubmitAt,
    this.lastSubmitError,
    this.remoteSubmissionId,
  });

  final String id;
  final String question;
  final QuizQuestionType type;
  final List<String> options;
  final String correctAnswer;
  final String? analysis;
  final String source;
  final DateTime? createdAt;
  final String? imageUrl;

  /// 题库分类（云端 catalog / 本地标签）。
  final String category;

  /// 来源归属：`local` 本地录入/OCR，`cloud` 云端正式库。
  final String origin;

  /// 云端投稿状态：local_only / pending_review / published / rejected / merged。
  final String syncStatus;
  final DateTime? lastSubmitAt;
  final String? lastSubmitError;
  final String? remoteSubmissionId;

  bool get isCloud => origin == 'cloud' || source.contains('云端');

  /// 本地题可投稿（云端镜像、审核中和已合并的题不重复投稿）。
  bool get canPushToCloud =>
      !isCloud &&
      (syncStatus == QuizSyncStatus.localOnly ||
          syncStatus == QuizSyncStatus.rejected);

  bool get isUnpushedLocal =>
      !isCloud &&
      (syncStatus == QuizSyncStatus.localOnly ||
          syncStatus == QuizSyncStatus.rejected ||
          syncStatus.trim().isEmpty);

  QuizBankItem copyWith({
    String? id,
    String? question,
    QuizQuestionType? type,
    List<String>? options,
    String? correctAnswer,
    String? analysis,
    String? source,
    DateTime? createdAt,
    String? imageUrl,
    String? category,
    String? origin,
    String? syncStatus,
    DateTime? lastSubmitAt,
    String? lastSubmitError,
    String? remoteSubmissionId,
    bool clearLastSubmitError = false,
    bool clearRemoteSubmissionId = false,
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
      imageUrl: imageUrl ?? this.imageUrl,
      category: category ?? this.category,
      origin: origin ?? this.origin,
      syncStatus: syncStatus ?? this.syncStatus,
      lastSubmitAt: lastSubmitAt ?? this.lastSubmitAt,
      lastSubmitError: clearLastSubmitError
          ? null
          : (lastSubmitError ?? this.lastSubmitError),
      remoteSubmissionId: clearRemoteSubmissionId
          ? null
          : (remoteSubmissionId ?? this.remoteSubmissionId),
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
      options = rawOptions
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
    } else if (rawOptions is String) {
      options = rawOptions
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else {
      options = const [];
    }

    final correctAnswer = (json['correctAnswer'] ?? json['answer'] ?? '')
        .toString();
    final analysis = (json['analysis'] ?? json['解析'] ?? '').toString();
    final question = (json['question'] ?? '').toString();
    final imageUrl = (json['image'] ?? json['imageUrl'] ?? '')
        .toString()
        .trim();
    final source = (json['source'] ?? '录入').toString();
    final category = (json['category'] ?? '').toString().trim();
    final originRaw = (json['origin'] ?? '').toString().trim();
    final origin = originRaw.isNotEmpty
        ? originRaw
        : (source.contains('云端') ? 'cloud' : 'local');
    final lastSubmitError =
        (json['lastSubmitError'] ?? json['submitError'] ?? '')
            .toString()
            .trim();
    final remoteSubmissionId =
        (json['remoteSubmissionId'] ?? json['submissionId'] ?? '')
            .toString()
            .trim();

    return QuizBankItem(
      id: (json['id'] ?? UniqueQuizKeyGenerator.key(question, options: options))
          .toString(),
      question: question,
      type: type,
      options: options,
      correctAnswer: correctAnswer,
      analysis: analysis.isEmpty ? null : analysis,
      source: source,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'].toString()),
      imageUrl: imageUrl.isEmpty ? null : imageUrl,
      category: category,
      origin: origin,
      syncStatus: QuizSyncStatus.normalize(
        (json['syncStatus'] ?? '').toString(),
        origin: origin,
        source: source,
      ),
      lastSubmitAt: json['lastSubmitAt'] == null
          ? null
          : DateTime.tryParse(json['lastSubmitAt'].toString()),
      lastSubmitError: lastSubmitError.isEmpty ? null : lastSubmitError,
      remoteSubmissionId: remoteSubmissionId.isEmpty
          ? null
          : remoteSubmissionId,
    );
  }

  factory QuizBankItem.fromDb(Map<String, Object?> row) {
    final rawImage = (row['image'] ?? row['imageUrl'] ?? '').toString().trim();
    final source = row['source']?.toString() ?? '录入';
    final category = (row['category']?.toString() ?? '').trim();
    final originRaw = (row['origin']?.toString() ?? '').trim();
    final origin = originRaw.isNotEmpty
        ? originRaw
        : (source.contains('云端') ? 'cloud' : 'local');
    final lastSubmitError = (row['lastSubmitError']?.toString() ?? '').trim();
    final remoteSubmissionId = (row['remoteSubmissionId']?.toString() ?? '')
        .trim();
    return QuizBankItem(
      id: row['id']?.toString() ?? '',
      question: row['question']?.toString() ?? '',
      type: row['type']?.toString() == 'true_false'
          ? QuizQuestionType.trueFalse
          : QuizQuestionType.singleChoice,
      options: _decodeOptions(row['options']?.toString()),
      correctAnswer: row['correctAnswer']?.toString() ?? '',
      analysis: (row['analysis']?.toString() ?? '').trim().isEmpty
          ? null
          : row['analysis']?.toString(),
      source: source,
      createdAt: row['createdAt'] == null
          ? null
          : DateTime.tryParse(row['createdAt'].toString()),
      imageUrl: rawImage.isEmpty ? null : rawImage,
      category: category,
      origin: origin,
      syncStatus: QuizSyncStatus.normalize(
        row['syncStatus']?.toString(),
        origin: origin,
        source: source,
      ),
      lastSubmitAt: row['lastSubmitAt'] == null
          ? null
          : DateTime.tryParse(row['lastSubmitAt'].toString()),
      lastSubmitError: lastSubmitError.isEmpty ? null : lastSubmitError,
      remoteSubmissionId: remoteSubmissionId.isEmpty
          ? null
          : remoteSubmissionId,
    );
  }

  static List<String> _decodeOptions(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return raw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
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
    if (imageUrl != null && imageUrl!.isNotEmpty) 'image': imageUrl,
    if (category.isNotEmpty) 'category': category,
    'origin': origin,
    'syncStatus': QuizSyncStatus.normalize(
      syncStatus,
      origin: origin,
      source: source,
    ),
    if (lastSubmitAt != null) 'lastSubmitAt': lastSubmitAt!.toIso8601String(),
    if (lastSubmitError != null && lastSubmitError!.isNotEmpty)
      'lastSubmitError': lastSubmitError,
    if (remoteSubmissionId != null && remoteSubmissionId!.isNotEmpty)
      'remoteSubmissionId': remoteSubmissionId,
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
    'image': imageUrl,
    'category': category,
    'origin': origin,
    'syncStatus': QuizSyncStatus.normalize(
      syncStatus,
      origin: origin,
      source: source,
    ),
    'lastSubmitAt': lastSubmitAt?.toIso8601String(),
    'lastSubmitError': lastSubmitError,
    'remoteSubmissionId': remoteSubmissionId,
  };
}

class UniqueQuizKeyGenerator {
  /// 题目标识：题干 + 规范化选项。同题干不同选项视为不同题。
  static String key(String question, {List<String> options = const []}) {
    final q = _compact(question);
    final opts = options.map(_compact).where((e) => e.isNotEmpty).toList()
      ..sort(); // 顺序无关：A/B 互换仍算同一题（内容相同）
    final payload = opts.isEmpty ? q : '$q|${opts.join('|')}';
    final digest = _fnv1a32(payload).toRadixString(16).padLeft(8, '0');
    return 'quiz_${payload.length.toString().padLeft(4, '0')}$digest';
  }

  static String keyFromItem(QuizBankItem item) =>
      key(item.question, options: item.options);

  static String _compact(String text) {
    return text
        .replaceAll(RegExp(r'\s+'), '')
        .replaceFirst(RegExp(r'^[A-DＡ-Ｄ]\s*[.、．:：)）]\s*'), '')
        .trim()
        .toLowerCase();
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

class QuizBankImportNormalization {
  const QuizBankImportNormalization({
    required this.items,
    required this.skipped,
  });

  final List<QuizBankItem> items;
  final int skipped;
}

enum QuizBankWriteStatus {
  inserted,
  duplicateSkipped,
  variantInserted,
  incompleteVariantNeedsRetry,
}

class QuizBankWriteDecision {
  const QuizBankWriteDecision({required this.status, required this.items});

  final QuizBankWriteStatus status;
  final List<QuizBankItem> items;
}

/// One identity rule for every entry point: a duplicate must never overwrite
/// an already-stored question. Explicit editing uses [replaceItem] instead.
class QuizBankWritePolicy {
  QuizBankWritePolicy._();

  static QuizBankWriteDecision insertIfAbsent({
    required List<QuizBankItem> existing,
    required QuizBankItem incoming,
    bool batchMode = false,
  }) {
    final canonical = incoming.copyWith(
      id: UniqueQuizKeyGenerator.keyFromItem(incoming),
    );
    final existingCanonicalIds = existing
        .map(UniqueQuizKeyGenerator.keyFromItem)
        .toSet();
    if (existingCanonicalIds.contains(canonical.id)) {
      return QuizBankWriteDecision(
        status: QuizBankWriteStatus.duplicateSkipped,
        items: List.unmodifiable(existing),
      );
    }
    final sameStem = existing.where(
      (item) =>
          QuizBankTextNormalizer.cleanForMatch(item.question) ==
          QuizBankTextNormalizer.cleanForMatch(canonical.question),
    );
    final looksTruncatedVariant =
        batchMode &&
        sameStem.any(
          (item) =>
              _isStrictOptionSubset(canonical.options, item.options) ||
              _isStrictOptionSubset(item.options, canonical.options),
        );
    if (looksTruncatedVariant) {
      return QuizBankWriteDecision(
        status: QuizBankWriteStatus.incompleteVariantNeedsRetry,
        items: List.unmodifiable(existing),
      );
    }
    return QuizBankWriteDecision(
      status: sameStem.isEmpty
          ? QuizBankWriteStatus.inserted
          : QuizBankWriteStatus.variantInserted,
      items: List.unmodifiable([...existing, canonical]),
    );
  }

  /// A strict subset indicates that the OCR/试捕 pass likely missed options.
  /// Use only for batch capture: manual entry remains intentionally permissive.
  static bool _isStrictOptionSubset(List<String> left, List<String> right) {
    final a = left
        .map(QuizBankTextNormalizer.normalizeOption)
        .where((option) => option.isNotEmpty)
        .toSet();
    final b = right
        .map(QuizBankTextNormalizer.normalizeOption)
        .where((option) => option.isNotEmpty)
        .toSet();
    return a.length < b.length && a.isNotEmpty && b.containsAll(a);
  }
}

class QuizBankDeduplicateResult {
  const QuizBankDeduplicateResult({
    required this.items,
    required this.removed,
    required this.duplicateGroups,
  });

  final List<QuizBankItem> items;
  final int removed;
  final int duplicateGroups;
}

/// Repairs legacy/corrupted records that share a canonical identity.
/// Prefer a complete answer, then analysis, option count, and earlier entry.
class QuizBankDeduplicator {
  QuizBankDeduplicator._();

  static QuizBankDeduplicateResult deduplicate(List<QuizBankItem> source) {
    final winners = <String, QuizBankItem>{};
    final countedGroups = <String>{};
    var removed = 0;
    for (final raw in source) {
      if (raw.question.trim().isEmpty) {
        removed++;
        continue;
      }
      final canonical = raw.copyWith(
        id: UniqueQuizKeyGenerator.keyFromItem(raw),
      );
      final previous = winners[canonical.id];
      if (previous == null) {
        winners[canonical.id] = canonical;
        continue;
      }
      if (countedGroups.add(canonical.id)) {
        // A group counts once even if it contains more than two legacy rows.
      }
      removed++;
      if (_isBetter(canonical, previous)) winners[canonical.id] = canonical;
    }
    return QuizBankDeduplicateResult(
      items: List.unmodifiable(winners.values),
      removed: removed,
      duplicateGroups: countedGroups.length,
    );
  }

  static bool _isBetter(QuizBankItem candidate, QuizBankItem current) {
    int score(QuizBankItem item) =>
        (item.correctAnswer.trim().isNotEmpty ? 100 : 0) +
        ((item.analysis?.trim().isNotEmpty ?? false) ? 10 : 0) +
        item.options.where((option) => option.trim().isNotEmpty).length;
    final candidateScore = score(candidate);
    final currentScore = score(current);
    if (candidateScore != currentScore) return candidateScore > currentScore;
    final candidateAt = candidate.createdAt;
    final currentAt = current.createdAt;
    if (candidateAt == null) return false;
    if (currentAt == null) return true;
    return candidateAt.isBefore(currentAt);
  }
}

/// Converts every imported record to the v2 identity (question + options).
/// The last occurrence wins when a file contains duplicate canonical questions.
class QuizBankImportNormalizer {
  QuizBankImportNormalizer._();

  static QuizBankImportNormalization canonicalize(List<QuizBankItem> source) {
    final byId = <String, QuizBankItem>{};
    var skipped = 0;
    for (final item in source) {
      if (item.question.trim().isEmpty) {
        skipped++;
        continue;
      }
      final id = UniqueQuizKeyGenerator.keyFromItem(item);
      if (byId.containsKey(id)) skipped++;
      byId[id] = item.id == id ? item : item.copyWith(id: id);
    }
    return QuizBankImportNormalization(
      items: List.unmodifiable(byId.values),
      skipped: skipped,
    );
  }
}

class QuizBankCache {
  QuizBankCache._();

  factory QuizBankCache.forTesting(List<QuizBankItem> items) {
    final cache = QuizBankCache._();
    cache.assign(items);
    return cache;
  }

  static final QuizBankCache instance = QuizBankCache._();
  List<QuizBankItem> _items = const [];
  Map<String, List<QuizBankItem>> _index = const {};
  Map<String, List<QuizBankItem>> _exactIndex = const {};
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
    _exactIndex = _buildExactIndex(_items);
    _loaded = true;
  }

  List<QuizBankItem> candidatesFor(String normalizedQuestion) {
    if (normalizedQuestion.length < 2) return const [];
    // 完整题干优先走精确索引：不会受 token 分词策略、候选上限影响。
    final exact = _exactIndex[normalizedQuestion];
    if (exact != null && exact.isNotEmpty) return exact;
    final tokens = _tokens(normalizedQuestion).take(8).toList();
    if (tokens.isEmpty) return const [];
    final merged = <String, QuizBankItem>{};
    for (final token in tokens) {
      for (final item in _index[token] ?? const <QuizBankItem>[]) {
        merged[item.id] = item;
      }
    }
    // 索引未命中时不能按录入顺序截断，否则后排题永远没有机会匹配。
    // 先做 O(n) 的字符重叠预筛选（不跑 LCS），再仅返回 Top 80 给搜索引擎精算。
    if (merged.isEmpty) {
      final queryChars = normalizedQuestion.split('').toSet();
      final ranked =
          _items
              .map((item) {
                final target = QuizBankTextNormalizer.cleanForMatch(
                  item.question,
                );
                final targetChars = target.split('').toSet();
                final overlap = queryChars.intersection(targetChars).length;
                final denominator = queryChars.length + targetChars.length;
                final score = denominator == 0
                    ? 0
                    : overlap * 200 ~/ denominator;
                return (item: item, score: score);
              })
              .where((entry) => entry.score > 0)
              .toList()
            ..sort((a, b) => b.score.compareTo(a.score));
      return ranked.take(80).map((entry) => entry.item).toList(growable: false);
    }
    return merged.values.take(160).toList(growable: false);
  }

  void reset() {
    _items = const [];
    _index = const {};
    _exactIndex = const {};
    _loaded = false;
  }

  static Map<String, List<QuizBankItem>> _buildExactIndex(
    List<QuizBankItem> items,
  ) {
    final index = <String, List<QuizBankItem>>{};
    for (final item in items) {
      final normalized = QuizBankTextNormalizer.cleanForMatch(item.question);
      if (normalized.isNotEmpty) {
        (index[normalized] ??= <QuizBankItem>[]).add(item);
      }
    }
    return index;
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
    final words = RegExp(
      r'[\u4e00-\u9fa5]{2,}|[a-zA-Z0-9]{2,}',
    ).allMatches(compact);
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
    t = t.replaceAll(
      RegExp(
        r'^(\[单选题\]|\[多选题\]|\[判断题\]|\[选择题\]|\[问答题\]|【单选题】|【多选题】|【判断题】|【选择题】|\[单选\]|\[判断\]|单选题|多选题|判断题|选择题)',
      ),
      '',
    );
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
    const labels = [
      '正确答案',
      '我的答案',
      '解析',
      '答案',
      '查看解析',
      '上一题',
      '下一题',
      '收藏',
      '交卷',
    ];
    return labels.any(line.contains);
  }

  /// 选项规范化：去空白、去 A./B. 前缀，小写，便于选项集合比对。
  static String normalizeOption(String text) {
    var t = text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    t = t.replaceFirst(RegExp(r'^[a-dａ-ｄ][.、．:：)）]'), '');
    return t.trim();
  }

  static String cleanForMatch(String text) {
    final usefulLines = text
        .split(RegExp(r'\n+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => !isOptionLine(line))
        .where((line) => !isNoiseLine(line))
        .map(
          (line) => stripQuestionPrefix(line)
              .replaceAll(RegExp(r'^(问题|题目|试题|第\d+题|\d+/\d+|\d+题)[:：]?'), '')
              .trim(),
        )
        .where((line) => line.isNotEmpty)
        .toList();
    final joined = usefulLines.isEmpty ? text : usefulLines.take(2).join('');
    return stripQuestionPrefix(joined);
  }
}

/// 题库答案 → 选项原文的投影。
///
/// 云端 `/api/quiz/sync` 绝大多数题的 `correctAnswer` 已是选项原文，
/// 但真实库中残留少量字母形答案（`'C'`），且字母下标可能越界于选项数
/// （实测 1934 题中有 3 道：答案 'C'/'D' 却只有 2~3 个选项）。
///
/// 查看页与答题助手都按「选项原文」比较答案，遇到字母形会静默失配、
/// 整题显示不出对号。此处统一做一次投影：
/// - 答案能按原文命中选项 → 用选项原文（不动）
/// - 答案是字母且下标在范围内 → 投影为对应选项原文
/// - 字母越界 / 答案为空 → 标记 needsRepair，不编造答案
class QuizAnswerProjection {
  QuizAnswerProjection._();

  static final RegExp _letterForm = RegExp(
    r'^[\s]*(?:答案|正确答案)?[\s:：]*([A-Ha-hＡ-Ｈａ-ｈ])[\s.、．:：)）]*$',
  );

  /// 解析某题的实际答案。
  static QuizAnswerResolution resolve(QuizBankItem item) {
    final raw = item.correctAnswer.trim();
    final options = item.options;

    if (raw.isEmpty) {
      return const QuizAnswerResolution(
        answer: '',
        projected: false,
        outOfRange: false,
        needsRepair: true,
        matchedIndex: null,
      );
    }

    // 1) 先按选项原文精确命中（含空白/大小写归一），优先于字母解释。
    //    这样选项本身就是 'A'/'B' 字面值时不会被当成下标。
    final exact = _indexOfOption(options, raw);
    if (exact != null) {
      return QuizAnswerResolution(
        answer: options[exact],
        projected: false,
        outOfRange: false,
        needsRepair: false,
        matchedIndex: exact,
      );
    }

    // 2) 字母形答案 → 按下标投影到选项原文。
    final letter = _extractLetter(raw);
    if (letter != null) {
      final index = _letterIndex(letter);
      if (index >= 0 && index < options.length) {
        return QuizAnswerResolution(
          answer: options[index],
          projected: true,
          outOfRange: false,
          needsRepair: false,
          matchedIndex: index,
        );
      }
      // 字母越界：保留原值，交由 UI 提示「答案待补」，绝不猜一个选项。
      return QuizAnswerResolution(
        answer: raw,
        projected: false,
        outOfRange: true,
        needsRepair: true,
        matchedIndex: null,
      );
    }

    // 3) 既非字母也对不上任何选项：视为待补，保留原文。
    return QuizAnswerResolution(
      answer: raw,
      projected: false,
      outOfRange: false,
      needsRepair: options.isNotEmpty,
      matchedIndex: null,
    );
  }

  /// 供列表 UI 判断第 [index] 个选项是否应打对号。
  static bool isCorrectOption(QuizBankItem item, int index) {
    if (index < 0 || index >= item.options.length) return false;
    final resolved = resolve(item);
    if (resolved.needsRepair) return false;
    final matched = resolved.matchedIndex;
    if (matched != null) return matched == index;
    return QuizBankTextNormalizer.normalizeOption(item.options[index]) ==
        QuizBankTextNormalizer.normalizeOption(resolved.answer);
  }

  /// 该题答案是否需要人工补全（空答案 / 字母越界 / 对不上任何选项）。
  static bool needsRepair(QuizBankItem item) => resolve(item).needsRepair;

  static int? _indexOfOption(List<String> options, String answer) {
    final target = QuizBankTextNormalizer.normalizeOption(answer);
    if (target.isEmpty) return null;
    for (var i = 0; i < options.length; i++) {
      if (QuizBankTextNormalizer.normalizeOption(options[i]) == target) {
        return i;
      }
    }
    return null;
  }

  static String? _extractLetter(String raw) {
    final match = _letterForm.firstMatch(raw);
    if (match == null) return null;
    return match.group(1);
  }

  static int _letterIndex(String letter) {
    final ch = letter.toUpperCase();
    final code = ch.codeUnitAt(0);
    // 半角 A-H
    if (code >= 0x41 && code <= 0x48) return code - 0x41;
    // 全角 Ａ-Ｈ
    if (code >= 0xFF21 && code <= 0xFF28) return code - 0xFF21;
    return -1;
  }
}

class QuizAnswerResolution {
  const QuizAnswerResolution({
    required this.answer,
    required this.projected,
    required this.outOfRange,
    required this.needsRepair,
    required this.matchedIndex,
  });

  /// 投影后的答案（选项原文）；待补时为原始值。
  final String answer;

  /// 是否由字母形投影得到。
  final bool projected;

  /// 字母下标是否越界于选项数。
  final bool outOfRange;

  /// 是否需要人工补答案。
  final bool needsRepair;

  /// 命中的选项下标；未命中为 null。
  final int? matchedIndex;
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
      version: 4,
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
  updatedAt TEXT,
  image TEXT,
  category TEXT,
  origin TEXT,
  syncStatus TEXT,
  lastSubmitAt TEXT,
  lastSubmitError TEXT,
  remoteSubmissionId TEXT
)
''');
        await database.execute(
          'CREATE INDEX idx_quiz_bank_question ON $_table(question)',
        );
        await database.execute(
          'CREATE INDEX idx_quiz_bank_category ON $_table(category)',
        );
        await database.execute(
          'CREATE INDEX idx_quiz_bank_origin ON $_table(origin)',
        );
        await database.execute(
          'CREATE INDEX idx_quiz_bank_sync_status ON $_table(syncStatus)',
        );
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database.execute('ALTER TABLE $_table ADD COLUMN image TEXT');
        }
        if (oldVersion < 3) {
          await database.execute(
            'ALTER TABLE $_table ADD COLUMN category TEXT',
          );
          await database.execute('ALTER TABLE $_table ADD COLUMN origin TEXT');
          await database.execute(
            "UPDATE $_table SET origin = CASE WHEN source LIKE '%云端%' THEN 'cloud' ELSE 'local' END WHERE origin IS NULL OR origin = ''",
          );
          await database.execute(
            'CREATE INDEX IF NOT EXISTS idx_quiz_bank_category ON $_table(category)',
          );
          await database.execute(
            'CREATE INDEX IF NOT EXISTS idx_quiz_bank_origin ON $_table(origin)',
          );
        }
        if (oldVersion < 4) {
          await database.execute(
            'ALTER TABLE $_table ADD COLUMN syncStatus TEXT',
          );
          await database.execute(
            'ALTER TABLE $_table ADD COLUMN lastSubmitAt TEXT',
          );
          await database.execute(
            'ALTER TABLE $_table ADD COLUMN lastSubmitError TEXT',
          );
          await database.execute(
            'ALTER TABLE $_table ADD COLUMN remoteSubmissionId TEXT',
          );
          await database.execute(
            'UPDATE $_table SET syncStatus = CASE '
            "WHEN origin = 'cloud' OR source LIKE '%云端%' THEN 'published' "
            "ELSE 'local_only' END "
            "WHERE syncStatus IS NULL OR syncStatus = ''",
          );
          await database.execute(
            'CREATE INDEX IF NOT EXISTS idx_quiz_bank_sync_status ON $_table(syncStatus)',
          );
        }
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
              final parsed = QuizBankItem.fromJson(
                Map<String, dynamic>.from(entry),
              );
              final item = parsed.copyWith(
                id: UniqueQuizKeyGenerator.keyFromItem(parsed),
              );
              if (item.question.trim().isNotEmpty) {
                batch.insert(
                  _table,
                  item.toDb(),
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );
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
    final rows = await db.query(
      _table,
      orderBy: 'createdAt DESC, question ASC',
    );
    return rows.map(QuizBankItem.fromDb).toList(growable: false);
  }

  static Future<void> saveAll(List<QuizBankItem> items) async {
    final db = await _database();
    final normalized = QuizBankImportNormalizer.canonicalize(items).items;
    // 清表和重建必须同一事务，失败时保留旧题库。
    await db.transaction((txn) async {
      await txn.delete(_table);
      for (final item in normalized) {
        await txn.insert(_table, item.toDb());
      }
    });
    QuizBankCache.instance.assign(await loadAll());
  }

  /// Writes a new question only when its canonical identity is absent.
  /// Unlike import/legacy behavior, this never replaces an existing question.
  static Future<QuizBankWriteStatus> insertIfAbsent(
    QuizBankItem item, {
    bool batchMode = false,
  }) async {
    final existingItems = await loadAll();
    final decision = QuizBankWritePolicy.insertIfAbsent(
      existing: existingItems,
      incoming: item,
      batchMode: batchMode,
    );
    if (decision.status == QuizBankWriteStatus.duplicateSkipped ||
        decision.status == QuizBankWriteStatus.incompleteVariantNeedsRetry) {
      return decision.status;
    }
    final db = await _database();
    final canonical = item.copyWith(
      id: UniqueQuizKeyGenerator.keyFromItem(item),
    );
    var inserted = false;
    await db.transaction((txn) async {
      final existing = await txn.query(
        _table,
        columns: const ['id'],
        where: 'id = ?',
        whereArgs: [canonical.id],
        limit: 1,
      );
      if (existing.isNotEmpty) return;
      await txn.insert(_table, canonical.toDb());
      inserted = true;
    });
    if (!inserted) return QuizBankWriteStatus.duplicateSkipped;
    QuizBankCache.instance.assign(await loadAll());
    return decision.status;
  }

  /// Merges import records without replacing questions already in the bank.
  static Future<List<QuizBankItem>> importItems(
    List<QuizBankItem> items,
  ) async {
    final db = await _database();
    final normalized = QuizBankImportNormalizer.canonicalize(items).items;
    final existingIds = (await loadAll())
        .map(UniqueQuizKeyGenerator.keyFromItem)
        .toSet();
    final newItems = normalized
        .where((item) => !existingIds.contains(item.id))
        .toList(growable: false);
    if (newItems.isNotEmpty) {
      await db.transaction((txn) async {
        for (final item in newItems) {
          await txn.insert(_table, item.toDb());
        }
      });
    }
    final result = await loadAll();
    QuizBankCache.instance.assign(result);
    return result;
  }

  /// 按 id 更新；不存在则插入（同题已存在时保持原记录）。
  static Future<List<QuizBankItem>> upsertItem(QuizBankItem item) async {
    return importItems([item]);
  }

  /// 仅更新图片字段（离线缓存回写本地路径用）。
  static Future<void> updateImagePath(String id, String imagePath) async {
    final db = await _database();
    final affected = await db.update(
      _table,
      {'image': imagePath, 'updatedAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (affected > 0) {
      QuizBankCache.instance.assign(await loadAll());
    }
  }

  /// 更新云端投稿元数据（不改题干/选项/答案）。
  static Future<void> updateSyncMeta(
    String id, {
    required String syncStatus,
    DateTime? lastSubmitAt,
    String? lastSubmitError,
    String? remoteSubmissionId,
    bool clearLastSubmitError = false,
  }) async {
    final db = await _database();
    final patch = <String, Object?>{
      'syncStatus': syncStatus,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    if (lastSubmitAt != null) {
      patch['lastSubmitAt'] = lastSubmitAt.toIso8601String();
    }
    if (clearLastSubmitError) {
      patch['lastSubmitError'] = null;
    } else if (lastSubmitError != null) {
      patch['lastSubmitError'] = lastSubmitError;
    }
    if (remoteSubmissionId != null) {
      patch['remoteSubmissionId'] = remoteSubmissionId;
    }
    final affected = await db.update(
      _table,
      patch,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (affected > 0) {
      QuizBankCache.instance.assign(await loadAll());
    }
  }

  /// 云端同步合并：新题插入；已存在题可补写 image/analysis，不覆盖题干答案。
  static Future<int> mergeCloudItems(List<QuizBankItem> items) async {
    final db = await _database();
    final normalized = QuizBankImportNormalizer.canonicalize(items).items;
    if (normalized.isEmpty) return 0;
    var inserted = 0;
    await db.transaction((txn) async {
      for (final item in normalized) {
        final existing = await txn.query(
          _table,
          where: 'id = ?',
          whereArgs: [item.id],
          limit: 1,
        );
        if (existing.isEmpty) {
          final cloudItem = item.copyWith(
            origin: 'cloud',
            syncStatus: QuizSyncStatus.published,
            source: item.source.contains('云端') ? item.source : '云端题库',
            clearLastSubmitError: true,
          );
          await txn.insert(_table, cloudItem.toDb());
          inserted++;
          continue;
        }
        final row = existing.first;
        final oldImage = (row['image']?.toString() ?? '').trim();
        final newImage = (item.imageUrl ?? '').trim();
        final oldAnalysis = (row['analysis']?.toString() ?? '').trim();
        final newAnalysis = (item.analysis ?? '').trim();
        final oldCategory = (row['category']?.toString() ?? '').trim();
        final newCategory = item.category.trim();
        final oldOrigin = (row['origin']?.toString() ?? '').trim();
        final patch = <String, Object?>{};
        if (newImage.isNotEmpty) {
          final oldIsLocal =
              oldImage.startsWith('/') || oldImage.startsWith('file:');
          final newIsRemote =
              newImage.startsWith('http') || newImage.startsWith('/api/');
          if (oldImage.isEmpty ||
              (!oldIsLocal && newIsRemote && oldImage != newImage)) {
            patch['image'] = newImage;
          }
        }
        if (oldAnalysis.isEmpty && newAnalysis.isNotEmpty) {
          patch['analysis'] = newAnalysis;
        }
        if (oldCategory.isEmpty && newCategory.isNotEmpty) {
          patch['category'] = newCategory;
        }
        if (oldOrigin.isEmpty || oldOrigin == 'local') {
          patch['origin'] = 'cloud';
        }
        // 云端正式库命中后，本地投稿态收敛为已上云。
        patch['syncStatus'] = QuizSyncStatus.published;
        patch['lastSubmitError'] = null;
        if (patch.isNotEmpty) {
          patch['updatedAt'] = DateTime.now().toIso8601String();
          await txn.update(
            _table,
            patch,
            where: 'id = ?',
            whereArgs: [item.id],
          );
        }
      }
    });
    QuizBankCache.instance.assign(await loadAll());
    return inserted;
  }

  /// Atomically writes the replacement before removing the old identity.
  /// If the insert fails, the transaction rolls back and keeps [oldId].
  static Future<List<QuizBankItem>> replaceItem(
    String oldId,
    QuizBankItem newItem,
  ) async {
    final db = await _database();
    final canonical = newItem.copyWith(
      id: UniqueQuizKeyGenerator.keyFromItem(newItem),
    );
    await db.transaction((txn) async {
      await txn.insert(
        _table,
        canonical.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (oldId != canonical.id) {
        await txn.delete(_table, where: 'id = ?', whereArgs: [oldId]);
      }
    });
    final result = await loadAll();
    QuizBankCache.instance.assign(result);
    return result;
  }

  static Future<List<QuizBankItem>> deleteById(String id) async {
    final db = await _database();
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
    final result = await loadAll();
    QuizBankCache.instance.assign(result);
    return result;
  }

  /// Applies a cloud tombstone only to the cloud-owned local mirror.
  /// A local OCR/manual record is never deleted merely because a cloud item
  /// with a coincident identity was withdrawn.
  static Future<int> deleteCloudItem(String id) async {
    final db = await _database();
    final removed = await db.delete(
      _table,
      where: 'id = ? AND origin = ?',
      whereArgs: [id, 'cloud'],
    );
    if (removed > 0) {
      QuizBankCache.instance.assign(await loadAll());
    }
    return removed;
  }

  /// Removes legacy duplicates in one atomic rewrite and refreshes the cache.
  static Future<QuizBankDeduplicateResult> deduplicateAll() async {
    final current = await loadAll();
    final result = QuizBankDeduplicator.deduplicate(current);
    if (result.removed == 0) return result;
    await saveAll(result.items);
    return result;
  }

  /// 导出为 JSON 字符串（UTF-8 文本）。
  static Future<String> exportJsonString() async {
    final items = await loadAll();
    return const JsonEncoder.withIndent('  ').convert({
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'count': items.length,
      'items': items.map((e) => e.toJson()).toList(),
    });
  }

  /// 从 JSON 导入。merge=true 合并（同 id 覆盖）；false 整库替换。
  /// [imported] and [total] are retained for older callers. The extra counters
  /// describe v2 canonical-ID migration and duplicate handling.
  static Future<
    ({int imported, int total, int added, int overwritten, int skipped})
  >
  importFromJsonString(String raw, {bool merge = true}) async {
    final decoded = jsonDecode(raw);
    List list;
    if (decoded is Map && decoded['items'] is List) {
      list = decoded['items'] as List;
    } else if (decoded is List) {
      list = decoded;
    } else {
      throw const FormatException('无法识别的题库 JSON 格式');
    }
    final parsedItems = <QuizBankItem>[];
    var invalidRecords = 0;
    for (final entry in list) {
      if (entry is Map) {
        final item = QuizBankItem.fromJson(Map<String, dynamic>.from(entry));
        parsedItems.add(item);
      } else {
        invalidRecords++;
      }
    }
    final normalized = QuizBankImportNormalizer.canonicalize(parsedItems);
    final items = normalized.items;
    final skipped = normalized.skipped + invalidRecords;
    if (!merge) {
      final db = await _database();
      await db.transaction((txn) async {
        await txn.delete(_table);
        for (final item in items) {
          await txn.insert(_table, item.toDb());
        }
      });
      QuizBankCache.instance.assign(items);
      return (
        imported: items.length,
        total: items.length,
        added: items.length,
        overwritten: 0,
        skipped: skipped,
      );
    }
    final existingItems = await loadAll();
    final existingIds = existingItems
        .map(UniqueQuizKeyGenerator.keyFromItem)
        .toSet();
    final duplicateInBank = items
        .where((item) => existingIds.contains(item.id))
        .length;
    final added = items.length - duplicateInBank;
    final merged = await importItems(items);
    return (
      imported: added,
      total: merged.length,
      added: added,
      overwritten: 0,
      skipped: skipped + duplicateInBank,
    );
  }

  static Future<void> clearAll() async {
    final db = await _database();
    await db.delete(_table);
    QuizBankCache.instance.reset();
  }
}
