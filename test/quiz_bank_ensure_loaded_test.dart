import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';

/// 冷启动并发保护回归（2026-09-12）：
///
/// 首题会同时触发多条 ensureLoaded（读屏首搜 + 重试/OCR 兜底）。
/// 若保护失效，每条都全量查库，首题明显卡顿 —— 用户感知就是
/// 「改了后之前能秒出的题现在也出不来了」。
void main() {
  QuizBankItem item(String q) => QuizBankItem(
    id: q,
    question: q,
    type: QuizQuestionType.singleChoice,
    options: const ['A', 'B'],
    correctAnswer: 'A',
    category: '测试',
  );

  test('并发 ensureLoaded 只触发一次真实加载', () async {
    var loadCount = 0;
    final cache = QuizBankCache.forTestingWithLoader(() async {
      loadCount++;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return [item('q1')];
    });

    // 模拟首题并发的 5 路加载（读屏首搜 + repeat + OCR 兜底 + attempt+1）
    await Future.wait([
      cache.ensureLoaded(),
      cache.ensureLoaded(),
      cache.ensureLoaded(),
      cache.ensureLoaded(),
      cache.ensureLoaded(),
    ]);

    expect(
      loadCount,
      1,
      reason: '并发的 5 路 ensureLoaded 必须共享同一次加载；'
          'loadCount=$loadCount 说明保护失效，首题会重复全量查库 → 卡顿',
    );
    expect(cache.items.length, 1);
  });

  test('加载完成后，再 ensureLoaded 不应重复加载（走 _loaded 短路）', () async {
    var loadCount = 0;
    final cache = QuizBankCache.forTestingWithLoader(() async {
      loadCount++;
      return [item('q1')];
    });
    await cache.ensureLoaded();
    await cache.ensureLoaded();
    await cache.ensureLoaded();
    expect(loadCount, 1, reason: '已加载后必须短路，不得再次全量查库');
  });

  test('加载失败后允许重试（坏 Future 不得被永久共享）', () async {
    var attempts = 0;
    final cache = QuizBankCache.forTestingWithLoader(() async {
      attempts++;
      if (attempts == 1) throw StateError('首次加载失败');
      return [item('q1')];
    });

    await expectLater(cache.ensureLoaded(), throwsA(isA<StateError>()));
    // 第二次必须能重新加载，而不是 await 同一个已失败的 Future
    await cache.ensureLoaded();
    expect(attempts, 2, reason: '失败后必须允许重试，否则首题永久「检索中」');
    expect(cache.items.length, 1);
  });
}
