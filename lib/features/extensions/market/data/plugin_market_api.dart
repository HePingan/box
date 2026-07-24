import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../account/data/account_store.dart';
import '../../../account/domain/account_models.dart';

/// 远端插件市场 API（投稿 / 我的 / 商店清单 / 管理审核）。
class PluginMarketApi {
  PluginMarketApi({
    http.Client? httpClient,
    Future<BoxAccountSession?> Function()? loadSession,
  })  : _http = httpClient ?? http.Client(),
        _loadSession = loadSession ?? BoxAccountStore().loadSession;

  final http.Client _http;
  final Future<BoxAccountSession?> Function() _loadSession;

  Future<Uri> _uri(String path, [Map<String, String>? query]) async {
    final session = await _loadSession();
    final base = BoxAccountDefaults.normalizeServerUrl(
      session?.serverUrl ?? BoxAccountDefaults.serverUrl,
    );
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Future<Map<String, String>> _headers({
    bool auth = true,
    bool json = true,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
    };
    if (json) {
      headers['Content-Type'] = 'application/json; charset=utf-8';
    }
    if (auth) {
      final session = await _loadSession();
      final token = session?.token.trim() ?? '';
      if (token.isEmpty) {
        throw const PluginMarketApiException('请先登录账号');
      }
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<Map<String, dynamic>> _decode(http.Response resp) async {
    Map<String, dynamic> body = const {};
    try {
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        body = decoded;
      } else if (decoded is Map) {
        body = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    if (resp.statusCode >= 200 && resp.statusCode < 300) return body;
    final err = body['error'] is Map
        ? Map<String, dynamic>.from(body['error'] as Map)
        : <String, dynamic>{};
    final msg = (err['message']?.toString().isNotEmpty == true)
        ? err['message'].toString()
        : (body['message']?.toString().isNotEmpty == true
            ? body['message'].toString()
            : '请求失败 HTTP ${resp.statusCode}');
    throw PluginMarketApiException(
      msg,
      statusCode: resp.statusCode,
      code: err['code']?.toString(),
      details: body,
    );
  }

  /// 公共商店清单（可匿名）。
  Future<PluginMarketRemoteManifest> fetchMarket({
    String channel = 'stable',
  }) async {
    final uri = await _uri('/api/plugin-market', {'channel': channel});
    final resp = await _http
        .get(uri, headers: await _headers(auth: false))
        .timeout(const Duration(seconds: 15));
    final body = await _decode(resp);
    return PluginMarketRemoteManifest.fromJson(body);
  }

  /// 用户投稿配置型插件（JSON）。
  Future<PluginSubmissionDto> submit(Map<String, dynamic> payload) async {
    final uri = await _uri('/api/plugins/submissions');
    final resp = await _http
        .post(
          uri,
          headers: await _headers(),
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 20));
    final body = await _decode(resp);
    return PluginSubmissionDto.fromJson(body);
  }

  /// 上传 zip 包投稿（multipart，失败回退 packageBase64）。
  Future<PluginSubmissionDto> submitZip({
    required List<int> zipBytes,
    String fileName = 'plugin.zip',
    Map<String, String> fields = const {},
  }) async {
    final uri = await _uri('/api/plugins/submissions/zip');
    try {
      final request = http.MultipartRequest('POST', uri);
      final headers = await _headers(auth: true, json: false);
      request.headers.addAll(headers);
      fields.forEach((k, v) {
        if (v.trim().isNotEmpty) request.fields[k] = v;
      });
      request.files.add(
        http.MultipartFile.fromBytes(
          'package',
          zipBytes,
          filename: fileName,
        ),
      );
      final streamed =
          await request.send().timeout(const Duration(seconds: 45));
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return PluginSubmissionDto.fromJson(await _decode(resp));
      }
    } catch (_) {
      // fall through to base64
    }
    final fallback = await _http
        .post(
          uri,
          headers: await _headers(),
          body: jsonEncode({
            ...fields,
            'packageBase64': base64Encode(zipBytes),
          }),
        )
        .timeout(const Duration(seconds: 45));
    final body = await _decode(fallback);
    return PluginSubmissionDto.fromJson(body);
  }

  /// 下载已发布插件包（zip 或 json 快照），支持进度回调与 1 次自动重试。
  Future<PluginPackageDownload> downloadPackage(
    String pluginId, {
    void Function(int receivedBytes, int totalBytes)? onProgress,
    int retries = 1,
  }) async {
    final uri = await _uri(
      '/api/plugin-market/${Uri.encodeComponent(pluginId)}/package',
    );
    PluginMarketApiException? lastErr;
    for (var attempt = 0; attempt <= retries; attempt++) {
      if (attempt > 0 && onProgress != null) {
        onProgress(0, 0);
      }
      try {
        final resp = await _http.get(
          uri,
          headers: await _headers(auth: false, json: false),
        ).timeout(const Duration(seconds: 30));
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          final total = resp.contentLength ?? 0;
          final bytes = resp.bodyBytes;
          if (onProgress != null) {
            onProgress(bytes.length, total);
          }
          return PluginPackageDownload(
            bytes: bytes,
            sha256: resp.headers['x-package-sha256'] ?? '',
            format: resp.headers['x-package-format'] ?? 'zip',
          );
        }
        Map<String, dynamic> body = const {};
        try {
          final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
          if (decoded is Map) body = Map<String, dynamic>.from(decoded);
        } catch (_) {}
        final msg = body['error'] is Map
            ? (body['error'] as Map)['message']?.toString()
            : null;
        lastErr = PluginMarketApiException(
          msg?.isNotEmpty == true ? msg! : '下载失败 HTTP ${resp.statusCode}',
          statusCode: resp.statusCode,
        );
      } catch (e) {
        lastErr = PluginMarketApiException(_err(e));
      }
      if (attempt < retries) {
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
    throw lastErr ?? const PluginMarketApiException('下载失败');
  }

  static String _err(Object e) {
    if (e is TimeoutException) return '下载超时，请检查网络后重试';
    if (e is SocketException) return '网络连接失败，请重试';
    if (e is PluginMarketApiException) return e.friendlyMessage;
    return '下载失败：${e.toString()}';
  }

  Future<List<PluginSubmissionDto>> listMine() async {
    final uri = await _uri('/api/plugins/mine');
    final resp = await _http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));
    final body = await _decode(resp);
    final items = body['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((e) => PluginSubmissionDto.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<AdminPluginQueue> adminList({String? status}) async {
    final query = <String, String>{};
    if (status != null && status.trim().isNotEmpty) {
      query['status'] = status.trim();
    }
    final uri =
        await _uri('/admin/plugins/submissions', query.isEmpty ? null : query);
    final resp = await _http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));
    final body = await _decode(resp);
    return AdminPluginQueue.fromJson(body);
  }

