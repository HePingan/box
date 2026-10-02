import 'dart:convert';
import 'dart:io';
import '../models/video_category.dart';
import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../utils/play_url_policy.dart';
import '../services/video_api_service.dart';
import 'cloud_play_url_resolver.dart';

/// Real playback-chain stages. The ordered list is safe to render in admin UI.
enum SourceHealthStage {
  source,
  category,
  list,
  detail,
  play,
  exception;

  static const List<SourceHealthStage> ordered = [
    SourceHealthStage.category,
    SourceHealthStage.list,
    SourceHealthStage.detail,
    SourceHealthStage.play,
  ];
}

/// 单个视频源的健康检测结果
class SourceCheckResult {
  final VideoSource source;
  final bool success;
  final SourceHealthStage stage;
  final String message;
  final String? playableUrl;
  final int categoryCount;
  final int videoCount;
  final DateTime checkedAt;
  final Duration elapsed;

  const SourceCheckResult({
    required this.source,
    required this.success,
    required this.stage,
    required this.message,
    required this.checkedAt,
    this.elapsed = Duration.zero,
    this.playableUrl,
    this.categoryCount = 0,
    this.videoCount = 0,
  });

  @override
  String toString() {
    return 'SourceCheckResult('
        'source=${source.name}, '
        'success=$success, '
        'stage=$stage, '
        'message=$message, '
        'playableUrl=$playableUrl, '
        'categoryCount=$categoryCount, '
        'videoCount=$videoCount, '
        'checkedAt=$checkedAt'
        ')';
  }
}

/// 视频源健康检测服务
///
/// 建议后续将此文件移动到 lib/services/ 目录下更为合理
class SourceHealthService {
  final Duration timeout;
  final int maxConcurrent;

  const SourceHealthService({
    this.timeout = const Duration(seconds: 8),
    this.maxConcurrent = 3,
  });

  Future<SourceCheckResult> checkSource(VideoSource source) async {
    return _checkOne(source);
  }

  Future<SourceCheckResult> checkSourceHealth(VideoSource source) async {
    return _checkOne(source);
  }

  Future<List<SourceCheckResult>> scanAll(
    List<VideoSource> sources, {
    bool includeDisabled = false,
    Future<void> Function(SourceCheckResult result)? onEachResult,
  }) async {
    final candidates = sources
        .where((s) => includeDisabled || s.isEnabled == true)
        .where((s) => s.url.trim().isNotEmpty)
        .toList(growable: false);

    if (candidates.isEmpty) return <SourceCheckResult>[];

    final results = <SourceCheckResult>[];

    for (var i = 0; i < candidates.length; i += maxConcurrent) {
      final end = (i + maxConcurrent) > candidates.length
          ? candidates.length
          : (i + maxConcurrent);
      final batch = candidates.sublist(i, end);

      final batchResults = await Future.wait(
        batch.map((source) => _checkOne(source)),
      );

      for (final result in batchResults) {
        results.add(result);
        if (onEachResult != null) {
          await onEachResult(result);
        }
      }
    }

    return results;
  }

  Future<List<SourceCheckResult>> scanSources(
    List<VideoSource> sources, {
    bool includeDisabled = false,
    Future<void> Function(SourceCheckResult result)? onEachResult,
  }) {
    return scanAll(
      sources,
      includeDisabled: includeDisabled,
      onEachResult: onEachResult,
    );
  }

