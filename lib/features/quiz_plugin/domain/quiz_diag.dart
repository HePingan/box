import 'package:flutter/foundation.dart';

import '../../../utils/app_logger.dart';
import '../../../utils/log_channels.dart';

// 重新导出，使调用方只需 import 本文件即可拿到 LogLevel / LogChannel，
// 减少链路各文件重复导入造成的漂移。
export '../../../utils/log_channels.dart' show LogLevel, LogChannel;

/// 答题插件的**诊断日志单一入口**。
///
/// 为什么要有它（2026-09-12）：
/// 用户连续三轮报「题不出答案 / 一直检索中」，而我只能靠单测和推测定位，
/// 真机现场的数据一条都拿不到 —— 他自己提出「把识别判断匹配这些写入调试日志」。
/// 这是对的做法：与其继续猜，不如让现场说话。
///
/// 为什么不让调用点各自写 `AppLogger`：
/// 1. 历史教训是散落在各处的 `debugPrint` 在 release 不落盘，报障人
///    按提示去日志页搜却搜不到（见 quiz_cloud_auto_sync.dart:93 的注释）。
/// 2. 识别/匹配链路一次捕获要产生十几条日志，逐处手写前缀必然漂移，
///    将来 grep 不到。这里统一格式与开关，保证同一格式可被稳定检索。
///
/// 统一格式（前两段由 AppLogger 补，后两段是本类负责）：
/// `[时间][QUIZ][级别] <阶段> <键=值 …>`
/// 其中 `<阶段>` 取 [QuizDiagStage] 的固定英文名，便于 grep：
///   PARSE / MATCH / THROTTLE / SOURCE / RESULT
///
/// **双写**：`AppLogger`（release 落盘、日志页可搜）+ `debugPrint`
/// （debug 时直接看控制台，且保持与历史日志一致的习惯）。
class QuizDiag {
  QuizDiag._();

  /// 总开关。默认开：这条链路的日志量可控（单次捕获十余行），
  /// 且用户正需要它来定位「不出答案」。真嫌吵可置 false。
  static const bool enabled = true;

  /// 单条日志里最长保留的题干/选项片段，避免整屏被长题干淹没。
  static const int _snippetMax = 60;

  /// 裁剪长文本，保留可辨认的开头。
  ///
  /// 刻意保留**开头**而不是结尾：题干的关键限定词（「驾驶机动车」「不按规定」
  /// 等）都在前面，匹配成功与否往往看它。
  static String snip(String raw) {
    final oneLine = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= _snippetMax) return oneLine;
    return '${oneLine.substring(0, _snippetMax)}…';
  }

  /// 写一条诊断日志。
  ///
  /// [stage] 见 [QuizDiagStage]；[fields] 建议用 `k=v` 形式的短串。
  static void log(
    QuizDiagStage stage,
    String message, {
    Map<String, Object?> fields = const {},
    LogLevel level = LogLevel.info,
  }) {
    if (!enabled) return;

    final suffix = fields.isEmpty
        ? ''
        : ' ${fields.entries.map((e) => '${e.key}=${e.value}').join(' ')}';

    final line = '${stage.tag} $message$suffix';
    // 双写：AppLogger 负责落盘与日志页检索，debugPrint 负责现场直读。
    AppLogger.instance.logTo(LogChannel.quiz, line, level: level);
    debugPrint('[QuizDiag][${stage.tag}] $message$suffix');
  }

  /// 便捷：记录一次「未命中/被拦下」这类需要用户一眼看到的问题。
  static void warn(
    QuizDiagStage stage,
    String message, {
    Map<String, Object?> fields = const {},
  }) =>
      log(stage, message, fields: fields, level: LogLevel.warn);
}

/// 识别 → 判断 → 匹配 链路的阶段划分。
///
/// 按**用户报障时实际会问的问题**切，而不是按代码模块切：
/// - 「字识别对了吗」→ PARSE
/// - 「题目在题库里吗、匹配打分多少」→ MATCH
/// - 「为什么重复搜/被拦了」→ THROTTLE
/// - 「几个来源谁赢了」→ SOURCE
/// - 「最终到底出没出答案」→ RESULT
enum QuizDiagStage {
  /// OCR / 无障碍文本 → 题干、选项、答案的解析结果。
  parse('PARSE'),

  /// 题库检索与相似度打分：候选数、最佳分、是否达阈值。
  match('MATCH'),

  /// 节流判断：是否被拦、拦的依据、指纹口径。
  throttle('THROTTLE'),

  /// 来源竞争：本地题库 / 外部 API / OCR 兜底的排名裁决与切题重置。
  source('SOURCE'),

  /// 最终结果：是否展示、展示什么、耗时。
  result('RESULT'),

  /// 题图感知哈希相关。
  image('IMAGE');

  const QuizDiagStage(this.tag);

  final String tag;
}
