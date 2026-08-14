import 'dart:async';

/// 屏幕常亮策略。
///
/// 把"何时开、何时关"从 ReaderPage 的 initState/dispose 里抽出来，
/// 底层插件调用通过 [toggle] 注入，便于测试且避免插件在测试环境抛异常。
///
/// 修复的两个缺陷：
///   1. 进入阅读页时不按已持久化的 keepScreenOn 应用（旧实现只在设置面板里调），
///      用户开了常亮、退出重进后屏幕照常息屏。
///   2. 离开阅读页时从不释放常亮，整个 App 后续页面都不息屏、持续耗电。
class ReaderWakelockController {
  ReaderWakelockController({required Future<void> Function(bool) toggle})
      : _toggle = toggle;

  final Future<void> Function(bool) _toggle;

  bool _enabled = false;
  bool _disposed = false;

  /// 当前是否已持有常亮（仅反映本控制器的请求状态）。
  bool get enabled => _enabled;

  /// 按设置应用常亮。重复的同值调用会被吞掉，避免每次滑动亮度条都打一次平台通道。
  Future<void> apply(bool keepScreenOn) async {
    if (_disposed) return;
    if (_enabled == keepScreenOn) return;
    _enabled = keepScreenOn;
    await _guard(keepScreenOn);
  }

  /// 离开阅读页：无条件释放常亮。
  Future<void> release() async {
    if (_disposed) return;
    _disposed = true;
    if (!_enabled) return;
    _enabled = false;
    await _guard(false);
  }

  Future<void> _guard(bool value) async {
    try {
      await _toggle(value);
    } catch (_) {
      // 插件在部分平台/测试环境会抛异常，不能影响阅读流程。
    }
  }
}
