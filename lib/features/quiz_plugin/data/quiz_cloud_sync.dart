import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';

import '../../account/data/account_client.dart';
import '../domain/quiz_bank.dart';
import 'quiz_submission_image_payload.dart';

typedef QuizCloudImportItems = Future<int> Function(List<QuizBankItem> items);
typedef QuizCloudDeleteItem = Future<int> Function(String id);

/// 云端正式题库的离线增量同步。
///
/// 同步仅导入云端 published 题；本地 OCR/手工题仍保留在 SQLite，
/// 因此网络失败或云端下架不会影响即时答题。
class QuizCloudSyncService {
  QuizCloudSyncService({
    http.Client? httpClient,
    QuizCloudImportItems? importItems,
    QuizCloudDeleteItem? deleteCloudItem,
  }) : _httpClient = httpClient ?? http.Client(),
       _importItems = importItems ?? _importIntoBank,
       _deleteCloudItem = deleteCloudItem ?? QuizBankStorage.deleteCloudItem;

  static const _cursorPrefix = 'quiz_cloud_cursor_v1';
  static const _syncPageLimit = 100;
  static const _maxSyncPages = 100;
  static const _maxSubmissionPages = 50;
  static const _apiTimeout = Duration(seconds: 15);
  static const _imageTimeout = Duration(seconds: 20);
  static const _maxImageBytes = 5 * 1024 * 1024;
  final http.Client _httpClient;
  final QuizCloudImportItems _importItems;
  final QuizCloudDeleteItem _deleteCloudItem;

