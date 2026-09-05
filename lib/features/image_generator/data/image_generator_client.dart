import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/image_generator_models.dart';

class ImageGeneratorClient {
  const ImageGeneratorClient({http.Client? httpClient})
    : _httpClient = httpClient;

  final http.Client? _httpClient;

  Future<List<String>> fetchModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    final base = baseUrl.trim();
    if (base.isEmpty) {
      throw const ImageGeneratorException('Base URL 不能为空，请配置图片生成服务的接口地址。');
    }
    final endpoint = Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}/models');
    return _fetchModelList(endpoint, {
      'Authorization': 'Bearer ${apiKey.trim()}',
    });
  }

  Future<ImagePlatformQuota> fetchPlatformQuota({
    required String platformBaseUrl,
    String? platformToken,
  }) async {
    final endpoint = Uri.parse(
      '${platformBaseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/api/image/quota',
    );
    final response = await _request(
      endpoint,
      headers: _platformHeaders(platformToken),
      timeout: const Duration(seconds: 20),
    );
    final text = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ImageGeneratorException(
        _extractError(text, response.statusCode),
        statusCode: response.statusCode,
        rawPreview: _preview(text),
      );
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const ImageGeneratorException('额度接口返回格式不是 JSON 对象');
    }
    return ImagePlatformQuota.fromJson(decoded);
  }

  Future<List<String>> fetchPlatformModels({
    required String platformBaseUrl,
    String? platformToken,
  }) async {
    final endpoint = Uri.parse(
      '${platformBaseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/api/image/models',
    );
    final response = await _request(
      endpoint,
      headers: _platformHeaders(platformToken),
      timeout: const Duration(seconds: 20),
    );
    final text = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ImageGeneratorException(
        _extractError(text, response.statusCode),
        statusCode: response.statusCode,
        rawPreview: _preview(text),
      );
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const ImageGeneratorException('平台模型接口返回格式不是 JSON 对象');
    }
    return _parseModelList(decoded, text);
  }

  Future<ImageGenerationResponse> generateWithPlatformQuota({
    required String platformBaseUrl,
    required ImageGenerationParams params,
    String? platformToken,
  }) async {
    final endpoint = Uri.parse(
      '${platformBaseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/api/image/generate',
    );
    final response = await _request(
      endpoint,
      method: 'POST',
      headers: _platformHeaders(platformToken, json: true),
      body: jsonEncode(params.toRequestBody()),
      timeout: const Duration(seconds: 300),
    );
    final text = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ImageGeneratorException(
        _extractError(text, response.statusCode),
        statusCode: response.statusCode,
        rawPreview: _preview(text),
      );
    }
    return _parseGenerationResponse(text, params.outputFormat);
  }

  Future<ImageGenerationResponse> generate(ImageGenerationParams params) async {
    final endpoint = Uri.parse(params.endpoint);
    final body = params.toRequestBody();

    final response = await _request(
      endpoint,
      method: 'POST',
      headers: {
        'Authorization': 'Bearer ${params.apiKey.trim()}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
      timeout: const Duration(seconds: 300),
    );

    final text = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ImageGeneratorException(
        _extractError(text, response.statusCode),
        statusCode: response.statusCode,
        rawPreview: _preview(text),
      );
    }

    return _parseGenerationResponse(text, params.outputFormat);
  }

  /// Shared HTTP request helper that manages client lifecycle.
  Future<http.Response> _request(
    Uri endpoint, {
    String method = 'GET',
    Map<String, String>? headers,
    String? body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final request = http.Request(method, endpoint)
        ..headers.addAll(headers ?? {});
      if (method == 'POST') {
        request.body = body ?? '';
      }

      // 必须用 client.send()：http.Request.send() 会自建一次性 client，
      // 那样注入的 httpClient 形同虚设（测试打真实网络、连接无法复用）。
      final streamed = await client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamed);

      // 状态码判定统一留给各调用方（它们都会检查并附带 rawPreview），
      // 这里不再重复抛，避免同一响应被解码两次。
      return response;
    } on ImageGeneratorException {
      rethrow;
    } catch (e) {
      throw ImageGeneratorException('请求失败：$e');
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<List<String>> _fetchModelList(
    Uri endpoint,
    Map<String, String> headers,
  ) async {
    final response = await _request(
      endpoint,
      headers: headers,
      timeout: const Duration(seconds: 30),
    );
    final text = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ImageGeneratorException(
        _extractError(text, response.statusCode),
        statusCode: response.statusCode,
        rawPreview: _preview(text),
      );
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const ImageGeneratorException('模型接口返回格式不是 JSON 对象');
    }
    return _parseModelList(decoded, text);
  }

  static Map<String, String> _platformHeaders(
    String? token, {
    bool json = false,
  }) {
    final headers = <String, String>{};
    if (json) headers['Content-Type'] = 'application/json';
    final trimmed = token?.trim() ?? '';
    if (trimmed.isNotEmpty) headers['Authorization'] = 'Bearer $trimmed';
    return headers;
  }

  static List<String> _parseModelList(
    Map<String, dynamic> decoded,
    String text,
  ) {
    final data = decoded['data'] ?? decoded['models'];
    if (data is! List) {
      throw ImageGeneratorException('模型接口没有返回 data 列表：${_preview(text)}');
    }
    final models =
        data
            .map((item) {
              if (item is Map && item['id'] != null) {
                return item['id'].toString();
              }
              if (item is String) return item;
              return '';
            })
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (models.isEmpty) {
      throw ImageGeneratorException('模型接口返回为空：${_preview(text)}');
    }
    return models;
  }

  static ImageGenerationResponse _parseGenerationResponse(
    String text,
    String outputFormat,
  ) {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const ImageGeneratorException('接口返回格式不是 JSON 对象');
    }

    final data = decoded['data'];
    if (data is! List || data.isEmpty) {
      throw ImageGeneratorException('接口没有返回图片数据：${_preview(text)}');
    }

    final images = <GeneratedImageResult>[];
    for (final item in data) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final url = _asString(map['url']);
      final b64 = _asString(map['b64_json']);
      final revised = _asString(map['revised_prompt']);
      if (url.isNotEmpty) {
        images.add(
          GeneratedImageResult(
            image: url,
            rawUrl: url,
            revisedPrompt: revised.isEmpty ? null : revised,
          ),
        );
      } else if (b64.isNotEmpty) {
        images.add(
          GeneratedImageResult(
            image: 'data:image/$outputFormat;base64,$b64',
            revisedPrompt: revised.isEmpty ? null : revised,
          ),
        );
      }
    }

    if (images.isEmpty) {
      throw ImageGeneratorException(
        '未识别到 url 或 b64_json 图片字段：${_preview(text)}',
      );
    }

    return ImageGenerationResponse(images: images, rawPreview: _preview(text));
  }

  static String _extractError(String text, int statusCode) {
    var message = '';
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] != null) {
          message = error['message'].toString();
        } else if (error is String && error.trim().isNotEmpty) {
          message = error.trim();
        } else {
          final fallback = decoded['message'] ?? decoded['detail'];
          if (fallback != null) message = fallback.toString();
        }
      }
    } catch (_) {}

    if (message.trim().isEmpty) {
      message = _preview(text);
    }

    final hint = switch (statusCode) {
      401 => 'API Key 无效或未授权，请检查 Key 是否完整。',
      403 => '当前 Key 无权限、额度不足，或该模型未开通。',
      404 => '接口路径或模型不兼容，请检查 Base URL 是否以 /v1 结尾。',
      408 => '请求超时，建议降低数量/质量后重试。',
      429 => '请求过于频繁或额度不足，请稍后再试。',
      >= 500 => '服务端错误，可能是中转接口或模型服务暂时不可用。',
      _ => '请检查 Base URL、模型、参数和中转接口兼容性。',
    };

    return 'HTTP $statusCode：$message\n$hint';
  }

  static String _preview(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 320) return compact;
    return '${compact.substring(0, 320)}...';
  }

  static String _asString(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }
}

class ImageGeneratorException implements Exception {
  const ImageGeneratorException(
    this.message, {
    this.statusCode,
    this.rawPreview = '',
  });

  final String message;
  final int? statusCode;
  final String rawPreview;

  @override
  String toString() => message;
}
