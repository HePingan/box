import 'package:box/utils/log_channels.dart';
import 'package:flutter_test/flutter_test.dart';

/// 全局错误钩子写出的 tag 必须能被频道筛选命中。
///
/// `app_bootstrap.dart` 的 `_installErrorHandlers()` 里：
/// - `FlutterError.onError` 写 `tag: 'FLUTTER'`
/// - `PlatformDispatcher.instance.onError` 走 `logError(..., 'DART')`
///
/// 这两个是**崩溃现场**，是用户报障时最该被看到的行。如果 tag 没被映射，
/// 它们会掉进 system 兜底，用户点「错误」筛选反而看不到崩溃日志。
void main() {
  group('全局错误钩子的 tag 必须归入错误频道', () {
    test("PlatformDispatcher 未捕获异常的 'DART' tag 归入 error", () {
      // 这是 app_bootstrap.dart:91 `logError(error, stack, 'DART')` 写出的 tag。
      expect(LogChannel.fromTag('DART'), LogChannel.error);
    });

    test("logError 的默认 tag 'ERROR' 归入 error", () {
      expect(LogChannel.fromTag('ERROR'), LogChannel.error);
    });

    test('未捕获异常不该被归进「系统」，否则筛错误时看不到崩溃', () {
      expect(LogChannel.fromTag('DART'), isNot(LogChannel.system));
    });
  });

  group('错误频道的行在「仅错误」筛选下可见', () {
    /// 复刻日志页 `_visible` 的过滤条件，锁住语义：
    /// 崩溃行即使级别是 info（旧格式没有级别段），只要频道是 error 也该留下。
    bool visibleUnderErrorsOnly(LogEntry e) =>
        e.level == LogLevel.error ||
        e.level == LogLevel.warn ||
        e.channel == LogChannel.error;

    test('旧格式的 DART 崩溃行（无级别段）在仅错误筛选下不被漏掉', () {
      final entry = LogEntry.parse(
        '[2026-09-05T10:00:00.000][DART] Error: Bad state: no element',
      );

      expect(entry.channel, LogChannel.error);
      expect(entry.level, LogLevel.info, reason: '旧格式没有级别段');
      expect(
        visibleUnderErrorsOnly(entry),
        isTrue,
        reason: '崩溃行必须能在「仅错误」下看到，否则报障时最关键的行被筛掉',
      );
    });

    test('普通 info 行在仅错误筛选下被排除', () {
      final entry = LogEntry.parse('[2026-09-05T10:00:00.000][PLAYER][I] 起播成功');

      expect(visibleUnderErrorsOnly(entry), isFalse);
    });
  });
}