  Future<List<QuizCloudCatalog>> fetchCatalogs({
    required String serverUrl,
  }) async {
    final response = await _httpClient
        .get(_uri(serverUrl, '/api/quiz/catalogs'))
        .timeout(_apiTimeout);
    final json = _decode(response);
    final rows = json['catalogs'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => QuizCloudCatalog.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<QuizCloudSyncResult> sync({
    required String serverUrl,
    String category = '',
    bool resetCursor = false,
  }) async {
    final normalizedServer = BoxAccountClient.normalizeServerUrl(serverUrl);
    final prefs = await SharedPreferences.getInstance();
    final key =
        '$_cursorPrefix:${_safeKey(normalizedServer)}:${category.trim()}';
    if (resetCursor) {
      await prefs.remove(key);
    }
    final cursor = prefs.getInt(key) ?? 0;
    var requestCursor = cursor;
    String? pageToken;
    String? afterSequence;
    var inserted = 0;
    var deleted = 0;
    var imagesCached = 0;
    var imageFailures = 0;
    var pages = 0;
    while (pages < _maxSyncPages) {
      final queryParameters = <String, String>{
        'cursor': '$requestCursor',
        'limit': '$_syncPageLimit',
      };
      if (category.trim().isNotEmpty) {
        queryParameters['category'] = category.trim();
      }
      if (pageToken != null) queryParameters['pageToken'] = pageToken;
      if (afterSequence != null) {
        queryParameters['afterSequence'] = afterSequence;
      }
      final response = await _httpClient
          .get(
            _uri(
              normalizedServer,
              '/api/quiz/sync',
            ).replace(queryParameters: queryParameters),
          )
          .timeout(_apiTimeout);
      final body = _decode(response);
      final changes = body['changes'];
      if (changes is List) {
        final incoming = <QuizBankItem>[];
        for (final raw in changes.whereType<Map>()) {
          final change = Map<String, dynamic>.from(raw);
          if (change['operation']?.toString() == 'delete') {
            final id = change['id']?.toString().trim() ?? '';
            if (id.isNotEmpty) deleted += await _deleteCloudItem(id);
            continue;
          }
          final question = change['question'];
          if (question is Map) {
            final rawCategory = (question['category']?.toString() ?? '').trim();
            final item =
                QuizBankItem.fromJson(
                  Map<String, dynamic>.from(question),
                ).copyWith(
                  source: '云端题库',
                  origin: 'cloud',
                  category: rawCategory.isNotEmpty
                      ? rawCategory
                      : category.trim(),
                  syncStatus: QuizSyncStatus.published,
                  clearLastSubmitError: true,
                );
            if (item.question.trim().isNotEmpty) incoming.add(item);
          }
        }
        if (incoming.isNotEmpty) {
          inserted += await _importItems(incoming);
          // 同步时下载题图到本地缓存；失败不阻塞主流程
          final imageStats = await _downloadImageCache(
            incoming,
            serverUrl: normalizedServer,
          );
          imagesCached += imageStats.cached;
          imageFailures += imageStats.failed;
        }
      }
      final nextCursor = _asInt(body['cursor'], requestCursor);
      final nextPageToken = _continuationToken(body);
      final nextAfterSequence = _token(body['afterSequence']);
      pages++;
      if (body['hasMore'] != true) {
        await prefs.setInt(key, nextCursor);
        return QuizCloudSyncResult(
          cursor: nextCursor,
          inserted: inserted,
          cloudDeletes: deleted,
          imagesCached: imagesCached,
          imageFailures: imageFailures,
          pages: pages,
        );
      }
      if (nextPageToken != null && nextPageToken != pageToken) {
        // New paginated API: retain the original sync cursor while the token
        // walks a stable snapshot, so concurrent cloud changes cannot skip a
        // page.
        pageToken = nextPageToken;
        requestCursor = cursor;
        continue;
      }
      if (nextAfterSequence != null && nextAfterSequence != afterSequence) {
        afterSequence = nextAfterSequence;
        requestCursor = cursor;
        continue;
      }
      if (nextCursor > requestCursor) {
        // Compatibility with the pre-pagination endpoint, where `cursor`
        // itself was the continuation marker.
        requestCursor = nextCursor;
        pageToken = null;
        continue;
      }
      // A repeated token/cursor would otherwise retry the same page forever.
      await prefs.setInt(key, nextCursor);
      return QuizCloudSyncResult(
        cursor: nextCursor,
        inserted: inserted,
        cloudDeletes: deleted,
        imagesCached: imagesCached,
        imageFailures: imageFailures,
        pages: pages,
      );
    }
    return QuizCloudSyncResult(
      cursor: cursor,
      inserted: inserted,
      cloudDeletes: deleted,
      imagesCached: imagesCached,
      imageFailures: imageFailures,
      pages: pages,
      reachedPageLimit: true,
    );
  }

  /// 仅扫描本地缺图/远程图项并补缓存，不改游标。
  Future<QuizCloudImageRepairResult> repairImages({
    required String serverUrl,
    int limit = 300,
  }) async {
    final normalizedServer = BoxAccountClient.normalizeServerUrl(serverUrl);
    List<QuizBankItem> all;
    try {
      all = await QuizBankStorage.loadAll();
    } catch (_) {
      all = QuizBankCache.instance.items;
    }
    final targets = all
        .where((e) {
          final image = (e.imageUrl ?? '').trim();
          if (image.isEmpty) return false;
          if (image.startsWith('/') && !image.startsWith('/data/')) return true;
          if (image.startsWith('http://') || image.startsWith('https://')) {
            return true;
          }
          // 本地路径但文件不存在
          if (image.startsWith('/') || image.startsWith('file://')) {
            final path = image.startsWith('file://')
                ? Uri.parse(image).toFilePath()
                : image;
            return !File(path).existsSync();
          }
          return false;
        })
        .take(limit)
        .toList(growable: false);
    if (targets.isEmpty) {
      return const QuizCloudImageRepairResult(scanned: 0, cached: 0, failed: 0);
    }
    final stats = await _downloadImageCache(
      targets,
      serverUrl: normalizedServer,
    );
    return QuizCloudImageRepairResult(
      scanned: targets.length,
      cached: stats.cached,
      failed: stats.failed,
    );
  }

  Future<void> resetCursor({
    required String serverUrl,
    String category = '',
  }) async {
    final normalizedServer = BoxAccountClient.normalizeServerUrl(serverUrl);
    final prefs = await SharedPreferences.getInstance();
    final key =
        '$_cursorPrefix:${_safeKey(normalizedServer)}:${category.trim()}';
    await prefs.remove(key);
  }

  Future<QuizCloudSubmission> submit({
    required String serverUrl,
    required String token,
    required QuizBankItem item,
    String category = '',
  }) async {
    final response = await _httpClient
        .post(
          _uri(serverUrl, '/api/quiz/submissions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          // 图片必须内联成 data URL 再提交：直接发本地路径
          // （/data/user/0/...）审核端取不到像素，只会看到「图片加载失败」。
          body: jsonEncode(
            await QuizSubmissionImagePayload.buildSubmissionJson({
              ...item.toJson(),
              if (category.trim().isNotEmpty) 'category': category.trim(),
            }),
          ),
        )
        .timeout(_apiTimeout);
    return QuizCloudSubmission.fromJson(_decode(response));
  }

  /// 拉取「当前登录账号自己的投稿」及其审核结果。
  ///
  /// 服务端按 token 绑定用户（`GET /api/me/quiz/questions`），
  /// 客户端不传 userId，避免越权读取他人投稿。
  Future<List<QuizCloudSubmission>> fetchMySubmissions({
    required String serverUrl,
    required String token,
    int pageSize = 100,
  }) async {
    final limit = pageSize.clamp(1, 100);
    final all = <QuizCloudSubmission>[];
    var offset = 0;
    for (var page = 0; page < _maxSubmissionPages; page++) {
      final uri = _uri(serverUrl, '/api/me/quiz/questions').replace(
        queryParameters: {
          'status': 'all',
          'offset': '$offset',
          'limit': '$limit',
        },
      );
      final response = await _httpClient
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(_apiTimeout);
      final body = _decode(response);
      final rows = body['questions'] ?? body['submissions'] ?? body['items'];
      if (rows is! List || rows.isEmpty) break;
      all.addAll(
        rows.whereType<Map>().map(
          (row) => QuizCloudSubmission.fromJson(Map<String, dynamic>.from(row)),
        ),
      );
      offset += rows.length;
      if (body['hasMore'] != true) break;
    }
    return List<QuizCloudSubmission>.unmodifiable(all);
  }

  static Uri _uri(String serverUrl, String path) =>
      Uri.parse(BoxAccountClient.normalizeServerUrl(serverUrl)).resolve(path);

  static Map<String, dynamic> _decode(http.Response response) {
    final text = utf8.decode(response.bodyBytes);
    final decoded = text.trim().isEmpty
        ? <String, dynamic>{}
        : jsonDecode(text);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map
          ? (decoded['error'] is Map
                ? decoded['error']['message']
                : decoded['message'])
          : null;
      throw QuizCloudSyncException(
        message?.toString() ?? '题库云端请求失败（${response.statusCode}）',
      );
    }
    if (decoded is! Map) throw const QuizCloudSyncException('题库云端返回格式异常');
    return Map<String, dynamic>.from(decoded);
  }

  static int _asInt(Object? value, int fallback) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
  static String? _continuationToken(Map<String, dynamic> body) {
    final pageToken = _token(body['pageToken']);
    if (pageToken != null) return pageToken;
    final nextCursor = _token(body['nextCursor']);
    return int.tryParse(nextCursor ?? '') == null ? nextCursor : null;
  }

  static String? _token(Object? value) {
    final token = value?.toString().trim();
    return token == null || token.isEmpty ? null : token;
  }

  /// 同步时下载题图到本地缓存目录。
  ///
  /// - 失败不阻塞题干同步
  /// - 已存在同名文件则跳过
  /// - 相对路径 `/api/quiz/images/xxx` 会拼到当前 serverUrl
  Future<({int cached, int failed})> _downloadImageCache(
    List<QuizBankItem> items, {
    String serverUrl = '',
  }) async {
    final targets = items
        .where((e) => (e.imageUrl ?? '').trim().isNotEmpty)
        .toList(growable: false);
    if (targets.isEmpty) return (cached: 0, failed: 0);

    Directory dir;
    try {
      final base = await getApplicationSupportDirectory();
      dir = Directory('${base.path}/quiz_images');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } catch (_) {
      return (cached: 0, failed: targets.length);
    }

    final normalizedServer = serverUrl.trim().isEmpty
        ? ''
        : BoxAccountClient.normalizeServerUrl(serverUrl);

    var cached = 0;
    var failed = 0;
    for (final item in targets) {
      final raw = item.imageUrl!.trim();
      try {
        final uri = _resolveImageUri(raw, normalizedServer);
        if (uri == null) {
          // 已是本地有效路径
          if (raw.startsWith('/data/') ||
              raw.startsWith('/storage/') ||
              raw.startsWith('file://')) {
            final path = raw.startsWith('file://')
                ? Uri.parse(raw).toFilePath()
                : raw;
            if (File(path).existsSync()) {
              cached++;
              continue;
            }
          }
          failed++;
          continue;
        }
        final ext = _guessExt(uri.path);
        final digest = sha256.convert(utf8.encode(uri.toString())).toString();
        final file = File('${dir.path}/$digest$ext');
        if (await file.exists() && await file.length() > 0) {
          // 已缓存：把本地路径回写到 item，便于 UI 优先读本地
          // QuizBankItem 是 immutable，这里仅更新 DB 中的 image 字段。
          await _rewriteLocalImagePath(item, file.path);
          cached++;
          continue;
        }
        final request = http.Request('GET', uri);
        final response = await _httpClient.send(request).timeout(_imageTimeout);
        if (response.statusCode < 200 ||
            response.statusCode >= 300 ||
            !_isAllowedImageContentType(response.headers['content-type'])) {
          failed++;
          continue;
        }
        final declaredLength = int.tryParse(
          response.headers['content-length'] ?? '',
        );
        if (declaredLength != null &&
            (declaredLength <= 0 || declaredLength > _maxImageBytes)) {
          failed++;
          continue;
        }
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > _maxImageBytes) {
            throw const QuizCloudSyncException('题图超过 5MB 限制');
          }
          bytes.addAll(chunk);
        }
        if (bytes.isEmpty) {
          failed++;
          continue;
        }
        await file.writeAsBytes(bytes, flush: true);
        await _rewriteLocalImagePath(item, file.path);
        cached++;
      } catch (_) {
        // 单图失败不影响其它题
        failed++;
      }
    }
    return (cached: cached, failed: failed);
  }

