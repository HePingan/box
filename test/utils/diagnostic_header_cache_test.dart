import 'package:box/utils/diagnostic_report.dart';
import 'package:flutter_test/flutter_test.dart';

/// 这组测试守的是一条设计约束：**复制/分享日志的路径不许依赖 platform channel**。
///
/// 起因是一个真实缺陷：最初 `_copyVisible` 里 `await DiagnosticHeader.collect()`，
/// 而 collect 内部要跨 channel 调 `PackageInfo.fromPlatform()`。插件没注册或
/// ROM 异常时那个 Future 迟迟不返回，用户点复制**毫无反应**——没提示、没报错、
/// 剪贴板也是空的。报障流程自己失效，是最不该出现的故障。
///
/// 现在版本信息启动时预取（`prime()`），复制路径同步读缓存。
void main() {
  setUp(() => DiagnosticHeader.resetCacheForTest());
  tearDown(() => DiagnosticHeader.resetCacheForTest());

  group('缓存缺失时的降级', () {
    test('没预取过也能同步拿到头部，不抛异常不阻塞', () {
      final header = DiagnosticHeader.cachedOrPlaceholder;

      expect(header.appVersion, '未知');
      expect(header.buildNumber, '未知');
      expect(header.packageName, '未知');
      // 系统版本走 dart:io，不经 channel，所以这一项仍是真实值。
      expect(header.osVersion, isNotEmpty);
    });

    test('占位头部照样能组装出完整报告', () {
      final text = DiagnosticReport.compose(
        header: DiagnosticHeader.cachedOrPlaceholder,
        entries: const [],
        scopeLabel: '全部',
      );

      expect(text, contains('===== Box 诊断报告 ====='));
      expect(text, contains('App 版本: 未知'));
    });
  });

  group('预取后走缓存', () {
    test('cachedOrPlaceholder 返回预取到的真实值', () {
      DiagnosticHeader.resetCacheForTest(
        DiagnosticHeader(
          appVersion: '1.10.0',
          buildNumber: '201',
          packageName: 'top.hpa888.box',
          osVersion: 'Android 15',
          generatedAt: DateTime.parse('2026-09-05T10:00:00.000'),
        ),
      );

      final header = DiagnosticHeader.cachedOrPlaceholder;
      expect(header.appVersion, '1.10.0');
      expect(header.buildNumber, '201');
      expect(header.packageName, 'top.hpa888.box');
    });

    test('连续读缓存返回同一份，不重复打 channel', () {
      DiagnosticHeader.resetCacheForTest(
        DiagnosticHeader(
          appVersion: '1.10.0',
          buildNumber: '201',
          packageName: 'top.hpa888.box',
          osVersion: 'Android 15',
          generatedAt: DateTime.parse('2026-09-05T10:00:00.000'),
        ),
      );

      final a = DiagnosticHeader.cachedOrPlaceholder;
      final b = DiagnosticHeader.cachedOrPlaceholder;

      expect(a.generatedAt, b.generatedAt);
    });
  });

  group('prime 的容错', () {
    test('测试环境下 PackageInfo 不可用，prime 不抛异常', () async {
      // 这里跑的是真实路径：测试环境没有 platform channel 实现，
      // PackageInfo 会抛 MissingPluginException，prime 必须吞掉它。
      await expectLater(DiagnosticHeader.prime(), completes);
    });

    test('prime 失败后仍能同步取到占位头部', () async {
      await DiagnosticHeader.prime();

      // 不论 prime 成功与否，这个调用都必须立刻返回可用对象。
      final header = DiagnosticHeader.cachedOrPlaceholder;
      expect(header.toLines(), hasLength(4));
    });
  });

  group('collect 的超时保护', () {
    test('collect 带超时上限，不会无限等 channel', () async {
      // 极短超时下也必须返回（落到「未知」），而不是挂住。
      final header = await DiagnosticHeader.collect(
        timeout: const Duration(milliseconds: 1),
      );

      expect(header.appVersion, '未知');
      expect(header.toLines(), hasLength(4));
    });
  });
}
