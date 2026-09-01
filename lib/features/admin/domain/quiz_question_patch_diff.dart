import 'quiz_bank_models.dart';

/// 计算题目编辑的最小改动集。
///
/// 为什么需要它：服务端 PATCH 自带查重——请求体里出现 `question` +
/// `options` 时，它会拿这份题干去比库。编辑一道已存在的题时，命中的
/// 正是这道题自己，于是报「题干与完整选项已存在，不能合并覆盖」。
///
/// 只发真正改了的字段，没动题干就不发题干，查重无从触发。
class QuizQuestionPatchDiff {
  const QuizQuestionPatchDiff._();

  /// 与查重相关、未改动时必须省略的字段。
  static const dedupSensitiveKeys = {'question', 'options'};

  /// 服务端接受同义别名的字段：任一改动则两个都要发，避免只更新一半。
  static const _aliasGroups = <Set<String>>[
    {'answer', 'correctAnswer'},
    {'explanation', 'analysis'},
  ];

  /// 从完整表单 [payload] 中剔除与 [original] 相同的字段。
  ///
  /// [original] 为 null（新建题目）时原样返回：新建必须发全字段。
  static Map<String, dynamic> minimize({
    required Map<String, dynamic> payload,
    QuizBankQuestion? original,
  }) {
    if (original == null) return Map<String, dynamic>.from(payload);

    final current = _snapshot(original);
    final out = <String, dynamic>{};

    for (final entry in payload.entries) {
      if (!current.containsKey(entry.key)) {
        // 服务端认识但本地快照没有的字段，保守起见照发。
        out[entry.key] = entry.value;
        continue;
      }
      if (!_same(entry.value, current[entry.key])) {
        out[entry.key] = entry.value;
      }
    }

    // 别名补齐：answer 改了就把 correctAnswer 一起发。
    for (final group in _aliasGroups) {
      if (group.any(out.containsKey)) {
        for (final key in group) {
          if (payload.containsKey(key)) out[key] = payload[key];
        }
      }
    }

    return out;
  }

  static Map<String, dynamic> _snapshot(QuizBankQuestion q) => {
    'question': q.question,
    'options': q.options,
    'answer': q.answer,
    'correctAnswer': q.answer,
    'status': q.status,
    'tags': q.tags,
    'explanation': q.explanation,
    'analysis': q.explanation,
    'category': q.category,
    'type': q.type,
    'image': q.image,
  };

  static bool _same(Object? a, Object? b) {
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_same(a[i], b[i])) return false;
      }
      return true;
    }
    final left = (a ?? '').toString().trim();
    final right = (b ?? '').toString().trim();
    return left == right;
  }
}
