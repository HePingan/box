import 'package:box/utils/diagnostic_report.dart';
import 'package:box/utils/log_channels.dart';
import 'package:flutter_test/flutter_test.dart';

/// 这组测试守的是一条硬约束：**报告头的「生成时间」必须晚于日志正文最后一行**。
///
/// 起因是朋友机（Android AQ3A.240829.003）2026-09-06 回传的真实小窗报告：
///
/// ```
/// 生成时间: 2026-09-06T07:57:29.202109      ← 头部
/// [2026-09-06T07:57:58.369351][BoxFlutterWindow] event=window_focus:false ...
/// [2026-09-06T07:58:01.861719][BoxFlutterWindow] event=after_layout:...
/// ```
///
/// 头部时间比第一行日志早 29 秒、比最后一行早 32 秒。日志不可能来自未来，
/// 所以这个时间戳是错的。
///
/// 根因：`generatedAt` 是 `prime()` 在 app_bootstrap 启动时 `collect()` 里取的
/// `DateTime.now()`，之后整个进程复用同一份缓存。于是「生成时间」实际是
/// **App 启动时间**，不是点复制的时间——偏多少取决于 App 开了多久。
///
/// 缓存版本号本身是对的（复制路径不能等 platform channel，见
/// diagnostic_header_cache_test.dart），错的是把 `generatedAt` 一起缓存了。
void main() {
  setUp(() => DiagnosticHeader.resetCacheForTest());
  tearDown(() => DiagnosticHeader.resetCacheForTest());

  /// 朋友机那份报告的首尾两行，逐字照抄。
  const firstLine =
      '[2026-09-06T07:57:58.369351][BoxFlutterWindow] '
      'event=window_focus:false renderMode=texture size=1080x2400 '
      'configDp=384x853 multiWindow=false orientation=1';
  const lastLine =
      '[2026-09-06T07:58:01.861719][BoxFlutterWindow] '
      'event=after_layout:configuration_changed renderMode=texture '
      'size=1080x2400 configDp=384x853 multiWindow=false orientation=1';

  List<LogEntry> entriesOf(List<String> raw) =>
      raw.map(LogEntry.parse).toList(growable: false);

  group('生成时间必须是「复制那一刻」，不是 App 启动那一刻', () {
    test('启动很久后复制，生成时间不得停留在启动时间', () async {
      // 模拟启动时预取：版本号是那一刻拿到的，generatedAt 也是那一刻。
      final bootTime = DateTime.now().subtract(const Duration(hours: 2));
      DiagnosticHeader.resetCacheForTest(
        DiagnosticHeader(
          appVersion: '1.12.0',
          buildNumber: '205',
          packageName: 'top.hpa888.box',
          osVersion: 'AQ3A.240829.003',
          generatedAt: bootTime,
        ),
      );

      final header = DiagnosticHeader.cachedOrPlaceholder;

      // 版本信息必须仍然走缓存（不许为此回退成同步打 channel）。
      expect(header.appVersion, '1.12.0');
      expect(header.buildNumber, '205');
      expect(header.packageName, 'top.hpa888.box');

      // 但时间必须是现在，不是两小时前那次启动。
      expect(
        header.generatedAt.isAfter(bootTime),
        isTrue,
        reason: '生成时间还停在启动时刻，报告头会把 App 启动时间冒充成报障时间',
      );
      expect(
        DateTime.now().difference(header.generatedAt).inSeconds.abs(),
        lessThan(5),
        reason: '生成时间应贴近调用时刻',
      );
    });

    test('连续两次读取，生成时间会推进（版本号仍复用缓存）', () async {
      DiagnosticHeader.resetCacheForTest(
        DiagnosticHeader(
          appVersion: '1.12.0',
          buildNumber: '205',
          packageName: 'top.hpa888.box',
          osVersion: 'AQ3A.240829.003',
          generatedAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      );

      final a = DiagnosticHeader.cachedOrPlaceholder;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final b = DiagnosticHeader.cachedOrPlaceholder;

      expect(b.generatedAt.isAfter(a.generatedAt), isTrue);
      // 版本三项仍旧一致：证明没有为了刷新时间而重打 channel。
      expect(b.appVersion, a.appVersion);
      expect(b.buildNumber, a.buildNumber);
      expect(b.packageName, a.packageName);
    });

    test('朋友机那份报告的时序不许再出现：头部时间晚于最后一行日志', () {
      // 缓存的 generatedAt 故意设在日志之前，复现原缺陷的条件。
      DiagnosticHeader.resetCacheForTest(
        DiagnosticHeader(
          appVersion: '1.12.0',
          buildNumber: '205',
          packageName: 'top.hpa888.box',
          osVersion: 'AQ3A.240829.003',
          generatedAt: DateTime.parse('2026-09-06T07:57:29.202109'),
        ),
      );

      final entries = entriesOf([firstLine, lastLine]);
      final header = DiagnosticHeader.cachedOrPlaceholder;

      final lastLogTime = entries.last.timestamp;
      expect(lastLogTime, isNotNull, reason: '这两行是标准格式，应能解析出时间');

      expect(
        header.generatedAt.isBefore(lastLogTime!),
        isFalse,
        reason: '生成时间早于最后一行日志 —— 正是朋友机报告里那个不可能的时序',
      );

      // 报告文本里也不许再出现那个启动时间戳。
      final text = DiagnosticReport.compose(
        header: header,
        entries: entries,
        scopeLabel: '窗口',
      );
      expect(text, isNot(contains('2026-09-06T07:57:29.202109')));
    });

    test('无缓存的占位头部同样用当前时间', () {
      final before = DateTime.now();
      final header = DiagnosticHeader.cachedOrPlaceholder;

      expect(header.appVersion, '未知');
      expect(
        header.generatedAt.isBefore(before.subtract(const Duration(seconds: 1))),
        isFalse,
      );
    });
  });
}
