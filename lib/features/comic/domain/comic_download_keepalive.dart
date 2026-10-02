// 漫画离线下载期间的前台保活 + 下完的通知（2026-10-02）。
//
// 为什么需要：下载是 Dart 侧的任务，**拦不住系统回收进程** —— app 一退到后台、内存吃紧
// 就会被回收，队列直接断掉（用户回来只看到进度不动了）。做法是下载期间挂一个前台服务
// （通知栏常驻），系统就不会随便杀这个进程。仓库里视频下载、远端存储传输都是同一个模式。
//
// 为什么下完要**留**一条通知、而不是像传输那样撤掉：用户切走了，唯一能知道他下完了的
// 办法就是这条通知（这也是他提"系统通知 + 切后台继续下载"的原始诉求）。
//
// 非 Android / 原生没注册 → [MissingPluginException] → 全部静默降级（不影响下载本身）。
library;

import 'package:box/utils/app_logger.dart';
import 'package:box/utils/log_channels.dart';
import 'package:flutter/services.dart';

class ComicDownloadKeepAlive {
  ComicDownloadKeepAlive({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'top.hpa888.box/comic_download_service';

  final MethodChannel _channel;

  /// 起前台服务（幂等：原生侧重复调用只更新通知）。
  Future<void> start({required String title, required String text}) =>
      _invoke('start', {'title': title, 'text': text});

  /// 更新通知文案（进度）。
  Future<void> update({required String text}) =>
      _invoke('update', {'text': text});

  /// 下完收工，**留一条可划掉的通知**（"下载完成 / 有 N 话失败"）。
  Future<void> finish({required String title, required String text}) =>
      _invoke('finish', {'title': title, 'text': text});

  /// 收工并撤掉通知（用户暂停/取消：不用告诉他"完成"）。
  Future<void> stop() => _invoke('stop', const {});

  Future<void> _invoke(String method, Map<String, Object?> args) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // 非 Android 或没注册：不影响下载。
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.system,
        '漫画下载保活 $method 失败: $e',
        level: LogLevel.debug,
      );
    }
  }
}
