// 读屏用量（B1，2026-10-01）：服务端在**响应头**回报「今日用量 / 每日上限」，
// 客户端把它显示在自检页 —— 此前只有额度用完时的 429 才知道超了。
//
// 两个易错点在这里锁死：
//   1) **大小写**：Dart 的 http 会把头名转小写，服务端发的是 `X-Quiz-Vision-Used`，
//      真机验证时我就因为按大写取值取漏了，误判成"没上线"；
//   2) 老服务端**没有**这两个头 → 不能把已有值清成 null（否则自检页会从有数字变回"未知"）。
import 'package:box/features/quiz_plugin/domain/quiz_vision_usage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(QuizVisionUsage.reset);
  tearDown(QuizVisionUsage.reset);

  test('服务端头名原样（X-Quiz-Vision-Used）也能读到', () {
    QuizVisionUsage.record({
      'X-Quiz-Vision-Used': '3',
      'X-Quiz-Vision-Cap': '100',
    });
    expect(QuizVisionUsage.usedToday, 3);
    expect(QuizVisionUsage.dailyCap, 100);
    expect(QuizVisionUsage.updatedAt, isNotNull);
  });

  test('http 包转小写后的头名也能读到（真机走的就是这条）', () {
    QuizVisionUsage.record({
      'x-quiz-vision-used': '7',
      'x-quiz-vision-cap': '100',
    });
    expect(QuizVisionUsage.usedToday, 7);
    expect(QuizVisionUsage.describe(), contains('7/100'));
  });

  test('老服务端没有这两个头 → 保持原值，不清空', () {
    QuizVisionUsage.record({'x-quiz-vision-used': '5', 'x-quiz-vision-cap': '100'});
    QuizVisionUsage.record({'content-type': 'application/json'});
    expect(QuizVisionUsage.usedToday, 5);
    expect(QuizVisionUsage.dailyCap, 100);
  });

  test('只有一个头时，另一个保持原值', () {
    QuizVisionUsage.record({'x-quiz-vision-cap': '100'});
    QuizVisionUsage.record({'x-quiz-vision-used': '12'});
    expect(QuizVisionUsage.usedToday, 12);
    expect(QuizVisionUsage.dailyCap, 100, reason: '上限不该被清掉');
  });

  test('从没发过请求时如实说"未知"，不编造 0', () {
    expect(QuizVisionUsage.describe(), contains('未知'));
    QuizVisionUsage.record({'content-type': 'application/json'});
    expect(QuizVisionUsage.describe(), contains('未知'));
  });
}