  Future<Map<String, dynamic>> adminReview({
    required String submissionId,
    required bool approve,
    String note = '',
    bool featured = false,
  }) async {
    final action = approve ? 'approve' : 'reject';
    final uri = await _uri('/admin/plugins/submissions/$submissionId/$action');
    final resp = await _http
        .post(
          uri,
          headers: await _headers(),
          body: jsonEncode({
            'note': note,
            if (approve) 'featured': featured,
          }),
        )
        .timeout(const Duration(seconds: 20));
    return _decode(resp);
  }

  /// A1 批量审核：一次性通过/拒绝多个投稿，统一 note。
  Future<Map<String, dynamic>> adminBulkReview({
    required List<String> ids,
    required bool approve,
    String note = '',
    bool featured = false,
  }) async {
    final uri = await _uri('/admin/plugins/submissions/bulk-review');
    final resp = await _http
        .post(
          uri,
          headers: await _headers(),
          body: jsonEncode({
            'action': approve ? 'approve' : 'reject',
            'ids': ids,
            'note': note,
            if (approve) 'featured': featured,
          }),
        )
        .timeout(const Duration(seconds: 30));
    return _decode(resp);
  }

  Future<Map<String, dynamic>> adminYank(
    String pluginId, {
    String note = '',
    bool forceUninstall = false,
  }) async {
    final uri =
        await _uri('/admin/plugins/${Uri.encodeComponent(pluginId)}/yank');
    final resp = await _http
        .post(
          uri,
          headers: await _headers(),
          body: jsonEncode({
            'note': note,
            'forceUninstall': forceUninstall,
          }),
        )
        .timeout(const Duration(seconds: 15));
    return _decode(resp);
  }

