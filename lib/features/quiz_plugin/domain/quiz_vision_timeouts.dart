/// 读屏全链路的**时限唯一来源**（2026-10-01 事故后收口）。
///
/// 为什么必须收成一处：这些值之间**有必须成立的大小关系**（见下），散在四个文件里
/// 改一个忘一个，症状不是报错而是"永远转圈"或"误杀正在正常推进的慢请求"。
/// 关系由 `test/quiz_vision_timeout_ladder_test.dart` 锁住（含跨语言核对 Kotlin 常量）。
///
/// 链路与各自的终点（从内到外）：
///
/// ```text
///   Kotlin 截图看门狗 kotlinCaptureWatchdog (6s)   ← 原生自己先收尾，回 null
///      ↓ 必须 <
///   Dart 截图等待     capture              (8s)   ← 原生仍不回就自己收尾
///   Dart 凭证解析     resolve             (10s)   ← 本机存储/签发不回也收尾
///   Dart 普通通道     channel              (5s)   ← 悬浮窗/权限查询等
///   Dart 框选交互     userInteraction   (5min)   ← 等用户拖拽，不能短超时
///   引擎硬顶          engineHard          (45s)   ← 含重试与退避
///      ↓ 各阶段之和必须 ≤
///   流程兜底          flow                (75s)   ← 与实现无关的最后一道网
/// ```
///
/// 兜底 [flow] 的取值口径：**大于** `capture + resolve + engineHard + 余量`，
/// 否则会在流程还在正常推进时把它掐掉（用户看到的是"读屏无响应"，其实它快好了）。
class QuizVisionTimeouts {
  QuizVisionTimeouts._();

  /// 原生侧截图看门狗（Kotlin `QuizAccessibilityService.CAPTURE_WATCHDOG_MS`）。
  ///
  /// 必须**小于** [capture]：让原生先自己收尾（回 null），Dart 侧的超时只做兜底。
  /// 改这里必须同步改 Kotlin 那个常量 —— 跨语言没法共享，靠单测读源码核对。
  static const Duration kotlinCaptureWatchdog = Duration(seconds: 6);

  /// 单次截图等待上限（本地平台通道）。
  static const Duration capture = Duration(seconds: 8);

  /// 读凭证上限：本机存储（Keystore / SharedPreferences）+ 匿名设备令牌签发。
  static const Duration resolve = Duration(seconds: 10);

  /// 引擎自身总时长硬顶（含重试与退避）。
  static const Duration engineHard = Duration(seconds: 45);

  /// 普通 HTTP 请求上限（用户自填的外部题库接口）。
  static const Duration httpRequest = Duration(seconds: 10);

  /// 内置外部题库（带浏览器 UA 的那条）请求上限。
  static const Duration externalBankHttp = Duration(seconds: 8);

  /// 普通平台通道调用上限：悬浮窗显隐/内容更新、权限查询、批处理开关等。
  static const Duration channel = Duration(seconds: 5);

  /// 用户交互类通道：原生框选区域（等用户拖拽），**不能**用短超时。
  static const Duration userInteraction = Duration(minutes: 5);

  /// 整条读屏流程的兜底：与具体实现无关的最后一道网。
  ///
  /// 点 AI 后无论内部卡在哪一步，流程都会在这个时限内结束（并把卡住的阶段写进
  /// 用户能看到的提示）。见 `quiz_plugin_entry.visionPhase` / `visionFlowTimeout`。
  static const Duration flow = Duration(seconds: 75);
}
