import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../account/data/account_client.dart';
import '../../account/data/admin_client.dart';
import '../domain/quiz_bank_import_report.dart';
import '../domain/quiz_bank_models.dart';

class QuizBankAdminClient {
  QuizBankAdminClient({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<List<QuizBankQuestion>> fetchQuestions({
    required String serverUrl,
    required String token,
    String? search,
    String? status,
  }) async {
    final query = <String, String>{};
    if (search != null && search.trim().isNotEmpty) {
      query['search'] = search.trim();
    }
    if (status != null && status.trim().isNotEmpty) {
      query['status'] = status.trim();
    }
    final response = await _httpClient.get(
      _uri(serverUrl, '/admin/quiz/questions').replace(queryParameters: query),
      headers: _headers(token),
    );
    return _questionList(_decode(response));
  }

  Future<List<QuizBankSubmission>> fetchPendingSubmissions({
    required String serverUrl,
    required String token,
  }) async {
    return fetchSubmissions(
      serverUrl: serverUrl,
      token: token,
      status: 'pending',
    );
  }

  Future<List<QuizBankSubmission>> fetchSubmissions({
    required String serverUrl,
    required String token,
    String status = '',
  }) async {
    final path = status.trim() == 'pending'
        ? '/admin/quiz/submissions/pending'
        : '/admin/quiz/submissions';
    final uri = _uri(serverUrl, path).replace(
      queryParameters: status.trim().isEmpty || status.trim() == 'pending'
          ? null
          : {'status': status.trim()},
    );
    final response = await _httpClient.get(uri, headers: _headers(token));
    final decoded = _decode(response);
    final items = decoded['submissions'] ?? decoded['items'] ?? decoded['data'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map(
          (item) =>
              QuizBankSubmission.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  Future<QuizBankSubmission> reviewSubmission({
    required String serverUrl,
    required String token,
    required String id,
    required String action, // approve | reject
    String reviewNote = '',
  }) async {
    final normalized = action.trim().toLowerCase() == 'reject'
        ? 'reject'
        : 'approve';
    final response = await _httpClient.post(
      _uri(
        serverUrl,
        '/admin/quiz/submissions/${Uri.encodeComponent(id)}/$normalized',
      ),
      headers: _headers(token, json: true),
      body: jsonEncode({
        if (reviewNote.trim().isNotEmpty) 'reviewNote': reviewNote.trim(),
      }),
    );
    return QuizBankSubmission.fromJson(_decode(response));
  }

  Future<QuizBankQuestion> createQuestion({
    required String serverUrl,
    required String token,
    required Map<String, dynamic> data,
  }) async {
    final response = await _httpClient.post(
      _uri(serverUrl, '/admin/quiz/questions'),
      headers: _headers(token, json: true),
      body: jsonEncode(data),
    );
    return QuizBankQuestion.fromJson(_questionPayload(_decode(response)));
  }

  Future<QuizBankQuestion> updateQuestion({
    required String serverUrl,
    required String token,
    required String id,
    required Map<String, dynamic> data,
  }) async {
    final response = await _httpClient.patch(
      _uri(serverUrl, '/admin/quiz/questions/${Uri.encodeComponent(id)}'),
      headers: _headers(token, json: true),
      body: jsonEncode(data),
    );
    return QuizBankQuestion.fromJson(_questionPayload(_decode(response)));
  }

  Future<void> deleteQuestion({
    required String serverUrl,
    required String token,
    required String id,
  }) async {
    final response = await _httpClient.delete(
      _uri(serverUrl, '/admin/quiz/questions/${Uri.encodeComponent(id)}'),
      headers: _headers(token),
    );
    _decode(response);
  }

  Future<QuizBankImportReport> importQuestions({
    required String serverUrl,
    required String token,
    required List<Map<String, dynamic>> items,
    bool dryRun = false,
    bool publish = true,
  }) async {
    final response = await _httpClient.post(
      _uri(serverUrl, '/admin/quiz/import'),
      headers: _headers(token, json: true),
      body: jsonEncode({
        'items': items,
        'dryRun': dryRun,
        'mode': publish ? 'published' : 'pending',
      }),
    );
    return QuizBankImportReport.fromJson(_decode(response));
  }

  Future<void> bulkSetCategory({
    required String serverUrl,
    required String token,
    required List<String> ids,
    required String category,
  }) async {
    final response = await _httpClient.post(
      _uri(serverUrl, '/admin/quiz/categories/bulk'),
      headers: _headers(token, json: true),
      body: jsonEncode({'ids': ids, 'category': category}),
    );
    _decode(response);
  }

  Future<List<Map<String, dynamic>>> fetchIncomplete({
    required String serverUrl,
    required String token,
    String filter = '',
    String query = '',
  }) async {
    final params = <String, String>{};
    if (filter.trim().isNotEmpty) params['filter'] = filter.trim();
    if (query.trim().isNotEmpty) params['q'] = query.trim();
    final response = await _httpClient.get(
      _uri(serverUrl, '/admin/quiz/incomplete').replace(
        queryParameters: params.isEmpty ? null : params,
      ),
      headers: _headers(token),
    );
    final decoded = _decode(response);
    return (decoded['items'] as List? ?? const [])
        .whereType<Map>()
        .map((x) => Map<String, dynamic>.from(x))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> bulkIncomplete({
    required String serverUrl,
    required String token,
    required String action,
    required List<String> ids,
    String category = '',
    String correctAnswer = '',
    String analysis = '',
    String image = '',
    Map<String, String>? answers,
  }) async {
    final body = <String, dynamic>{
      'action': action,
      'ids': ids,
      if (category.trim().isNotEmpty) 'category': category.trim(),
      if (correctAnswer.trim().isNotEmpty) 'correctAnswer': correctAnswer.trim(),
      if (analysis.trim().isNotEmpty) 'analysis': analysis.trim(),
      if (image.trim().isNotEmpty) 'image': image.trim(),
      if (answers != null && answers.isNotEmpty) 'answers': answers,
    };
    final response = await _httpClient.post(
      _uri(serverUrl, '/admin/quiz/incomplete/bulk'),
      headers: _headers(token, json: true),
      body: jsonEncode(body),
    );
    return _decode(response);
  }


  Future<Map<String, dynamic>> bulkUpdateQuestions({
    required String serverUrl,
    required String token,
    required String action,
    required List<String> ids,
    String category = '',
    String image = '',
  }) async {
    final body = <String, dynamic>{
      'action': action,
      'ids': ids,
      if (category.trim().isNotEmpty) 'category': category.trim(),
      if (image.trim().isNotEmpty) 'image': image.trim(),
    };
    final response = await _httpClient.post(
      _uri(serverUrl, '/admin/quiz/questions/bulk'),
      headers: _headers(token, json: true),
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<void> completeIncomplete({
    required String serverUrl,
    required String token,
    required String id,
    required String correctAnswer,
    String category = '',
    String analysis = '',
    String? image,
  }) async {
    final body = <String, dynamic>{'correctAnswer': correctAnswer};
    if (category.isNotEmpty) body['category'] = category;
    if (analysis.isNotEmpty) body['analysis'] = analysis;
    if (image != null && image.isNotEmpty) body['image'] = image;
    final response = await _httpClient.patch(
      _uri(serverUrl, '/admin/quiz/incomplete/${Uri.encodeComponent(id)}'),
      headers: _headers(token, json: true),
      body: jsonEncode(body),
    );
    _decode(response);
  }

  Future<String> uploadQuizImage({
    required String serverUrl,
    required String token,
    required String imageData,
  }) async {
    final response = await _httpClient.post(
      _uri(serverUrl, '/admin/quiz/images/upload'),
      headers: _headers(token, json: true),
      body: jsonEncode({'image': imageData}),
    );
    final decoded = _decode(response);
    return decoded['url']?.toString() ?? '';
  }

  Future<List<Map<String, dynamic>>> fetchImports({
    required String serverUrl,
    required String token,
  }) async {
    final response = await _httpClient.get(
      _uri(serverUrl, '/admin/quiz/imports'),
      headers: _headers(token),
    );
    final decoded = _decode(response);
    return (decoded['imports'] as List? ?? const [])
        .whereType<Map>()
        .map((x) => Map<String, dynamic>.from(x))
        .toList(growable: false);
  }

  static Uri _uri(String serverUrl, String path) {
    final normalized = BoxAccountClient.normalizeServerUrl(serverUrl);
    return Uri.parse(normalized).resolve(path);
  }

  static Map<String, String> _headers(String token, {bool json = false}) => {
    if (json) 'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  static List<QuizBankQuestion> _questionList(Map<String, dynamic> decoded) {
    final items = decoded['questions'] ?? decoded['items'] ?? decoded['data'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map(
          (item) => QuizBankQuestion.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  static Map<String, dynamic> _questionPayload(Map<String, dynamic> decoded) {
    final value = decoded['question'] ?? decoded['data'] ?? decoded;
    return value is Map ? Map<String, dynamic>.from(value) : decoded;
  }

  static Map<String, dynamic> _decode(http.Response response) {
    final text = utf8.decode(response.bodyBytes);
    dynamic decoded;
    try {
      decoded = text.trim().isEmpty ? <String, dynamic>{} : jsonDecode(text);
    } catch (_) {
      decoded = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map
          ? (decoded['message'] ?? decoded['error']?['message'] ?? '请求失败')
                .toString()
          : (text.trim().isEmpty ? '请求失败' : text.trim());
      throw BoxAdminException(message, statusCode: response.statusCode);
    }
    if (decoded is! Map) {
      throw BoxAdminException(
        '题库接口返回格式不是 JSON 对象。',
        statusCode: response.statusCode,
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  void dispose() => _httpClient.close();
}
