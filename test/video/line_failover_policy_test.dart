import 'package:box/video/widgets/player/line_failover_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('计数器跨重试保留：第二次失败才自动换线路', () {
    final policy = LineFailoverPolicy();

    // 第一次失败：还是把错误给用户看（错误层里有「换线路重试」和「重试线路」）。
    expect(policy.recordFailure(hasFallbackLine: true), isFalse);
    expect(policy.failures, 1);

    // 用户点了重试仍失败 → 自动换线路。
    expect(policy.recordFailure(hasFallbackLine: true), isTrue);
    expect(policy.failures, 0);
  });

  test('只有真正起播成功才清零，没报错不算成功', () {
    final policy = LineFailoverPolicy();
    policy.recordFailure(hasFallbackLine: true);
    expect(policy.failures, 1);

    policy.recordPlaybackStarted();
    expect(policy.failures, 0);
  });

  test('没有可换的线路时不换线路，也不留残留计数', () {
    final policy = LineFailoverPolicy();
    expect(policy.recordFailure(hasFallbackLine: false), isFalse);
    expect(policy.failures, 0);
  });

  test('无需再试的失败（网页线路）一次就换线路', () {
    final policy = LineFailoverPolicy();
    expect(
      policy.recordFailure(hasFallbackLine: true, decisive: true),
      isTrue,
    );
  });

  test('阈值可调且必须为正数', () {
    final policy = LineFailoverPolicy(threshold: 3);
    expect(policy.recordFailure(hasFallbackLine: true), isFalse);
    expect(policy.recordFailure(hasFallbackLine: true), isFalse);
    expect(policy.recordFailure(hasFallbackLine: true), isTrue);
    expect(() => LineFailoverPolicy(threshold: 0), throwsA(isA<AssertionError>()));
  });
}
