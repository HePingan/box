import 'dart:convert';
import 'dart:io';

import 'video_category.dart';
import 'video_source.dart';
import 'vod_item.dart';
import '../services/video_api_service.dart';
import '../../utils/app_logger.dart';

/// 单个视频源的健康检测结果
class SourceCheckResult {
  final VideoSource source;
  final bool success;
  final String stage;
  final String message;
  final String? playableUrl;
  final int categoryCount;
  final int videoCount;
  final DateTime checkedAt;

  const SourceCheckResult({
    required this.source,
    required this.success,
    required this.stage,
    required this.message,
    required this.checkedAt,
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
  static const String _logTag = 'SOURCE_HEALTH';

  final Duration timeout;
  final int maxConcurrent;

  const SourceHealthService({
    this.timeout = const Duration(seconds: 8),
    this.maxConcurrent = 3,
  });

  void _log(String message) {
    AppLogger.instance.log(message, tag: _logTag);
  }

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
      final end = (i + maxConcurrent) > candidates.length ? candidates.length : (i + maxConcurrent);
      final batch = candidates.sublist(i, end);

      final batchResults = await Future.wait(batch.map((source) => _checkOne(source)));

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
      return SourceCheckResult(source: source, success: false, stage: 'source', message: '源地址为空', checkedAt: now);
    }

    try {
      final categories = await _fetchCategories(source);
      if (categories.isEmpty) {
        return SourceCheckResult(source: source, success: false, stage: 'categories', message: '分类为空', checkedAt: now);
      }

      final videos = await _fetchVideoList(source, categories.first);
      if (videos.isEmpty) {
        return SourceCheckResult(source: source, success: false, stage: 'list', message: '视频列表为空', categoryCount: categories.length, checkedAt: now);
      }

      final detailBaseUrl = source.detailUrl.trim().isNotEmpty ? source.detailUrl.trim() : source.url.trim();
      final detail = await _fetchDetail(detailBaseUrl, videos.first);
      if (detail == null) {
        return SourceCheckResult(source: source, success: false, stage: 'detail', message: '详情为空', categoryCount: categories.length, videoCount: videos.length, checkedAt: now);
      }

      final playableUrl = _extractPlayableUrl(detail, source);
      if (playableUrl == null || playableUrl.trim().isEmpty) {
        return SourceCheckResult(source: source, success: false, stage: 'detail', message: '未解析到播放地址', categoryCount: categories.length, videoCount: videos.length, checkedAt: now);
      }

      final playable = await _probePlayableUrl(playableUrl, baseUrl: detailBaseUrl, headers: _buildHeaders(source));

      if (!playable) {
        return SourceCheckResult(source: source, success: false, stage: 'play', message: '播放地址不可用', playableUrl: playableUrl, categoryCount: categories.length, videoCount: videos.length, checkedAt: now);
      }

      return SourceCheckResult(source: source, success: true, stage: 'ok', message: '可用', playableUrl: playableUrl, categoryCount: categories.length, videoCount: videos.length, checkedAt: now);
    } catch (e) {
      return SourceCheckResult(source: source, success: false, stage: 'exception', message: e.toString(), checkedAt: now);
    }
  }

  Future<List<VideoCategory>> _fetchCategories(VideoSource source) async {
    return await VideoApiService.fetchCategories(source.url).timeout(timeout);
  }

  Future<List<VodItem>> _fetchVideoList(VideoSource source, VideoCategory category) async {
    return await VideoApiService.fetchVideoList(baseUrl: source.url, page: 1, typeId: category.typeId,).timeout(timeout);
  }

  Future<dynamic> _fetchDetail(String detailBaseUrl, VodItem item) async {
    return await VideoApiService.fetchDetail(detailBaseUrl, item.vodId).timeout(timeout);
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
      final regex = RegExp(r'https?:\/\/[^"\s\\]+\.(?:m3u8|mp4)', caseSensitive: false);
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

    final urlRegex = RegExp(r'''(https?:\/\/[^\s#\$"'<>\\]+|\/\/[^\s#\$"'<>\\]+)''', caseSensitive: false);
    final match = urlRegex.firstMatch(input);
    if (match != null) {
      var url = match.group(0)!.trim();
      return url.startsWith('//') ? 'https:$url' : url;
    }

    if (input.startsWith('/') || input.startsWith('./') || input.startsWith('../')) {
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
      'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Flutter) AppleWebKit/537.36 Chrome/122.0 Mobile',
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

  Future<bool> _probePlayableUrl(String rawUrl, {required String baseUrl, required Map<String, String> headers}) async {
    final url = _normalizeUrl(rawUrl, baseUrl);
    if (url == null || url.trim().isEmpty) return false;

    final isM3u8 = url.toLowerCase().contains('.m3u8');
    final client = HttpClient()..connectionTimeout = timeout..idleTimeout = timeout;

    try {
      final uri = Uri.parse(url);
      
      try {
        final headReq = await client.headUrl(uri);
        headers.forEach((k, v) => headReq.headers.set(k, v));
        final headResp = await headReq.close().timeout(timeout);
        
        if (headResp.statusCode >= 200 && headResp.statusCode < 400 && !isM3u8) {
          return true;
        }
      } catch (_) {}

      final getReq = await client.getUrl(uri);
      headers.forEach((k, v) => getReq.headers.set(k, v));
      if (!isM3u8) getReq.headers.set('Range', 'bytes=0-1023');

      final resp = await getReq.close().timeout(timeout);
      if (resp.statusCode < 200 || resp.statusCode >= 400) return false;
      if (!isM3u8) return true;

      final body = await utf8.decodeStream(resp);
      return body.contains('#EXTM3U') || body.contains('#EXT-X');
      
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
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
        case 'vodPlayUrl': return item.vodPlayUrl;
        case 'vod_play_url': return item.vodPlayUrl;
        case 'playUrl': return item.playUrl;
        case 'play_url': return item.playUrl;
        default: return null;
      }
    } catch (_) {
      return null;
    }
  }
}