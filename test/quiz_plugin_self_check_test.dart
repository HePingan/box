// 自检页的「复制结论」与日志环形缓冲（2026-10-01 事故后新增）。
//
// 为什么单测这一页：读屏卡住时，用户唯一的现场证据就是这段被他复制出来的文本，
// 所以两件事必须锁住：
//   1) 报告里**绝不能出现令牌/口令**（他会直接贴进聊天）；
//   2) 报告里必须带"卡在哪一步"这类定位信息，而不是只说"失败了"。
import 'package:box/features/quiz_plugin/domain/quiz_diag.dart';
import 'package:box/features/quiz_plugin/presentation/quiz_plugin_self_check_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('自检报告', () {
    test('报告带状态、阶段、自测结果与日志', () {
      final report = QuizPluginSelfCheckPage.buildReport(
        status: const {
          '无障碍服务': '已启用',
          '凭证模式': 'deviceProxy（平台代理）',
          '当前阶段': '截图',
        },
        probe: '失败：8000ms 内没拿到截图',
        recent: const ['14:20:01 RESULT 读屏跳过：未拿到截图'],
        important: const ['14:20:01 RESULT 截图无响应（超时）'],
      );

      expect(report, contains('无障碍服务：已启用'));
      expect(report, contains('当前阶段：截图'), reason: '定位信息必须在报告里');
      expect(report, contains('8000ms 内没拿到截图'));
      expect(report, contains('读屏跳过：未拿到截图'));
      expect(report, contains('截图无响应（超时）'));
    });

    test('报告里绝不出现令牌/口令（宽松判据，防将来改坏）', () {
      final report = QuizPluginSelfCheckPage.buildReport(
        status: const {'凭证模式': 'deviceProxy（平台代理）'},
        probe: '成功：12345 字节，耗时 320ms',
        recent: const ['14:20:01 RESULT 读屏凭证模式 mode=deviceProxy'],
        important: const [],
      );

      // 真令牌是 64 位 hex / 长随机串：报告里出现 32 位以上 hex 就是事故
      expect(
        RegExp(r'[0-9a-fA-F]{32,}').hasMatch(report),
        isFalse,
        reason: '报告会被用户贴进聊天，不能带任何令牌/设备标识',
      );
      expect(report, isNot(contains('Bearer')));
      expect(report, isNot(contains('sk-')));
    });

    test('没有日志时给「（无）」而不是空白', () {
      final report = QuizPluginSelfCheckPage.buildReport(
        status: const {'当前阶段': '准备'},
        probe: '未测试',
        recent: const [],
        important: const [],
      );

      expect(report, contains('【最近日志】'));
      expect(report, contains('（无）'));
    });
  });

  group('QuizDiag 日志缓冲', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      QuizDiag.clearAll();
    });

    test('recent 返回最近若干条，且是完整可读的一行', () {
      QuizDiag.log(QuizDiagStage.result, '第一条');
      QuizDiag.log(QuizDiagStage.result, '第二条');

      final recent = QuizDiag.recent(limit: 1);

      expect(recent.length, 1);
      expect(recent.single, contains('RESULT 第二条'));
      expect(
        RegExp(r'^\d\d:\d\d:\d\d ').hasMatch(recent.single),
        isTrue,
        reason: '带时间戳，用户贴出来我才知道先后',
      );
    });

    test('warn 级事件落本机（跨重启还能看到）', () async {
      QuizDiag.warn(QuizDiagStage.result, '截图无响应（超时）', fields: {'ms': 8000});
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final important = await QuizDiag.important();

      expect(
        important.any((l) => l.contains('截图无响应（超时）')),
        isTrue,
        reason: '真机常态是"卡住→用户重开 App"，只在内存里等于没有',
      );
    });

    test('clearAll 把内存与本机都清掉', () async {
      QuizDiag.warn(QuizDiagStage.result, '要清掉的事件');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await QuizDiag.clearAll();

      expect(QuizDiag.recent(), isEmpty);
      expect(await QuizDiag.important(), isEmpty);
    });
  });
}
