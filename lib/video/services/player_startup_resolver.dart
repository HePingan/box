import 'dart:async';

import '../../utils/app_logger.dart';
import '../utils/play_url_policy.dart';
import '../widgets/player/player_stream_resolver.dart';
import 'cloud_play_url_resolver.dart';
import 'stream_resolve_cache.dart';

/// 云播页归一化之后仍然不是媒体流 —— 重试还是网页，属于「无需再试」的失败。
class UnresolvedCloudPageException implements Exception {
  const UnresolvedCloudPageException();

  @override
  String toString() => '该线路是网页线路';
}

/// 起播链的统一入口：**云播页归一化 → 直连 m3u8 解析**，带缓存与预热。
///
/// 抽出来的两个理由（2026-10-03）：
///   1. 同一段链原来在播放容器里串两遍（详情页预热、播放器起播各一次），
///      缓存与「在途合并」只有集中在一处才对两处都生效；
///   2. 超时口径要统一：实测正常线路 146ms~1.9s，而一条不可达线路会一直等到
///      上限（原先单次探测 5s、整段 12s）。封顶值放在这里，一处可调、可测。
class PlayerStartupResolver {
  PlayerStartupResolver({
    CloudPlayUrlResolver cloud = const CloudPlayUrlResolver(),
    PlayerStreamResolver stream = const PlayerStreamResolver(),
    StreamResolveCache? cache,
    this.cloudTimeout = const Duration(seconds: 6),
    this.streamTimeout = const Duration(seconds: 5),
  })  : _cloud = cloud,
        _stream = stream,
        cache = cache ?? StreamResolveCache();

  /// 进程级共享实例：详情页预热写进去、播放器起播读出来。
  static PlayerStartupResolver instance = PlayerStartupResolver();

  final CloudPlayUrlResolver _cloud;
  final PlayerStreamResolver _stream;
  final StreamResolveCache cache;

  /// 云播页归一化整段的上限（内部要串几次探测）。
  final Duration cloudTimeout;

  /// 直连 m3u8 解析的上限。
  final Duration streamTimeout;

  /// 缓存键：同一个地址在不同 Referer 下可能解析出不同结果（有些源按 Referer 签名），
  /// 所以把 Referer 也编进键里，避免「预热用 A 源的头、播放用 B 源的头」互相污染。
  String keyFor(Uri raw, Map<String, String> headers) =>
      '${raw.toString()}|${headers['Referer'] ?? ''}';

  String debugKey(Uri raw, Map<String, String> headers) => keyFor(raw, headers);

  Future<Uri> resolve(
    Uri raw, {
    required Map<String, String> headers,
    bool force = false,
  }) {
    return cache.resolve(keyFor(raw, headers), () async {
      final media = await _cloud.resolve(raw, headers: headers).timeout(cloudTimeout);
      // 归一化后仍是网页地址：明确判死，绝不把 HTML 丢给播放器。
      if (PlayUrlPolicy.isCloudPage(media)) {
        throw const UnresolvedCloudPageException();
      }
      return _stream.resolveDirectM3u8(media, headers: headers).timeout(streamTimeout);
    }, force: force);
  }

  /// 已经解析过（缓存里有）就不要重复请求。
  bool isWarm(Uri raw, Map<String, String> headers) =>
      cache.peek(keyFor(raw, headers)) != null;

  /// 预热：不阻塞调用方、不抛错。写给「下一集」与「用户正在挑集数」用。
  void prewarm(Uri raw, {required Map<String, String> headers}) {
    if (isWarm(raw, headers)) return;
    unawaited(
      resolve(raw, headers: headers).then<void>(
        (_) {},
        onError: (Object e, StackTrace st) {
          AppLogger.instance.log('预热失败（不影响播放）：${e.runtimeType}', tag: 'PLAYER');
        },
      ),
    );
  }

  /// 播放失败后把这条地址的结果踢掉，免得重试时又拿到同一个坏地址。
  void invalidate(Uri raw, Map<String, String> headers) =>
      cache.invalidate(keyFor(raw, headers));
}
