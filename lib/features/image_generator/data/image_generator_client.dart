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
    final base = baseUrl.trim().isEmpty
        ? 'https://api.openai.com/v1'
        : baseUrl.trim();
    final endpoint = Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}/models');
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;

    try {
      final response = await client
          .get(endpoint, headers: {'Authorization': 'Bearer ${apiKey.trim()}'})
          .timeout(const Duration(seconds: 30));
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
    } on ImageGeneratorException {
      rethrow;
    } catch (e) {
      throw ImageGeneratorException('获取模型列表失败：$e');
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<ImagePlatformQuota> fetchPlatformQuota({
    required String platformBaseUrl,
  }) async {
    final endpoint = Uri.parse(
      '${platformBaseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/api/image/quota',
    );
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final response = await client
          .get(endpoint)
          .timeout(const Duration(seconds: 20));
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
    } on ImageGeneratorException {
      rethrow;
    } catch (e) {
      throw ImageGeneratorException('获取平台额度失败：$e');
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<List<String>> fetchPlatformModels({
    required String platformBaseUrl,
  }) async {
    final endpoint = Uri.parse(
      '${platformBaseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/api/image/models',
    );
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final response = await client
          .get(endpoint)
          .timeout(const Duration(seconds: 20));
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
    } on ImageGeneratorException {
      rethrow;
    } catch (e) {
      throw ImageGeneratorException('获取平台模型失败：$e');
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<ImageGenerationResponse> generateWithPlatformQuota({
    required String platformBaseUrl,
    required ImageGenerationParams params,
  }) async {
    final endpoint = Uri.parse(
      '${platformBaseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/api/image/generate',
    );
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;
    try {
      final response = await client
          .post(
            endpoint,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(params.toRequestBody()),
          )
          .timeout(const Duration(seconds: 90));
      final text = utf8.decode(response.bodyBytes);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ImageGeneratorException(
          _extractError(text, response.statusCode),
          statusCode: response.statusCode,
          rawPreview: _preview(text),
        );
      }
      return _parseGenerationResponse(text, params.outputFormat);
    } on ImageGeneratorException {
      rethrow;
    } catch (e) {
      throw ImageGeneratorException('平台额度生图失败：$e');
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<ImageGenerationResponse> generate(ImageGenerationParams params) async {
    final endpoint = Uri.parse(params.endpoint);
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;

    try {
      final body = params.toRequestBody();

      final response = await client
          .post(
            endpoint,
            headers: {
              'Authorization': 'Bearer ${params.apiKey.trim()}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 90));

      final text = utf8.decode(response.bodyBytes);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ImageGeneratorException(
          _extractError(text, response.statusCode),
          statusCode: response.statusCode,
          rawPreview: _preview(text),
        );
      }

      return _parseGenerationResponse(text, params.outputFormat);
    } on ImageGeneratorException {
      rethrow;
    } catch (e) {
      throw ImageGeneratorException('生图请求失败：$e');
    } finally {
      if (closeClient) client.close();
    }
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
