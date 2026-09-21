import 'package:box/features/quiz_plugin/domain/quiz_vision_candidate.dart';
import 'package:flutter_test/flutter_test.dart';

/// AI 读屏命中 → 自动上报题库后端「待审核」区（P0）
///
/// 用户 2026-09-13 拍板四条口径（逐字）：
///   1. A 档不提交，保留该题的截图及 ai 识别的题目信息，后面我再手动补充
///   2. 命中静默
///   3. conf 大于等于 0.9
///   4. 可以（未登录静默禁用）
///
/// 本文件只测**纯决策函数**，不碰网络/数据库，保证红灯可复现。
void main() {
  QuizVisionCandidate build({
    String stem = '当事人未在道路交通事故现场报警，事后请求公安机关交通管理部门处理的，( )内作出是否受理的决定。',
    List<String> options = const ['A. 十日', 'B. 五日', 'C. 三日', 'D. 二日'],
    String answer = 'C',
    double confidence = 0.95,
    bool loggedIn = true,
    bool cloudPushAllowed = true,
    bool hasImage = true,
  }) => QuizVisionCandidate(
    stem: stem,
    options: options,
    answer: answer,
    confidence: confidence,
    capturedAt: DateTime.parse('2026-09-13T16:49:00'),
    imagePath: hasImage ? '/data/user/0/top.hpa888.box/files/vision_candidates/q_x.jpg' : null,
    loggedIn: loggedIn,
    cloudPushAllowed: cloudPushAllowed,
  );

  group('自动上报闸门（conf ≥ 0.9 + 选项≥2 + 已登录 + 云推送已开）', () {
    test('全部条件满足 → 允许静默上报', () {
      final c = build();
      expect(c.autoSubmitDecision, QuizVisionSubmitDecision.autoSubmit);
    });

    test('conf 低于 0.9（0.89）→ 不提交，仅留档', () {
      final c = build(confidence: 0.89);
      expect(c.autoSubmitDecision, QuizVisionSubmitDecision.keepLocalOnly);
      expect(c.keepReason, contains('置信度'));
    });

    test('conf 恰好 0.9 → 允许上报（“大于等于”）', () {
      final c = build(confidence: 0.9);
      expect(c.autoSubmitDecision, QuizVisionSubmitDecision.autoSubmit);
    });

    test('选项不足 2 项 → A 档：不提交，但保留截图与识别信息', () {
      final c = build(options: const ['A. 十日']);
      expect(c.autoSubmitDecision, QuizVisionSubmitDecision.keepLocalOnly);
      // A 档核心：即便不提交，也必须留档
      expect(c.stem.isNotEmpty, isTrue);
      expect(c.answer, 'C');
      expect(c.imagePath, isNotNull);
      expect(c.keepReason, contains('选项'));
    });

    test('选项为空 → 不提交，留档', () {
      final c = build(options: const []);
      expect(c.autoSubmitDecision, QuizVisionSubmitDecision.keepLocalOnly);
      expect(c.imagePath, isNotNull);
    });

    test('未登录 → 静默禁用，不提交（且不报错打扰用户）', () {
      final c = build(loggedIn: false);
      expect(c.autoSubmitDecision, QuizVisionSubmitDecision.keepLocalOnly);
      expect(c.keepReason, contains('登录'));
    });

    test('云推送被插件策略禁用 → 不提交', () {
      final c = build(cloudPushAllowed: false);
      expect(c.autoSubmitDecision, QuizVisionSubmitDecision.keepLocalOnly);
    });

    test('题干为空 → 不提交（后端会 400）', () {
      final c = build(stem: '   ');
      expect(c.autoSubmitDecision, QuizVisionSubmitDecision.keepLocalOnly);
    });

    test('答案为空 → 不提交', () {
      final c = build(answer: '');
      expect(c.autoSubmitDecision, QuizVisionSubmitDecision.keepLocalOnly);
    });
  });

  group('A 档留档：不提交的题必须完整保留截图 + 识别信息', () {
    test('toJson 往返保留题干/选项/答案/置信度/截图路径/留档原因', () {
      final c = build(confidence: 0.72, options: const ['A. 十日']);
      final json = c.toJson();
      final back = QuizVisionCandidate.fromJson(json);
      expect(back.stem, c.stem);
      expect(back.options, c.options);
      expect(back.answer, c.answer);
      expect(back.confidence, c.confidence);
      expect(back.imagePath, c.imagePath);
      expect(back.keepReason, c.keepReason);
    });

    test('留档候选可转成 QuizBankItem 供用户补充后投稿', () {
      final c = build(options: const ['A. 十日', 'B. 五日'], confidence: 0.72);
      final item = c.toBankItem(id: 'q_vision_test_1');
      expect(item.question, c.stem);
      expect(item.options.length, 2);
      expect(item.correctAnswer, 'C');
      expect(item.source, contains('AI读屏'));
    });
  });
}
