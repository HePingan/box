// 视频首帧抽取通道（284 D8）。
//
// 设计约束：
// 1. **只在 Android 有实现**（MediaMetadataRetriever）。其它平台/测试环境没有这个
//    通道 → `MissingPluginException` → 返回 null，界面回退通用图标，绝不影响列表。
// 2. **任何失败都返回 null**：远端不认识认证、服务端不支持 Range、编码不支持、
//    原生侧抛异常……这些都不是"错误"，只是"这张图没有"，列表里不该出现红字。
// 3. 原生侧在工作线程抽取，回到主线程才回 result（Flutter 要求）。

import 'dart:async';

import 'package:box/utils/app_logger.dart';
import 'package:box/utils/log_channels.dart';
import 'package:flutter/services.dart';

class VideoFrameChannel {
  VideoFrameChannel({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName =
      'top.hpa888.box/remote_storage_video_frame';

  final MethodChannel _channel;

  /// 取 [url] 的一帧。返回 null 表示"拿不到"（原因见类注释）。
  ///
  /// [headers] 用于直接带认证（Basic）访问；需要中继/摘要认证的场景由调用方跳过，
  /// 不在这里做二次协商——缩略图不值得为此开一条中继会话。
  Future<Uint8List?> frameAt({
    required String url,
    Map<String, String> headers = const <String, String>{},
    int positionMs = 0,
    int maxWidth = 256,
  }) async {
    if (url.isEmpty) return null;
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('frameAt', {
        'url': url,
        'headers': headers,
        'positionMs': positionMs,
        'maxWidth': maxWidth,
      });
      if (bytes == null || bytes.isEmpty) return null;
      return bytes;
    } on MissingPluginException {
      // 非 Android 或没有注册原生实现：静默降级。
      return null;
    } on PlatformException catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '视频首帧抽取失败（${e.code}）: ${e.message}',
        level: LogLevel.debug,
      );
      return null;
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '视频首帧抽取异常: $e',
        level: LogLevel.debug,
      );
      return null;
    }
  }
}
