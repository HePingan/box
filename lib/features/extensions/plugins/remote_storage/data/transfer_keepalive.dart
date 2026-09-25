// 传输期间的前台保活（284 P1）。
//
// 为什么需要：Flutter 的 IO 任务不能阻止系统回收进程，app 一退到后台/被切掉，
// 排队中的上传下载就断了。做法是传输入队期间起一个前台服务（通知栏常驻），
// 系统就不会回收 —— 仓库里视频下载已有同样的模式（VideoDownloadService）。
//
// 非 Android / 原生没注册 → [MissingPluginException] → 全部静默降级（不影响传输本身）。

import 'dart:async';

import 'package:box/utils/app_logger.dart';
import 'package:box/utils/log_channels.dart';
import 'package:flutter/services.dart';

class TransferKeepAlive {
  TransferKeepAlive({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName =
      'top.hpa888.box/remote_storage_transfer_service';

  final MethodChannel _channel;

  /// 起前台服务（幂等：原生侧重复调用只更新通知）。
  Future<void> start({required String title, required String text}) =>
      _invoke('start', {'title': title, 'text': text});

  /// 更新通知文案（进度）。
  Future<void> update({required String text}) =>
      _invoke('update', {'text': text});

  /// 收工，撤掉通知。
  Future<void> stop() => _invoke('stop', const {});

  Future<void> _invoke(String method, Map<String, Object?> args) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // 非 Android 或没注册：不影响传输。
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '前台保活 $method 失败: $e',
        level: LogLevel.debug,
      );
    }
  }
}