  static Uri? _resolveImageUri(String raw, String serverUrl) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return Uri.tryParse(value);
    }
    if (value.startsWith('file://') ||
        value.startsWith('/data/') ||
        value.startsWith('/storage/')) {
      return null; // 已是本地路径
    }
    if (serverUrl.isEmpty) return null;
    final base = Uri.parse(serverUrl);
    if (value.startsWith('/')) {
      return base.replace(path: value, query: '', fragment: '');
    }
    return base.resolve(value);
  }

  static String _guessExt(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return '.jpg';
    if (lower.endsWith('.webp')) return '.webp';
    if (lower.endsWith('.gif')) return '.gif';
    return '.png';
  }

  static bool _isAllowedImageContentType(String? contentType) {
    final mime = (contentType ?? '').split(';').first.trim().toLowerCase();
    return mime == 'image/jpeg' ||
        mime == 'image/png' ||
        mime == 'image/webp' ||
        mime == 'image/gif';
  }

  static Future<void> _rewriteLocalImagePath(
    QuizBankItem item,
    String localPath,
  ) async {
    try {
      await QuizBankStorage.updateImagePath(item.id, localPath);
    } catch (_) {}
  }

  static Future<int> _importIntoBank(List<QuizBankItem> items) async {
    return QuizBankStorage.mergeCloudItems(items);
  }

  static String _safeKey(String raw) =>
      base64Url.encode(utf8.encode(raw)).replaceAll('=', '');
  void dispose() => _httpClient.close();
}

