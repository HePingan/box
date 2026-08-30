import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../account/domain/account_models.dart';
import '../domain/cloud_sync_models.dart';

/// 云端书源 / 公告的只读客户端。
///
/// 这两个接口都是公开的（不需要登录），所以不传 token —— 保持匿名用户也能收到
/// 公告和书源更新。管理端写操作走 [CloudSyncAdminClient]。
class CloudSyncClient {
  CloudSyncClient({http.Client? httpClient, String? serverUrl})
      : _http = httpClient ?? http.Client(),
        _serverUrl = BoxAccountDefaults.normalizeServerUrl(serverUrl ?? '');

  final http.Client _http;
  final String _serverUrl;

  static const Duration _timeout = Duration(seconds: 12);

  /// 拉云端书源。
  ///
  /// [since] 传本地已持有的版本号，服务端若判定无变化则 changed=false 且不下发
  /// sources，省流量。传 null 表示强制要全量。
  Future<CloudBookSourceBundle> fetchBookSources({int? since}) async {
    final query = since == null ? null : <String, String>{'since': '$since'};
    final body = await _get('/api/book-sources', query);
    return CloudBookSourceBundle.fromJson(body);
  }

  Future<List<AnnouncementEntry>> fetchAnnouncements({int limit = 50}) async {
    final body = await _get('/api/announcements', {
      'limit': '${limit.clamp(1, 200)}',
    });
    final items = body['announcements'];
    if (items is! List) return const <AnnouncementEntry>[];
    return items
        .whereType<Map>()
        .map((e) => AnnouncementEntry.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String>? query,
  ]) async {
    final base = _serverUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base$path').replace(
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
    final response = await _http.get(uri).timeout(_timeout);
    if (response.statusCode != 200) {
      throw CloudSyncException(
        '请求失败 HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const CloudSyncException('响应格式异常');
      }
      return decoded;
    } on CloudSyncException {
      rethrow;
    } catch (e) {
      throw CloudSyncException('响应解析失败：$e');
    }
  }

  void close() => _http.close();
}

/// 管理端写操作（发布书源、增删改公告）。需要管理员会话 token。
class CloudSyncAdminClient {
  CloudSyncAdminClient({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;
  static const Duration _timeout = Duration(seconds: 20);

  /// 发布书源到云端。
  ///
  /// [mode] 'merge' 只增改，'replace' 会把本次未提交的既有云端书源转为墓碑
  /// （客户端同步时会删除本地对应条目），破坏性更强，调用方需二次确认。
  Future<Map<String, dynamic>> publishBookSources({
    required String serverUrl,
    required String token,
    required List<Map<String, dynamic>> sources,
    String mode = 'merge',
    bool announce = true,
    String? announcementTitle,
    String? announcementBody,
  }) {
    return _send('POST', serverUrl, token, '/admin/book-sources/publish', {
      'sources': sources,
      'mode': mode,
      'announce': announce,
      if (announcementTitle != null && announcementTitle.trim().isNotEmpty)
        'announcementTitle': announcementTitle.trim(),
      if (announcementBody != null && announcementBody.trim().isNotEmpty)
        'announcementBody': announcementBody.trim(),
    });
  }

  Future<Map<String, dynamic>> listCloudBookSources({
    required String serverUrl,
    required String token,
  }) {
    return _send('GET', serverUrl, token, '/admin/book-sources', null);
  }

  Future<Map<String, dynamic>> deleteCloudBookSource({
    required String serverUrl,
    required String token,
    required String id,
  }) {
    return _send(
      'DELETE',
      serverUrl,
      token,
      '/admin/book-sources/${Uri.encodeComponent(id)}',
      null,
    );
  }

  Future<Map<String, dynamic>> listAnnouncements({
    required String serverUrl,
    required String token,
  }) {
    return _send('GET', serverUrl, token, '/admin/announcements', null);
  }

  Future<Map<String, dynamic>> createAnnouncement({
    required String serverUrl,
    required String token,
    required String title,
    required String body,
    String level = 'info',
    bool pinned = false,
    String linkUrl = '',
    bool published = true,
  }) {
    return _send('POST', serverUrl, token, '/admin/announcements', {
      'title': title,
      'body': body,
      'level': level,
      'pinned': pinned,
      'linkUrl': linkUrl,
      'published': published,
    });
  }

  Future<Map<String, dynamic>> updateAnnouncement({
    required String serverUrl,
    required String token,
    required String id,
    Map<String, dynamic> patch = const {},
  }) {
    return _send(
      'PATCH',
      serverUrl,
      token,
      '/admin/announcements/${Uri.encodeComponent(id)}',
      patch,
    );
  }

  Future<Map<String, dynamic>> deleteAnnouncement({
    required String serverUrl,
    required String token,
    required String id,
  }) {
    return _send(
      'DELETE',
      serverUrl,
      token,
      '/admin/announcements/${Uri.encodeComponent(id)}',
      null,
    );
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String serverUrl,
    String token,
    String path,
    Map<String, dynamic>? body,
  ) async {
    final base = BoxAccountDefaults.normalizeServerUrl(
      serverUrl,
    ).replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base$path');
    final request = http.Request(method, uri)
      ..headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }
    final streamed = await _http.send(request).timeout(_timeout);
    final response = await http.Response.fromStream(streamed);
    Map<String, dynamic>? decoded;
    try {
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is Map<String, dynamic>) decoded = value;
    } catch (_) {
      // 保持 decoded 为 null，下面按状态码报错
    }
    if (response.statusCode != 200) {
      final error = decoded?['error'];
      final message = error is Map ? error['message']?.toString() : null;
      throw CloudSyncException(
        message?.isNotEmpty == true
            ? message!
            : '请求失败 HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    return decoded ?? <String, dynamic>{};
  }

  void close() => _http.close();
}

class CloudSyncException implements Exception {
  const CloudSyncException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}
