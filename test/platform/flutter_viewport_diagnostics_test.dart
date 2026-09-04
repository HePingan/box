// 朋友机 K80(HyperOS) 2026-09-04T21:04:57 日志读出来的缺口：
//
//   configuration_changed        size=1080x1728  configDp=384x853  multiWindow=false
//   after_layout:configuration_changed size=1080x2400 configDp=384x853 multiWindow=false
//
// 原生侧 24ms 内就把高度恢复到 2400，也没有 after_layout_timeout ——
// 「窗口高度卡在 1728」这个判断在原生层不成立。
//
// 但全项目没有任何地方监听 didChangeMetrics（本测试写之前 grep 确认为 0 处），
// 所以 Flutter 侧的 physicalSize 有没有跟着原生一起回到 2400，日志里是**空白**。
// 这是目前唯一还没有证据覆盖的一层：原生窗口恢复了、Flutter 视口没跟上，
// 表现出来同样是「退出分屏后界面还是小窗那么高」。
//
// 这些断言锁的是「视口变化必须留痕」，不是锁某个具体尺寸——
// 真实数值要等朋友机新日志回来才能判断哪一层出问题。
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/platform/flutter_viewport_diagnostics.dart';
import 'package:box/utils/app_logger.dart';

/// AppLogger 只存拼好的字符串（`[时间][tag] message`），没有结构化 entries。
List<String> _taggedLines() => AppLogger.instance.lines.value
    .where((l) => l.contains('[${FlutterViewportDiagnostics.logTag}]'))
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // AppLogger.clear() 会去碰 SharedPreferences（测试环境无插件），
  // 这里只按 tag 过滤，不清全局缓冲——用每条测试自己的基线长度做增量断言。
  int baseline = 0;

  setUp(() {
    baseline = _taggedLines().length;
  });

  List<String> viewportLines() => _taggedLines().sublist(baseline);

  /// attach 会额外记一条 `event=attach` 基线（没有它就不知道第一次变化是从
  /// 多少变过来的）。这里只看真正的尺寸变化事件。
  List<String> metricsLines() =>
      viewportLines().where((l) => l.contains('event=metrics')).toList();

  test('视口变化必须落进 AppLogger，与原生 after_layout 同页对照', () {
    final diagnostics = FlutterViewportDiagnostics()..attach();
    addTearDown(diagnostics.detach);

    // 模拟退出分屏：Flutter 侧 physicalSize 从小窗高度回到全屏高度。
    diagnostics.debugRecordMetrics(
      const Size(1080, 1728),
      2.8125,
    );
    diagnostics.debugRecordMetrics(
      const Size(1080, 2400),
      2.8125,
    );

    final lines = metricsLines();
    expect(
      lines.length,
      2,
      reason: '原生报了 1728→2400，Flutter 侧必须有对应两条，否则无法判断是哪一层没跟上',
    );
    expect(
      lines.last,
      contains('physicalSize=1080x2400'),
      reason: '要能直接和原生 after_layout 的 size=1080x2400 逐字对照',
    );
    expect(
      lines.last,
      contains('logicalSize=384x853'),
      reason: '逻辑尺寸才是布局真正用的值，必须记出来（2400/2.8125≈853）',
    );
  });

  test('尺寸没变不重复记，避免顶掉 AppLogger 仅 1000 行的环形缓冲', () {
    final diagnostics = FlutterViewportDiagnostics()..attach();
    addTearDown(diagnostics.detach);

    diagnostics.debugRecordMetrics(const Size(1080, 2400), 2.8125);
    diagnostics.debugRecordMetrics(const Size(1080, 2400), 2.8125);
    diagnostics.debugRecordMetrics(const Size(1080, 2400), 2.8125);

    expect(
      metricsLines().length,
      1,
      reason: '小窗拖拽会高频触发 didChangeMetrics，不去重会把现场上下文刷没',
    );
  });

  test('tag 与原生一致的前缀，便于用户一次复制两层日志', () {
    expect(FlutterViewportDiagnostics.logTag, 'BoxFlutterViewport');
  });

  test('detach 后不再记录，避免测试与页面重建期间重复挂 observer', () {
    final diagnostics = FlutterViewportDiagnostics()..attach();
    diagnostics.debugRecordMetrics(const Size(1080, 2400), 2.8125);
    diagnostics.detach();
    diagnostics.debugRecordMetrics(const Size(1080, 1728), 2.8125);

    expect(metricsLines().length, 1);
  });
}