  Future<Map<String, dynamic>> adminPreview(String submissionId) async {
    final uri =
        await _uri('/admin/plugins/submissions/$submissionId/preview');
    final resp = await _http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 20));
    return _decode(resp);
  }

  Future<Map<String, dynamic>> reportPlugin(
    String pluginId, {
    required String reason,
  }) async {
    final uri = await _uri(
      '/api/plugin-market/${Uri.encodeComponent(pluginId)}/report',
    );
    final resp = await _http
        .post(
          uri,
          headers: await _headers(),
          body: jsonEncode({'reason': reason}),
        )
        .timeout(const Duration(seconds: 15));
    return _decode(resp);
  }

  Future<Map<String, dynamic>> adminBanAuthor(
    String userId, {
    required bool ban,
    String note = '',
  }) async {
    final action = ban ? 'ban' : 'unban';
    final uri = await _uri(
      '/admin/plugins/authors/${Uri.encodeComponent(userId)}/$action',
    );
    final resp = await _http
        .post(
          uri,
          headers: await _headers(),
          body: jsonEncode({'note': note}),
        )
        .timeout(const Duration(seconds: 15));
    return _decode(resp);
  }

  Future<List<Map<String, dynamic>>> adminListReports({
    String? status,
  }) async {
    final query = <String, String>{};
    if (status != null && status.trim().isNotEmpty) {
      query['status'] = status.trim();
    }
    final uri =
        await _uri('/admin/plugins/reports', query.isEmpty ? null : query);
    final resp = await _http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));
    final body = await _decode(resp);
    final items = body['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> adminStats() async {
    final uri = await _uri('/admin/plugins/stats');
    final resp = await _http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));
    return _decode(resp);
  }

  Future<Map<String, dynamic>> adminFeature(
    String pluginId, {
    bool featured = true,
  }) async {
    final uri =
        await _uri('/admin/plugins/${Uri.encodeComponent(pluginId)}/feature');
    final resp = await _http
        .post(
          uri,
          headers: await _headers(),
          body: jsonEncode({'featured': featured}),
        )
        .timeout(const Duration(seconds: 15));
    return _decode(resp);
  }

  /// 安装成功后上报下载量，并返回 packageSha256 / packageJson。
  Future<Map<String, dynamic>> reportInstall(String pluginId) async {
    final uri = await _uri(
      '/api/plugin-market/${Uri.encodeComponent(pluginId)}/install',
    );
    final resp = await _http
        .post(uri, headers: await _headers(auth: false), body: '{}')
        .timeout(const Duration(seconds: 15));
    return _decode(resp);
  }

  /// 批量查询已装插件远端状态（published / yanked / unknown）。
  Future<List<Map<String, dynamic>>> fetchStatus(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final uri = await _uri('/api/plugin-market/status');
    final resp = await _http
        .post(
          uri,
          headers: await _headers(auth: false),
          body: jsonEncode({'ids': ids}),
        )
        .timeout(const Duration(seconds: 15));
    final body = await _decode(resp);
    final items = body['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }
}

class PluginPackageDownload {
  const PluginPackageDownload({
    required this.bytes,
    required this.sha256,
    required this.format,
  });
  final List<int> bytes;
  final String sha256;
  final String format;
}

class PluginMarketApiException implements Exception {
  const PluginMarketApiException(
    this.message, {
    this.statusCode,
    this.code,
    this.details = const {},
  });
  final String message;
  final int? statusCode;
  final String? code;
  final Map<String, dynamic> details;

  /// 面向用户的中文说明（含 code 场景补充）。
  String get friendlyMessage {
    switch (code) {
      case 'author_banned':
        return message;
      case 'reject_limit':
        return '拒绝次数过多，已禁止投稿，请联系管理员';
      case 'daily_limit':
        return '今日投稿已达上限（5），请明天再试';
      case 'pending_limit':
        return '待审投稿过多，请等待审核后再提交';
      case 'storage_unwritable':
        return '服务器插件包存储不可写，请联系管理员';
      case 'storage_full':
        return '服务器插件包存储空间不足';
      case 'user_storage_limit':
        return '你的插件包累计已超过 50MB 上限';
      case 'storage_write_fail':
        return '保存 zip 失败，请稍后重试';
      case 'plugin_not_installable':
        return '插件不可安装（未发布或已下架）';
      case 'package_not_found':
      case 'package_empty':
        return '插件包不存在或未发布';
      case 'package_file_missing':
        return '包文件丢失，请联系管理员重新发布';
      default:
        return message;
    }
  }

  @override
  String toString() => friendlyMessage;
}

class PluginMarketRemoteManifest {
  const PluginMarketRemoteManifest({
    required this.version,
    required this.channel,
    required this.plugins,
    required this.updatedAt,
  });

  final int version;
  final String channel;
  final List<Map<String, dynamic>> plugins;
  final DateTime? updatedAt;

  factory PluginMarketRemoteManifest.fromJson(Map<String, dynamic> json) {
    final raw = json['plugins'];
    final list = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) list.add(Map<String, dynamic>.from(item));
      }
    }
    return PluginMarketRemoteManifest(
      version: int.tryParse(json['version']?.toString() ?? '') ?? 1,
      channel: json['channel']?.toString() ?? 'stable',
      plugins: list,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }
}

