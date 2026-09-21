import 'package:dio/dio.dart';

import '../../../config/app_config.dart';
import 'update_history_models.dart';

/// 历史更新日志的拉取结果。
///
/// 刻意用「结果对象」而不是抛异常：历史更新是关于页里的一个次要信息，
/// 拉不到应该在页面里如实说明原因（而不是转圈卡死或者弹红屏），
/// 所以失败原因必须能被 UI 拿到并显示。
class UpdateHistoryResult {
  const UpdateHistoryResult._({
    required this.entries,
    this.errorMessage,
  });

  const UpdateHistoryResult.success(List<UpdateHistoryEntry> entries)
      : this._(entries: entries);

  const UpdateHistoryResult.failure(String message)
      : this._(entries: const [], errorMessage: message);

  final List<UpdateHistoryEntry> entries;
  final String? errorMessage;

  bool get isFailure => errorMessage != null;
  bool get isEmpty => entries.isEmpty;
}

/// 从更新服务端拉取历史版本的更新日志。
///
/// 端点 `GET /api/v1/app-updates/history` 是**公开**的（无需鉴权），并且
/// 只回元数据：能列全部版本的 `/api/v1/admin/releases` 挂着管理员鉴权，
/// 把管理员凭据打进 APK 等于把发布后台的钥匙分发给每个用户。
class UpdateHistoryRepository {
  UpdateHistoryRepository({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 10),
              ),
            );

  final Dio _dio;

  /// 由 `updateCheckUrl` 推导出同源的 history 地址。
  ///
  /// 不新增 dart-define：更新检查地址已经是可配置项，历史接口和它同源同前缀，
  /// 再加一个环境变量就多一处可能配错、且两者必须一致的地方。
  static String? historyUrlFrom(String checkUrl) {
    final trimmed = checkUrl.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    // 只接受 https：明文 http 下别人可以随意改写「历史更新」的内容。
    if (uri == null || uri.scheme != 'https') return null;
    if (!uri.path.endsWith('/check')) return null;
    final path = '${uri.path.substring(0, uri.path.length - '/check'.length)}'
        '/history';
    return uri.replace(path: path).toString();
  }

  Future<UpdateHistoryResult> fetch({
    required String packageName,
    int limit = 30,
  }) async {
    final url = historyUrlFrom(AppConfig.updateCheckUrl);
    if (url == null) {
      return const UpdateHistoryResult.failure('更新服务地址未正确配置');
    }

    Response<dynamic> res;
    try {
      res = await _dio.get(
        url,
        queryParameters: {
          'app_id': AppConfig.appId,
          'platform': AppConfig.updatePlatform,
          'channel': AppConfig.appChannel,
          'package_name': packageName,
          'limit': limit,
        },
      );
    } on DioException catch (e) {
      return UpdateHistoryResult.failure(_describeDioError(e));
    } catch (_) {
      return const UpdateHistoryResult.failure('拉取历史更新失败');
    }

    final body = res.data;
    if (body is! Map) {
      return const UpdateHistoryResult.failure('服务端返回格式异常');
    }
    if (body['code'] != 0) {
      final msg = body['message'];
      return UpdateHistoryResult.failure(
        msg is String && msg.isNotEmpty ? msg : '服务端返回错误',
      );
    }

    final data = body['data'];
    if (data is! Map) {
      return const UpdateHistoryResult.failure('服务端返回格式异常');
    }

    final rawItems = data['items'];
    if (rawItems is! List) {
      return const UpdateHistoryResult.failure('服务端返回格式异常');
    }

    final entries = <UpdateHistoryEntry>[];
    for (final item in rawItems) {
      if (item is! Map) continue;
      final entry = UpdateHistoryEntry.fromJson(
        item.cast<String, dynamic>(),
      );
      // 版本号缺失的记录直接丢：拿它当条目会显示成一条无名空记录。
      if (entry.versionName.isEmpty) continue;
      entries.add(entry);
    }

    // 服务端已按 version_code 倒序，这里再排一次是为了不把展示顺序
    // 押在服务端实现上 —— 新版在最上面是这个页面的语义要求。
    entries.sort((a, b) => b.versionCode.compareTo(a.versionCode));

    return UpdateHistoryResult.success(entries);
  }

  String _describeDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return '连接更新服务超时';
      case DioExceptionType.connectionError:
        return '网络不可用，无法连接更新服务';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        return code == null ? '服务端返回错误' : '服务端返回错误（HTTP $code）';
      default:
        return '拉取历史更新失败';
    }
  }
}
