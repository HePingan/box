import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/image_generator_models.dart';

class ImageGeneratorClient {
  const ImageGeneratorClient({http.Client? httpClient})
    : _httpClient = httpClient;

  final http.Client? _httpClient;

  Future<ImageGenerationResponse> generate(ImageGenerationParams params) async {
    final base = params.baseUrl.trim().isEmpty
        ? 'https://api.openai.com/v1'
        : params.baseUrl.trim();
    final endpoint = Uri.parse(
      '${base.replaceAll(RegExp(r'/+$'), '')}/images/generations',
    );
    final client = _httpClient ?? http.Client();
    final closeClient = _httpClient == null;

    try {
      final body = <String, dynamic>{
        'model': params.model.trim().isEmpty
            ? 'gpt-image-1'
            : params.model.trim(),
        'prompt': params.effectivePrompt,
        'size': params.size,
        'quality': params.quality,
        'n': params.count.clamp(1, 4),
      };
      if (params.outputFormat.trim().isNotEmpty) {
        body['output_format'] = params.outputFormat.trim();
      }

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
        throw ImageGeneratorException(_extractError(text, response.statusCode));
      }

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
              image: 'data:image/${params.outputFormat};base64,$b64',
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

      return ImageGenerationResponse(
        images: images,
        rawPreview: _preview(text),
      );
    } on ImageGeneratorException {
      rethrow;
    } catch (e) {
      throw ImageGeneratorException('生图请求失败：$e');
    } finally {
      if (closeClient) client.close();
    }
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
  const ImageGeneratorException(this.message);

  final String message;

  @override
  String toString() => message;
}
