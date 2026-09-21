import 'package:flutter/services.dart';

/// AI 作答过程推送桥。
///
/// 用户 2026-09-13 第五次反馈「ai回答时在答题悬浮窗下面显示作答过程」。
///
/// 设计说明（为什么不直接在 data 层调 presentation 的 QuizPluginEntry）：
///   data 层（quiz_engine.dart）不能反向 import presentation 层，否则形成
///   分层环依赖。这里放一个**极薄的 utils 桥**，只负责把文本发到原生答题
///   悬浮窗，data 与 presentation 都可以依赖 utils，不产生环。
///
/// 失败静默：无障碍服务未运行 / 悬浮窗未显示时推送无接收方，属正常情况，
/// 不应打断搜题主流程。
class AiProcessBridge {
  AiProcessBridge._();

  static const MethodChannel _channel =
      MethodChannel('top.hpa888.box/quiz_plugin');

  /// 推送过程文本；传空串表示清空并隐藏该区块。
  static Future<void> push(String text) async {
    try {
      await _channel.invokeMethod('updateAiProcess', {'text': text});
    } catch (_) {
      // 原生侧未就绪时忽略：过程展示是增强功能，不能影响出答案。
    }
  }

  /// 清空过程区块（本地题库命中 / 非 AI 作答时调用）。
  static Future<void> clear() => push('');
}
