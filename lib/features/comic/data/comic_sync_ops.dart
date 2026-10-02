// 漫画收藏/阅读进度同步的接线：把"手机上存的设备令牌 + 主服务端地址"变成
// [ComicSyncService]（2026-10-02，第三批）。
//
// 为什么地址是常量、令牌要挑那一把：
//   * 同步档存在**边缘机 hpa888**（公网入口 `box.hpa888.top` 的 `/opsapi`）——
//     它是最常在线、走到哪都能连的那台；
//   * 所以令牌要 **hpa888 那把**，与"读中转"要的 175 那把**不是同一把**：
//     混用会 401（`comic_online_page.dart` 的 `loadComicRelayToken` 注释里记过）；
//   * 令牌只从加密存储读、只进请求头，绝不落盘/进日志。
//
// 没配令牌 → 返回 null：**这台设备就不同步**，不是错误（页面据此静默跳过）。
import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_api_client.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';

import '../domain/comic_library_store.dart';
import '../domain/comic_online_progress.dart';
import '../domain/comic_sync.dart';

Future<ComicSyncService?> createComicSyncService({
  ComicLibraryStore? libraryStore,
  ComicOnlineProgressStore? progressStore,
  CacheStore? cacheStore,
}) async {
  try {
    final settings = await ServerOpsSettings.load();
    final token = settings.apiTokenFor(ServerOpsSettings.builtInHpa888Id).trim();
    if (token.isEmpty) return null;
    return ComicSyncService(
      api: OpsApiClient(
        baseUrl: ServerOpsSettings.defaultApiUrl,
        token: token,
      ),
      libraryStore: libraryStore,
      progressStore: progressStore,
      cacheStore: cacheStore,
    );
  } catch (_) {
    // 读设置本身失败（存储没起来/没迁移完）：当成"这台设备不同步"，
    // 不要因为同步把漫画页拖起来 —— 同步是顺带做的事。
    return null;
  }
}
