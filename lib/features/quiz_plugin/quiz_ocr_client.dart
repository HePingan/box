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
  QuizOcrClient({
    required this.endpoint,
    this.token = '',
    this.timeout = const Duration(seconds: 20),
  });

  final String endpoint;
  final String token;
  final Duration timeout;

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
    try {
      final uri = Uri.parse('$_base/api/ocr/upload');
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(_authHeaders)
        ..files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: filename),
        );
      final streamed = await request.send().timeout(timeout);
      final response = await http.Response.fromStream(streamed);
      return _parseResponse(response.statusCode, response.body);
    } catch (e) {
      return OcrResult(error: 'OCR 上传失败：$e');
    }
  }

  /// 让服务端抓取远程图片 URL 做 OCR。
  Future<OcrResult> recognizeUrl(String imageUrl) async {
    if (imageUrl.trim().isEmpty) {
      return const OcrResult(error: '图片 URL 为空');
    }
    try {
      final uri = Uri.parse(
        '$_base/api/ocr/fetch',
      ).replace(queryParameters: {'url': imageUrl.trim()});
      final response = await http
          .get(uri, headers: _authHeaders)
          .timeout(timeout);
      return _parseResponse(response.statusCode, response.body);
    } catch (e) {
      return OcrResult(error: 'OCR 抓取失败：$e');
    }
  }

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
