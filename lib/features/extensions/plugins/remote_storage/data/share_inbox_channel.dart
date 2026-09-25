// 接收系统分享的通道（286 P3）。
//
// 只在 Android 有实现（见 ShareInboxReceiver.kt）。其它平台/测试环境没有这个通道
// → `MissingPluginException` → 当成"没收到分享"，绝不影响其它功能。
//
// 两种取件方式，对应两种启动路径：
//   * 冷启动：Intent 在 Dart handler 挂上之前就到了，原生先攒着 → [takePending]。
//   * 热启动：Dart 已就绪，原生直接 `onSharedFiles` 推过来 → [listen]。
// 冷启动前必须先 [markReady]（告诉原生"handler 挂了、可以推了"），
// 否则冷启动攒下的文件要等下一次 App 重启才被取到（或者推了没人接）。
import 'dart:async';

import 'package:box/features/extensions/plugins/remote_storage/domain/share_inbox_models.dart';
import 'package:box/utils/app_logger.dart';
import 'package:box/utils/log_channels.dart';
import 'package:flutter/services.dart';

class ShareInboxChannel {
  ShareInboxChannel({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'top.hpa888.box/share_inbox';

  final MethodChannel _channel;

  final StreamController<List<SharedInboxFile>> _incoming =
      StreamController<List<SharedInboxFile>>.broadcast();

  /// 热启动时原生推过来的分享文件。
  Stream<List<SharedInboxFile>> get onSharedFiles => _incoming.stream;

  bool _listening = false;

  /// 挂上 handler 并告诉原生"可以推了"。重复调用无副作用。
  Future<void> markReady() async {
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onSharedFiles') {
          final files = SharedInboxFile.parseList(call.arguments);
          if (files.isNotEmpty) _incoming.add(files);
        }
        return null;
      });
    }
    try {
      await _channel.invokeMethod<bool>('ready');
    } on MissingPluginException {
      // 非 Android：没有实现，什么都不做。
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '分享接收通道就绪通知失败: $e',
        level: LogLevel.debug,
      );
    }
  }

  /// 取走冷启动时攒下的分享文件（取完原生侧即清空，不会重复提示）。
  Future<List<SharedInboxFile>> takePending() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('takePending');
      return SharedInboxFile.parseList(raw);
    } on MissingPluginException {
      return const <SharedInboxFile>[];
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '读取分享暂存失败: $e',
        level: LogLevel.debug,
      );
      return const <SharedInboxFile>[];
    }
  }

  Future<void> dispose() async {
    _listening = false;
    _channel.setMethodCallHandler(null);
    await _incoming.close();
  }
}
