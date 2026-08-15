import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// OCR 识别结果。
class OcrResult {
  const OcrResult({
    this.fullText = '',
    this.lines = const [],
    this.scores = const [],
    this.error,
  });

  final String fullText;
  final List<String> lines;
  final List<double> scores;
  final String? error;

  bool get isSuccess => error == null && fullText.trim().isNotEmpty;

  /// 平均置信度（无分数时返回 0）。
  double get averageScore {
    if (scores.isEmpty) return 0;
    final sum = scores.fold<double>(0, (a, b) => a + b);
    return sum / scores.length;
  }

  /// OCR 服务没有返回行级 score 时不阻断：老服务兼容；有 score 时要求平均值达标。
  bool meetsAutoSearchConfidence({double minimum = 0.55}) =>
      scores.isEmpty || averageScore >= minimum;

  String confidenceDiagnostic({double minimum = 0.55}) {
    if (scores.isEmpty) return 'OCR 未提供置信度，已按兼容模式继续';
    return 'OCR 平均置信度 ${(averageScore * 100).toStringAsFixed(0)}%'
        '${meetsAutoSearchConfidence(minimum: minimum) ? "" : "，低于自动搜题阈值 ${(minimum * 100).round()}%"}';
  }
}

/// 图片题 OCR 客户端。
///
/// 对接用户自建 OCR 服务（与 qwen.hpa888.top 同反代模板）：
///  - POST {endpoint}/api/ocr/upload  (multipart file) —— 上传本地截屏字节
///  - GET  {endpoint}/api/ocr/fetch?url=<图片URL>       —— 让服务端抓取远程图片
///
/// 响应结构：
///  {"code":200,"data":{"texts":[...],"scores":[...],"full_text":"..."}}
class QuizOcrClient {
  static const maxUploadBytes = 2 * 1024 * 1024;
  QuizOcrClient({
    required this.endpoint,
    this.token = '',
    this.timeout = const Duration(seconds: 20),
    this.maxAttempts = 2,
    this.retryDelay = const Duration(milliseconds: 400),
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final String endpoint;
  final String token;
  final Duration timeout;
  final int maxAttempts;
  final Duration retryDelay;
  final http.Client _httpClient;

  String get _base {
    var e = endpoint.trim();
    if (e.isEmpty) e = 'https://ocr.hpa888.top';
    if (e.endsWith('/')) e = e.substring(0, e.length - 1);
    return e;
  }

  Map<String, String> get _authHeaders =>
      token.trim().isEmpty ? {} : {'Authorization': 'Bearer ${token.trim()}'};

  /// 上传截屏字节做 OCR。
  Future<OcrResult> recognizeBytes(
    Uint8List bytes, {
    String filename = 'quiz_capture.png',
  }) async {
    if (bytes.isEmpty) {
      return const OcrResult(error: '截屏数据为空');
    }
    if (bytes.length > maxUploadBytes) {
      return const OcrResult(error: '截图超过 2MB，请缩小识别区域后重试');
    }
    return _withRetry('OCR 上传失败', () async {
      final uri = Uri.parse('$_base/api/ocr/upload');
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(_authHeaders)
        ..files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: filename),
        );
      final streamed = await _httpClient.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamed);
      return _parseResponse(response.statusCode, _utf8Body(response));
    });
  }

  /// 网络/超时/5xx 类失败做有限重试；业务错误直接返回不重试。
  Future<OcrResult> _withRetry(
    String label,
    Future<OcrResult> Function() attempt,
  ) async {
    Object? lastError;
    for (var i = 0; i < maxAttempts; i++) {
      try {
        final result = await attempt();
        if (result.isSuccess || !_isRetryableError(result.error)) return result;
        lastError = result.error;
      } catch (e) {
        lastError = e;
      }
      if (i < maxAttempts - 1) {
        await Future<void>.delayed(retryDelay * (i + 1));
      }
    }
    return OcrResult(error: '$label：$lastError');
  }

  static bool _isRetryableError(String? error) {
    if (error == null) return false;
    final match = RegExp(r'OCR 返回 (\d{3})').firstMatch(error);
    final status = int.tryParse(match?.group(1) ?? '');
    return status != null && status >= 500;
  }

  /// 让服务端抓取远程图片 URL 做 OCR。
  Future<OcrResult> recognizeUrl(String imageUrl) async {
    if (imageUrl.trim().isEmpty) {
      return const OcrResult(error: '图片 URL 为空');
    }
    return _withRetry('OCR 抓取失败', () async {
      final uri = Uri.parse(
        '$_base/api/ocr/fetch',
      ).replace(queryParameters: {'url': imageUrl.trim()});
      final response = await _httpClient
          .get(uri, headers: _authHeaders)
          .timeout(timeout);
      return _parseResponse(response.statusCode, _utf8Body(response));
    });
  }

  void dispose() => _httpClient.close();

  /// package:http 在响应缺少 charset 时按 latin1 解码，会把中文识别结果变成乱码。
  /// OCR 服务返回的始终是 UTF-8 JSON，这里显式按 UTF-8 解码。
  static String _utf8Body(http.Response response) =>
      utf8.decode(response.bodyBytes, allowMalformed: true);

  OcrResult _parseResponse(int statusCode, String body) {
    if (statusCode != 200) {
      return OcrResult(error: 'OCR 返回 $statusCode');
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return const OcrResult(error: 'OCR 响应格式异常');
      final code = decoded['code'];
      if (code != null && code != 200) {
        return OcrResult(error: 'OCR 业务码 $code：${decoded['msg'] ?? ''}');
      }
      final data = decoded['data'];
      if (data is! Map) return const OcrResult(error: 'OCR 无 data');

      final lines = <String>[];
      final rawTexts = data['texts'];
      if (rawTexts is List) {
        for (final t in rawTexts) {
          final s = t?.toString().trim() ?? '';
          if (s.isNotEmpty) lines.add(s);
        }
      }

      final scores = <double>[];
      final rawScores = data['scores'];
      if (rawScores is List) {
        for (final s in rawScores) {
          final v = (s as num?)?.toDouble();
          if (v != null) scores.add(v);
        }
      }

      var fullText = (data['full_text'] as String?)?.trim() ?? '';
      if (fullText.isEmpty && lines.isNotEmpty) {
        fullText = lines.join('\n');
      }

      if (fullText.isEmpty) {
        return const OcrResult(error: 'OCR 未识别到文本');
      }
      return OcrResult(fullText: fullText, lines: lines, scores: scores);
    } catch (e) {
      return OcrResult(error: 'OCR 解析失败：$e');
    }
  }
}