  Future<SourceCheckResult> _checkOne(VideoSource source) async {
    final now = DateTime.now();
    final sourceUrl = source.url.trim();
    if (sourceUrl.isEmpty) {
      return SourceCheckResult(
        source: source,
        success: false,
        stage: SourceHealthStage.source,
        message: '源地址为空',
        checkedAt: now,
        elapsed: DateTime.now().difference(now),
      );
    }

    try {
      final categories = await fetchCategoriesForHealthCheck(source);
      if (categories.isEmpty) {
        return SourceCheckResult(
          source: source,
          success: false,
          stage: SourceHealthStage.category,
          message: '分类为空',
          checkedAt: now,
          elapsed: DateTime.now().difference(now),
        );
      }

      var videos = await _fetchVideoList(source, categories.first, categories);
      // 有些源的首个分类只是展示父类或空壳（如最大/无尽/飘零），
      // 不能因一个空分类把整个源判死。分类请求为空时，用“全部”再验证一次。
      if (videos.isEmpty) {
        videos = await VideoApiService.fetchVideos(source.url, null, 1)
            .timeout(timeout);
      }
      if (videos.isEmpty) {
        return SourceCheckResult(
          source: source,
          success: false,
          stage: SourceHealthStage.list,
          message: '视频列表为空',
          categoryCount: categories.length,
          checkedAt: now,
          elapsed: DateTime.now().difference(now),
        );
      }

      // `url` 是目录给出的真实采集 API；`detailUrl` 通常只是官网/Referer。
      // 详情同样必须 API 优先，否则列表正常的源会被官网的 404/超时误判详情为空。
      final detailCandidates = <String>[
        source.url.trim(),
        source.detailUrl.trim(),
      ].where((url) => url.isNotEmpty).toSet();
      dynamic detail;
      String detailBaseUrl = source.url.trim();
      for (final candidate in detailCandidates) {
        detail = await _fetchDetail(candidate, videos.first);
        if (detail != null) {
          detailBaseUrl = candidate;
          break;
        }
      }
      if (detail == null) {
        return SourceCheckResult(
          source: source,
          success: false,
          stage: SourceHealthStage.detail,
          message: '详情为空',
          categoryCount: categories.length,
          videoCount: videos.length,
          checkedAt: now,
          elapsed: DateTime.now().difference(now),
        );
      }

      final playableUrl = _extractPlayableUrl(detail, source);
      if (playableUrl == null || playableUrl.trim().isEmpty) {
        return SourceCheckResult(
          source: source,
          success: false,
          stage: SourceHealthStage.detail,
          message: '未解析到播放地址',
          categoryCount: categories.length,
          videoCount: videos.length,
          checkedAt: now,
          elapsed: DateTime.now().difference(now),
        );
      }

      // 判定规则（2026-10-02 收紧）：以前只要是「格式合法的绝对播放地址」就判可用，
      // 于是云播页（`/play/<id>`、`/share/<id>`）和指向 HTML 首页的地址全被判成
      // 「可用」，播不了的源永远显示健康。现在的规则分三档：
      //   - 拿到媒体（HLS 清单 / 二进制体）           → 可用；
      //   - 没拿到响应（超时 / 连接被拒 / DNS）        → 仍判可用（保留原判断：
      //     媒体常带非标端口、refer、geo 校验，裸探测会被拒，ExoPlayer 带完整头能播）；
      //   - 服务器答了但答的不是媒体（HTML 页、404）    → 播放阶段失败，如实记录。
      final normalizedPlayable = _normalizeUrl(playableUrl, detailBaseUrl);
      final playableUri = normalizedPlayable == null
          ? null
          : Uri.tryParse(normalizedPlayable);
      final hasValidPlayableUrl = playableUri != null &&
          playableUri.hasScheme &&
          (playableUri.scheme == 'http' || playableUri.scheme == 'https') &&
          playableUri.host.isNotEmpty;

      if (!hasValidPlayableUrl) {
        // 连合法绝对地址都拼不出，才算真的播放地址不可用。
        return SourceCheckResult(
          source: source,
          success: false,
          stage: SourceHealthStage.play,
          message: '播放地址不可用',
          playableUrl: playableUrl,
          categoryCount: categories.length,
          videoCount: videos.length,
          checkedAt: now,
          elapsed: DateTime.now().difference(now),
        );
      }

      // 播放地址形态先过一遍：云播页（`/play/<id>`、`/share/<id>`）要么被
      // 归一化成真流，要么如实记成「网页线路」——以前这两种情况都报「可用」，
      // 于是播不了的源永远显示健康（2026-10-02 定位）。
      final resolvedPlayUrl = await _resolveCloudPageIfNeeded(
        playableUrl,
        baseUrl: detailBaseUrl,
        headers: _buildHeaders(source),
      );

      final resolvedUri = Uri.tryParse(resolvedPlayUrl);
      final isCloudPage = PlayUrlPolicy.isCloudPage(resolvedUri);

      final probeVerdict = isCloudPage
          ? PlayProbeVerdict.answeredButNotMedia
          : await _probePlayableUrlVerdict(
              resolvedPlayUrl,
              baseUrl: detailBaseUrl,
              headers: _buildHeaders(source),
            );

      // 「没拿到响应」不算死：媒体常带非标端口 / refer / geo 校验，裸探测会被拒，
      // 而真正播放时 ExoPlayer 带完整头能播（保留原判断）。但「答了却不是媒体」
      // （HTML 页、404）是能确定的事实，必须如实记成播放阶段失败。
      final canPlay = probeVerdict == PlayProbeVerdict.playable;
      final unknown = probeVerdict == PlayProbeVerdict.unreachable;

      return SourceCheckResult(
        source: source,
        success: canPlay || unknown,
        stage: SourceHealthStage.play,
        message: canPlay
            ? (resolvedPlayUrl == playableUrl ? '可用' : '可用（已从网页线路解析出真流）')
            : unknown
            ? '可用（未探测到响应，实际播放以播放器为准）'
            : isCloudPage
            ? '播放地址是网页线路，需二次解析'
            : '播放地址不是媒体流',
        playableUrl: canPlay ? resolvedPlayUrl : playableUrl,
        categoryCount: categories.length,
        videoCount: videos.length,
        checkedAt: now,
        elapsed: DateTime.now().difference(now),
      );
    } catch (_) {
      return SourceCheckResult(
        source: source,
        success: false,
        stage: SourceHealthStage.exception,
        message: '健康检查请求失败，请稍后重试',
        checkedAt: now,
        elapsed: DateTime.now().difference(now),
      );
    }
  }

