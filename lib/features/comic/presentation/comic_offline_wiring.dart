// 把「仅 Wi-Fi 下载」接到离线下载队列上（App 里在入口处调一次即可）。
//
// 为什么放在这里而不是下载队列里：队列是**纯逻辑**（单测直接跑），
// 而"现在是什么网"要过平台通道（`NetworkStatusChannel`，remote_storage 那套原生实现）。
// 判定立场跟 remote_storage 一致：**拿不准就不拦**（读不到网络类型当"没情报"放行），
// 最坏是让用户在 5G 上多点一次确认，而不是把他晾在"等待 Wi-Fi"。
library;

import 'package:box/features/extensions/plugins/remote_storage/data/network_status_channel.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/network_policy.dart';

import '../domain/comic_offline_downloader.dart';
import '../domain/comic_offline_prefs.dart';

/// 装好网络策略（可重复调用：每次都会重新读一遍设置，用户改了立即生效）。
void wireComicOfflineNetworkGuard(
  ComicOfflineDownloader downloader, {
  ComicOfflinePrefs? prefs,
  NetworkStatusChannel? channel,
}) {
  final p = prefs ?? ComicOfflinePrefs();
  final c = channel ?? NetworkStatusChannel();
  downloader.setNetworkAllowed(() async {
    bool wifiOnly;
    try {
      wifiOnly = await p.wifiOnly();
    } catch (_) {
      wifiOnly = true; // 读不到设置按"省流量"那一档走
    }
    if (!wifiOnly) return true;
    final kind = await c.current();
    if (kind == null) return true; // 没有情报就不拦
    return networkAllowsTransfer(TransferNetworkPolicy.wifiOnly, kind);
  });
}
