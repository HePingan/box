// 红灯回归：来源排名的题干键被「|image:」后缀撕裂。
//
// 背景（2026-09-19 真机报障，驾考宝典判断题截图）：
//   AI 读屏答案（正确/A）上屏 <1 秒后被「请人工确认 候选1：正确 候选2：错误」
//   覆盖。过程区仍留着 AI 的「③第1次请求 ④识别成功9270ms」——说明是
//   同题的第二次结果**原地覆盖**，不是新题流程（新题会清过程日志）。
//
// 链条（代码实证）：
//   1. 首捕：题库冷启动未命中 → AI 读屏兜底 → 答案上屏，
//      recordSuccess(source=aiVision rank 5)，题干键 = 无后缀指纹。
//   2. 无障碍 ticker 对同题再捕获，题库此时已加载完 → 搜出同题干 2 条
//      互斥候选（引擎 ambiguous 护栏，正常）→ canReplaceWith(localBank rank 4)。
//   3. BUG：_runSearch 的 requestFingerprint 带「|image:<dHash>」后缀
//      （切题身份口径），而 recordSuccess 存的是无后缀指纹 →
//      canReplaceWith 误判「换题，旧排名作废」→ rank 4 顶掉 rank 5。
//
// 契约：来源排名/节流一律以**纯题干**为键；「|image:」后缀只属于
// 切题身份（generation/activeFingerprint）机制，两者不得混用。
import 'package:box/features/quiz_plugin/domain/quiz_search_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const stem =
      '这个标志的含义是禁止车货总体外廓高度超过标志所示数值的车辆通行';
  const suffixed = '$stem|image:0123456789abcdef';

  group('同题判定不受 |image: 后缀影响', () {
    test('低秩来源(localBank)同题不得顶掉已上屏的 aiVision 答案', () {
      final p = QuizSearchPolicy();
      p.recordSuccess(
        stem: stem,
        options: const ['正确', '错误'],
        source: QuizResultSource.aiVision,
        questionScore: 0,
        optionScore: 0,
      );
      // 真实调用点传的是带题图后缀的 requestFingerprint。
      expect(
        p.canReplaceWith(QuizResultSource.localBank, stem: suffixed),
        isFalse,
        reason: '同题 rank 4 < rank 5 必须被拦，否则题库候选会覆盖 AI 答案'
            '（2026-09-19 报障：AI 答案显示<1s 被刷成候选）',
      );
    });

    test('后缀方向反过来（存带后缀、查无后缀）同样识别为同题', () {
      final p = QuizSearchPolicy();
      p.recordSuccess(
        stem: suffixed,
        options: const ['正确', '错误'],
        source: QuizResultSource.localBank,
        questionScore: 100,
        optionScore: 100,
      );
      expect(
        p.canReplaceWith(QuizResultSource.externalApi, stem: stem),
        isFalse,
      );
    });

    test('高秩来源(aiVision)同题仍可覆盖 localBank（既有契约不回归）', () {
      final p = QuizSearchPolicy();
      p.recordSuccess(
        stem: suffixed,
        options: const ['正确', '错误'],
        source: QuizResultSource.localBank,
        questionScore: 100,
        optionScore: 100,
      );
      expect(
        p.canReplaceWith(QuizResultSource.aiVision, stem: stem),
        isTrue,
      );
    });

    test('真换题（题干不同，无论带不带后缀）照旧放行', () {
      final p = QuizSearchPolicy();
      p.recordSuccess(
        stem: stem,
        options: const ['正确', '错误'],
        source: QuizResultSource.aiVision,
        questionScore: 0,
        optionScore: 0,
      );
      expect(
        p.canReplaceWith(
          QuizResultSource.localBank,
          stem: '另一道完全不同的题干|image:0123456789abcdef',
        ),
        isTrue,
        reason: '换题后旧排名作废的防跨题污染契约必须保留',
      );
    });

    test('stem 为空（含纯后缀的退化输入）不触发换题放行语义', () {
      final p = QuizSearchPolicy();
      p.recordSuccess(
        stem: stem,
        options: const ['正确', '错误'],
        source: QuizResultSource.aiVision,
        questionScore: 0,
        optionScore: 0,
      );
      // 防御：若调用方只传了后缀段（题干意外为空），不得被判成「换题」放行。
      expect(
        p.canReplaceWith(QuizResultSource.localBank, stem: '|image:0123456789abcdef'),
        isFalse,
      );
    });
  });
}