class PluginSubmissionDto {
  const PluginSubmissionDto({
    required this.id,
    required this.pluginId,
    required this.title,
    required this.subtitle,
    required this.version,
    required this.status,
    required this.actionCode,
    required this.areaCode,
    required this.reviewNote,
    required this.createdAt,
    required this.authorName,
    this.authorUserId = '',
    this.packageFormat = '',
    this.packageSha256 = '',
    this.packageSize = 0,
    this.hasPackage = false,
    this.changelog = '',
  });

  final String id;
  final String pluginId;
  final String title;
  final String subtitle;
  final String version;
  final String status;
  final String actionCode;
  final String areaCode;
  final String reviewNote;
  final DateTime? createdAt;
  final String authorName;
  final String authorUserId;
  final String packageFormat;
  final String packageSha256;
  final int packageSize;
  final bool hasPackage;
  final String changelog;

  factory PluginSubmissionDto.fromJson(Map<String, dynamic> json) {
    return PluginSubmissionDto(
      id: json['id']?.toString() ?? '',
      pluginId: json['pluginId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      version: json['version']?.toString() ?? '1.0.0',
      status: json['status']?.toString() ?? '',
      actionCode: json['actionCode']?.toString() ?? '',
      areaCode: json['areaCode']?.toString() ?? '',
      reviewNote: json['reviewNote']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      authorName: json['authorName']?.toString() ?? '',
      authorUserId: json['authorUserId']?.toString() ?? '',
      packageFormat: json['packageFormat']?.toString() ?? '',
      packageSha256: json['packageSha256']?.toString() ?? '',
      packageSize: int.tryParse(json['packageSize']?.toString() ?? '') ?? 0,
      hasPackage: json['hasPackage'] == true ||
          (json['packagePath']?.toString().isNotEmpty == true) ||
          (json['packageFormat']?.toString() == 'zip'),
      changelog: json['changelog']?.toString() ?? '',
    );
  }

  String get statusLabel {
    switch (status) {
      case 'pending_review':
        return '待审核';
      case 'published':
        return '已发布';
      case 'rejected':
        return '已拒绝';
      case 'draft':
        return '草稿';
      default:
        return status;
    }
  }
}

class AdminPluginQueue {
  const AdminPluginQueue({
    required this.items,
    required this.published,
    required this.pendingCount,
    this.rejectsToday = 0,
    this.audit = const [],
    this.openReports = 0,
    this.bannedAuthors = const {},
    this.storage = const {},
    this.counters = const {},
  });

  final List<PluginSubmissionDto> items;
  final List<Map<String, dynamic>> published;
  final int pendingCount;
  final int rejectsToday;
  final List<Map<String, dynamic>> audit;
  final int openReports;
  final Map<String, String> bannedAuthors;
  final Map<String, dynamic> storage;
  final Map<String, dynamic> counters;

  factory AdminPluginQueue.fromJson(Map<String, dynamic> json) {
    final items = <PluginSubmissionDto>[];
    final rawItems = json['items'];
    if (rawItems is List) {
      for (final item in rawItems.whereType<Map>()) {
        items.add(
          PluginSubmissionDto.fromJson(Map<String, dynamic>.from(item)),
        );
      }
    }
    final published = <Map<String, dynamic>>[];
    final rawPub = json['published'];
    if (rawPub is List) {
      for (final item in rawPub.whereType<Map>()) {
        published.add(Map<String, dynamic>.from(item));
      }
    }
    final audit = <Map<String, dynamic>>[];
    final rawAudit = json['audit'];
    if (rawAudit is List) {
      for (final item in rawAudit.whereType<Map>()) {
        audit.add(Map<String, dynamic>.from(item));
      }
    }
    final banned = <String, String>{};
    final rawBanned = json['bannedAuthors'];
    if (rawBanned is Map) {
      rawBanned.forEach((k, v) {
        banned[k.toString()] = v?.toString() ?? '';
      });
    }
    final storage = json['storage'] is Map
        ? Map<String, dynamic>.from(json['storage'] as Map)
        : <String, dynamic>{};
    final counters = json['counters'] is Map
        ? Map<String, dynamic>.from(json['counters'] as Map)
        : <String, dynamic>{};
    return AdminPluginQueue(
      items: items,
      published: published,
      pendingCount: int.tryParse(json['pendingCount']?.toString() ?? '') ??
          items.where((e) => e.status == 'pending_review').length,
      rejectsToday: int.tryParse(json['rejectsToday']?.toString() ?? '') ?? 0,
      audit: audit,
      openReports: int.tryParse(json['openReports']?.toString() ?? '') ?? 0,
      bannedAuthors: banned,
      storage: storage,
      counters: counters,
    );
  }
}