class QuizCloudCatalog {
  const QuizCloudCatalog({
    required this.id,
    required this.name,
    required this.count,
  });
  factory QuizCloudCatalog.fromJson(Map<String, dynamic> json) =>
      QuizCloudCatalog(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? json['id'] ?? ''}',
        count: json['count'] is num
            ? (json['count'] as num).toInt()
            : int.tryParse('${json['count']}') ?? 0,
      );
  final String id;
  final String name;
  final int count;
}

class QuizCloudSyncResult {
  const QuizCloudSyncResult({
    required this.cursor,
    required this.inserted,
    required this.cloudDeletes,
    this.imagesCached = 0,
    this.imageFailures = 0,
    this.pages = 0,
    this.reachedPageLimit = false,
  });
  final int cursor;
  final int inserted;
  final int cloudDeletes;
  final int imagesCached;
  final int imageFailures;
  final int pages;
  final bool reachedPageLimit;
}

class QuizCloudImageRepairResult {
  const QuizCloudImageRepairResult({
    required this.scanned,
    required this.cached,
    required this.failed,
  });
  final int scanned;
  final int cached;
  final int failed;
}

class QuizCloudSubmission {
  const QuizCloudSubmission({
    required this.id,
    required this.status,
    this.reviewNote = '',
    this.linkedQuestionId,
    this.reviewedAt,
    this.question = '',
    this.options = const <String>[],
    this.imageSha256,
    this.imagePerceptualHash,
  });