  /// Override in tests to provide a deterministic category endpoint.
  Future<List<VideoCategory>> fetchCategoriesForHealthCheck(
    VideoSource source,
  ) {
    return _fetchCategories(source);
  }

  Future<List<VideoCategory>> _fetchCategories(VideoSource source) async {
    return await VideoApiService.fetchCategories(source.url).timeout(timeout);
  }

  Future<List<VodItem>> _fetchVideoList(
    VideoSource source,
    VideoCategory category,
    List<VideoCategory> allCategories,
  ) async {
    // 与业务侧一致：顶级分类(pid=0)常不挂视频，展开成子分类逗号多选，
    // 避免把“视频挂子类”的正常源误报为“列表为空”。
    final typeQuery = _buildTypeQuery(category.typeId, allCategories);
    return await VideoApiService.fetchVideos(
      source.url,
      category.typeId,
      1,
      typeQuery: typeQuery,
    ).timeout(timeout);
  }

  /// 把父分类展开成子分类 ID 逗号多选(如 "6,7,8,9")；叶子分类返回 null。
  String? _buildTypeQuery(int typeId, List<VideoCategory> categories) {
    final children = categories
        .where((c) => c.pid == typeId && c.typeId > 0)
        .map((c) => c.typeId)
        .toList(growable: false);
    if (children.isEmpty) return null;
    return children.join(',');
  }

  Future<dynamic> _fetchDetail(String detailBaseUrl, VodItem item) async {
    return await VideoApiService.fetchDetail(
      detailBaseUrl,
      item.vodId,
    ).timeout(timeout);
  }

  // =====================================================================
  // 💥 终极精简：暴力正则秒杀层层递归，防卡死防 OOM
  // =====================================================================
  String? _extractPlayableUrl(dynamic detail, VideoSource source) {
    if (detail == null) return null;

    // 1. 常规快速匹配
    const preferredKeys = ['vodPlayUrl', 'vod_play_url', 'playUrl', 'play_url'];
    for (final key in preferredKeys) {
      final value = _readDynamicProperty(detail, key);
      if (value is String && value.isNotEmpty) {
        final url = _extractUrlFromText(value, source);
        if (url != null) return url;
      }
    }

    // 2. 兜底扫描：直接将巨型 JSON 转为文本，正则 1 毫秒瞬间扫出直链
    try {
      final jsonStr = jsonEncode(detail);
      // 正则说明：寻找 http 开始，中间不包含双引号或空白，并以 m3u8 或 mp4 结尾的链接
      final regex = RegExp(
        r'https?:\/\/[^"\s\\]+\.(?:m3u8|mp4)',
        caseSensitive: false,
      );
      final match = regex.firstMatch(jsonStr);

      if (match != null) {
        String url = match.group(0)!;
        // JSON 编码时经常把斜杠转义，这里要给它还原回来
        return url.replaceAll(r'\/', '/');
      }
    } catch (_) {}

    return null;
  }

