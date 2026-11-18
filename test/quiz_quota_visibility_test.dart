// 第 2 批回归（2026-11-18）：服务端配置/额度可见（P3-4、P3-7）。
//
// 锁三件事：
//   1) 后端 `/api/quiz/vision/config` 的字段解析（老服务端缺字段不能崩）。
//   2) 额度文案要说清「重置时刻」与「上游失败不计额度」——这两件事是这轮修的
//      额度语义（失败不再扣额度、日界是 UTC ⇒ 北京时间 08:00）。
//   3) 没有身份时服务端不回个人额度，界面必须显示「未知」而不是 0。
import 'package:box/features/quiz_plugin/data/quiz_vision_server_config.dart';
import 'package:box/features/quiz_plugin/domain/quiz_vision_usage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(QuizVisionUsage.reset);
  tearDown(QuizVisionUsage.reset);

  group('服务端配置解析', () {
    test('完整字段', () {
      final cfg = QuizVisionServerConfig.fromJson({
        'enabled': true,
        'model': 'qodercn/qfmodel',
        'thinkingOff': true,
        'dailyCapPerAccount': 100,
        'usedToday': 7,
        'remainingToday': 93,
        'failedToday': 2,
        'resetsAt': '2026-11-19T00:00:00.000Z',
        'upstreamBudgetSeconds': 35,
      })!;
      expect(cfg.model, 'qodercn/qfmodel');
      expect(cfg.usedToday, 7);
      expect(cfg.remainingToday, 93);
      expect(cfg.failedToday, 2);
      expect(cfg.upstreamBudgetSeconds, 35);
      expect(cfg.resetsAt, isNotNull);
      expect(cfg.describeModel(), contains('已关思考'));
      expect(cfg.describeQuota(), contains('7/100'));
      expect(cfg.describeQuota(), contains('不计额度'));
    });

    test('老服务端（无 used/remaining）→ 额度显示未知，不显示 0', () {
      final cfg = QuizVisionServerConfig.fromJson({
        'enabled': true,
        'model': 'x',
        'dailyCapPerAccount': 100,
      })!;
      expect(cfg.usedToday, isNull);
      expect(cfg.describeQuota(), contains('未知'));
    });

    test('缺 dailyCapPerAccount（不是我们的服务端）→ 解析失败而不是当成 0 次', () {
      expect(QuizVisionServerConfig.fromJson({'model': 'x'}), isNull);
      expect(QuizVisionServerConfig.fromJson('nope'), isNull);
      expect(QuizVisionServerConfig.fromJson(null), isNull);
    });

    test('后台未启用时如实说明（不让用户以为是自己没配好）', () {
      final cfg = QuizVisionServerConfig.fromJson({
        'enabled': false,
        'dailyCapPerAccount': 100,
      })!;
      expect(cfg.describeModel(), contains('未配置'));
    });

    test('数字以字符串形式回来也认（Dart/JSON 双端的常见坑）', () {
      final cfg = QuizVisionServerConfig.fromJson({
        'dailyCapPerAccount': '100',
        'usedToday': '3',
      })!;
      expect(cfg.dailyCap, 100);
      expect(cfg.usedToday, 3);
    });
  });

  group('用量文案（响应头 + 主动查询共用）', () {
    test('没数据时说未知，不说 0 次', () {
      expect(QuizVisionUsage.describe(), contains('未知'));
    });

    test('重置时刻按本地时间显示（UTC 00:00 ⇒ 北京 08:00）', () {
      QuizVisionUsage.usedToday = 5;
      QuizVisionUsage.dailyCap = 100;
      QuizVisionUsage.failedToday = 1;
      QuizVisionUsage.resetsAt = DateTime.utc(2026, 11, 19);
      final text = QuizVisionUsage.describe();
      expect(text, contains('5/100'));
      expect(text, contains('08:00'));
      expect(text, contains('不计额度'));
    });

    test('响应头只带 used/cap 时也能出文案（不依赖 resetsAt）', () {
      QuizVisionUsage.record({'x-quiz-vision-used': '12', 'x-quiz-vision-cap': '100'});
      final text = QuizVisionUsage.describe();
      expect(text, contains('12/100'));
      expect(text.contains('重置'), isFalse);
    });

    test('reset 之后回到未知', () {
      QuizVisionUsage.record({'x-quiz-vision-used': '12', 'x-quiz-vision-cap': '100'});
      QuizVisionUsage.reset();
      expect(QuizVisionUsage.describe(), contains('未知'));
    });
  });
}