  factory QuizCloudSubmission.fromJson(Map<String, dynamic> json) {
    final nested = json['question'];
    final questionMap = nested is Map
        ? Map<String, dynamic>.from(nested)
        : const <String, dynamic>{};
    final rawOptions = questionMap['options'];
    final imageSha256 =
        '${questionMap['imageSha256'] ?? json['imageSha256'] ?? ''}'.trim();
    final imagePerceptualHash =
        '${questionMap['imagePerceptualHash'] ?? json['imagePerceptualHash'] ?? ''}'
            .trim();
    return QuizCloudSubmission(
      id: '${json['id'] ?? ''}',
      status: '${json['status'] ?? ''}',
      reviewNote: '${json['reviewNote'] ?? ''}',
      linkedQuestionId: _optional(json['linkedQuestionId']),
      reviewedAt: DateTime.tryParse('${json['reviewedAt'] ?? ''}'),
      question: nested is Map
          ? '${questionMap['question'] ?? ''}'
          : '${nested ?? ''}',
      options: rawOptions is List
          ? rawOptions.map((e) => '$e').toList(growable: false)
          : const <String>[],
      imageSha256: imageSha256.isEmpty ? null : imageSha256,
      imagePerceptualHash: imagePerceptualHash.isEmpty
          ? null
          : imagePerceptualHash,
    );
  }

  static String? _optional(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  final String id;
  final String status;
  final String reviewNote;
  final String? linkedQuestionId;
  final DateTime? reviewedAt;

  /// 云端回传的题干与选项，用于历史投稿（无 remoteSubmissionId）的兜底匹配。
  final String question;
  final List<String> options;
  final String? imageSha256;
  final String? imagePerceptualHash;

  /// 审核已产生终态（不再是排队中）。
  bool get isSettled => localSyncStatus != null;

  /// 云端审核状态 → 本地 syncStatus；仍在排队时返回 null。
  String? get localSyncStatus {
    switch (status.trim().toLowerCase()) {
      case 'approved':
      case 'published':
        return QuizSyncStatus.published;
      case 'merged':
        return QuizSyncStatus.merged;
      case 'rejected':
        return QuizSyncStatus.rejected;
      default:
        return null;
    }
  }
}

class QuizCloudSyncException implements Exception {
  const QuizCloudSyncException(this.message);
  final String message;
  @override
  String toString() => message;
}