  String? _extractUrlFromText(String text, VideoSource source) {
    var input = text.trim();
    if (input.isEmpty) return null;
    input = input.replaceAll('\\', '');

    final urlRegex = RegExp(
      r'''(https?:\/\/[^\s#\$"'<>\\]+|\/\/[^\s#\$"'<>\\]+)''',
      caseSensitive: false,
    );
    final match = urlRegex.firstMatch(input);
    if (match != null) {
      var url = match.group(0)!.trim();
      return url.startsWith('//') ? 'https:$url' : url;
    }

    if (input.startsWith('/') ||
        input.startsWith('./') ||
        input.startsWith('../')) {
      final resolved = _resolveRelativeUrl(input, source);
      if (resolved != null && resolved.isNotEmpty) return resolved;
    }
    return null;
  }

  String? _resolveRelativeUrl(String rawUrl, VideoSource source) {
    for (final base in [source.detailUrl.trim(), source.url.trim()]) {
      if (base.isEmpty) continue;
      final baseUri = Uri.tryParse(base);
      if (baseUri == null || !baseUri.hasScheme) continue;
      try {
        return baseUri.resolve(rawUrl).toString();
      } catch (_) {}
    }
    return null;
  }

  // =====================================================================
  // 网络探测
  // =====================================================================
  Map<String, String> _buildHeaders(VideoSource source) {
    final referer = source.url.trim();
    return <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13; Flutter) AppleWebKit/537.36 Chrome/122.0 Mobile',
      'Referer': referer,
      'Origin': _originOf(referer),
      'Accept': '*/*',
    };
  }

  String _originOf(String url) {
    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme || !uri.hasAuthority) return url;
      return '${uri.scheme}://${uri.authority}';
    } catch (_) {
      return url;
    }
  }

  /// 探测播放地址并给出判定（见 _checkOne 里的三档规则）。
  Future<PlayProbeVerdict> _probePlayableUrlVerdict(
    String rawUrl, {
    required String baseUrl,
    required Map<String, String> headers,
  }) async {
    final url = _normalizeUrl(rawUrl, baseUrl);
    if (url == null || url.trim().isEmpty) {
      return PlayProbeVerdict.answeredButNotMedia;
    }

    final client = HttpClient()
      ..connectionTimeout = timeout
      ..idleTimeout = timeout;

    try {
      final uri = Uri.parse(url);
      final getReq = await client.getUrl(uri);
      headers.forEach((k, v) => getReq.headers.set(k, v));
      // 只读前 1KB：HLS 清单第一行就是 #EXTM3U，网页开头几十字节也能认出来。
      getReq.headers.set('Range', 'bytes=0-1023');

      final resp = await getReq.close().timeout(timeout);
      final body = await utf8.decodeStream(resp.take(1024));

      String? contentType;
      try {
        contentType = resp.headers.contentType?.mimeType;
      } catch (_) {}

      return PlayUrlPolicy.classifyProbe(
        statusCode: resp.statusCode,
        contentType: contentType,
        body: body,
      );
    } catch (_) {
      // 连不上 = 探测不到，不算「服务器说是网页」。
      return PlayProbeVerdict.unreachable;
    } finally {
      client.close(force: true);
    }
  }

  /// 云播页 → 真流地址（尽力而为：判定不了就原样返回）。
  Future<String> _resolveCloudPageIfNeeded(
    String rawUrl, {
    required String baseUrl,
    required Map<String, String> headers,
  }) async {
    final normalized = _normalizeUrl(rawUrl, baseUrl);
    if (normalized == null || normalized.trim().isEmpty) return rawUrl;

    final uri = Uri.tryParse(normalized);
    if (uri == null || !PlayUrlPolicy.isCloudPage(uri)) return normalized;

    try {
      final resolved = await const CloudPlayUrlResolver().resolve(
        uri,
        headers: headers,
      );
      return resolved.toString();
    } catch (_) {
      return normalized;
    }
  }

  String? _normalizeUrl(String rawUrl, String baseUrl) {
    var url = rawUrl.trim().replaceAll('\\', '');
    if (url.isEmpty) return null;
    if (url.startsWith('//')) return 'https:$url';

    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.hasScheme) return url;

    final baseUri = Uri.tryParse(baseUrl);
    if (baseUri != null && baseUri.hasScheme) {
      try {
        return baseUri.resolve(url).toString();
      } catch (_) {}
    }
    return url;
  }

  dynamic _readDynamicProperty(dynamic item, String key) {
    if (item == null) return null;
    if (item is Map) return item[key];
    try {
      switch (key) {
        case 'vodPlayUrl':
          return item.vodPlayUrl;
        case 'vod_play_url':
          return item.vodPlayUrl;
        case 'playUrl':
          return item.playUrl;
        case 'play_url':
          return item.playUrl;
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }
}
