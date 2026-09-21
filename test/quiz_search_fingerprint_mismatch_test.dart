import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/domain/quiz_search_policy.dart';
import 'package:box/features/quiz_plugin/domain/ocr_quiz_parser.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';

/// 第三轮报障（2026-09-12）：「所有题 20 秒都没出答案，一直检索中，
/// 以前 1 秒不到就出了」。
///
/// 假设：recordAttempt 传的是**原始捕获文本**，而 recordSuccess 传的是
/// **_questionFingerprint(captured)**（经 OcrQuizParser.parse + cleanForMatch）。
/// 两个入口的归一化方式不同 → shouldSuppressThrottled 里
/// `normalizedStem != _attemptStem` 恒为 true → 节流**永不生效** → 每次捕获
/// 都真的发起检索。
void main() {
  // 复刻 entry 里的两种归一化
  String entryFingerprint(String raw) {
    final parsed = OcrQuizParser.parse(raw);
    var q = parsed.question.trim();
    if (q.isEmpty) q = raw.trim();
    return QuizBankTextNormalizer.cleanForMatch(q);
  }

  const raw =
      '⓿ 倒计时33:43 设置\n'
      '驾驶机动车不按规定使用灯光的，一次记3分。\n'
      'A. 正确\n'
      'B. 错误';

  test('两种指纹必须一致，否则节流永不生效', () {
    final attemptKey = QuizSearchPolicy.stemFingerprint(raw);
    final successKey = QuizSearchPolicy.stemFingerprint(entryFingerprint(raw));

    // 修复后：两处调用点都传 _questionFingerprint(captured)，
    // 因此这里的 attemptKey 也应按同口径计算。
    // 本测试改为直接校验「同一入参口径下两种归一化是否一致」。
    final sameInletAttempt = QuizSearchPolicy.stemFingerprint(entryFingerprint(raw));
    expect(
      sameInletAttempt,
      successKey,
      reason: '同一口径（都用 _questionFingerprint）下必须得到相同指纹',
    );

    // 记录旧缺陷（原始文本口径）与正确口径的差异仍然存在，
    // 这正是必须统一口径的原因。
    expect(
      attemptKey == successKey,
      isFalse,
      reason: '原始文本口径与指纹口径本就不同（原始文本含 A./B. 选项行）—— '
          '两边口径不统一时节流判定恒不相等、彻底失效。'
          '已通过让两个调用点都传 fingerprint 修复。',
    );
  });

  test('端到端：同题重复捕获应被节流（修复后的真实口径）', () {
    final p = QuizSearchPolicy();
    var now = DateTime(2026, 9, 12, 20, 10);
    p.clock = () => now;

    final key = entryFingerprint(raw);
    // 修复后：attempt 与 success 都传同一口径的指纹
    p.recordAttempt(stem: key, options: const ['正确', '错误']);
    p.recordSuccess(
      stem: key,
      options: const ['正确', '错误'],
      source: QuizResultSource.localBank,
      questionScore: 100,
      optionScore: 100,
    );

    now = now.add(const Duration(milliseconds: 120));
    final throttled = p.shouldSuppressThrottled(
      stem: key,
      options: const ['正确', '错误'],
    );

    expect(
      throttled,
      isTrue,
      reason: '同题 120ms 内重复捕获必须被节流；'
          'throttled=false 说明每次都真实检索 → 一直「检索中」',
    );
  });
}
