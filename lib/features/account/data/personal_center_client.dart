import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/personal_center_models.dart';

class PersonalCenterClient {
  PersonalCenterClient({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final http.Client _http;

  Future<PersonalOverview> fetchOverview({
    required String serverUrl,
    required String token,
  }) async {
    final body = await _get(serverUrl, token, '/api/me/overview');
    return PersonalOverview.fromJson(body);
  }

  /// 拉取生图用量流水。
  ///
  /// [success] 为 null 时返回全部，true/false 分别只返回成功/失败记录。
  /// 服务端 limit 上限为 200。
  Future<PersonalQuotaSummary> fetchQuotaSummary({
    required String serverUrl,
    required String token,
    bool? success,
    int limit = 50,
  }) async {
    final query = <String, String>{'limit': '${limit.clamp(1, 200)}'};
    if (success != null) query['success'] = success ? 'true' : 'false';
    final body = await _get(
      serverUrl,
      token,
      '/api/me/quota/transactions',
      query,
    );
    return PersonalQuotaSummary.fromJson(body);
  }

  Future<PersonalQuizPage> fetchMyQuizzes({
    required String serverUrl,
    required String token,
    String? status,
    int limit = 50,
  }) async {
    final query = <String, String>{'limit': '$limit'};
    if (status != null && status.isNotEmpty) query['status'] = status;
    final body = await _get(serverUrl, token, '/api/me/quiz/questions', query);
    return PersonalQuizPage.fromJson(body);
  }

  Future<List<PersonalActivityDay>> fetchActivity({
    required String serverUrl,
    required String token,
  }) async {
    final body = await _get(serverUrl, token, '/api/me/activity');
    final items = body['activity'] as List<dynamic>? ?? [];
    return items
        .whereType<Map>()
        .map((e) => PersonalActivityDay.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> fetchMyPlugins({
    required String serverUrl,
    required String token,
  }) async {
    final body = await _get(serverUrl, token, '/api/plugins/mine');
    return _list(body['items']);
  }

  List<Map<String, dynamic>> _list(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false)
      : const [];

  Future<Map<String, dynamic>> _get(
    String serverUrl,
    String token,
    String path, [
    Map<String, String>? query,
  ]) async {
    final base = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse(
      '$base$path',
    ).replace(queryParameters: query?.isEmpty == true ? null : query);
    final response = await _http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw PersonalCenterException(
        '请求失败 HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw PersonalCenterException('响应解析失败：${e.toString()}');
    }
  }
}

class PersonalCenterException implements Exception {
  const PersonalCenterException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}
