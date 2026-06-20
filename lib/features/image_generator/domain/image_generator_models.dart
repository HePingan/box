import 'dart:convert';

enum ImageGeneratorAccessMode {
  ownKey('ownKey', '自带 Key'),
  platformQuota('platformQuota', '平台额度');

  const ImageGeneratorAccessMode(this.wireName, this.label);

  final String wireName;
  final String label;

  static ImageGeneratorAccessMode fromWireName(String value) {
    final normalized = value.trim();
    for (final mode in ImageGeneratorAccessMode.values) {
      if (mode.wireName == normalized || mode.name == normalized) return mode;
    }
    return ImageGeneratorAccessMode.ownKey;
  }
}

class ImageGenerationParams {
  const ImageGenerationParams({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.prompt,
    required this.size,
    required this.quality,
    required this.outputFormat,
    this.negativePrompt = '',
    this.referenceImageUrls = const [],
    this.referenceImageField = ImageReferencePayloadField.none,
    this.count = 1,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final String prompt;
  final String negativePrompt;
  final String size;
  final String quality;
  final String outputFormat;
  final List<String> referenceImageUrls;
  final ImageReferencePayloadField referenceImageField;
  final int count;

  String get effectivePrompt {
    final negative = negativePrompt.trim();
    if (negative.isEmpty) return prompt.trim();
    return '${prompt.trim()}\n\nNegative prompt: $negative';
  }

  Map<String, dynamic> toRequestBody() {
    final body = <String, dynamic>{
      'model': model.trim().isEmpty ? 'gpt-image-1' : model.trim(),
      'prompt': effectivePrompt,
      'size': size,
      'quality': quality,
      'n': count.clamp(1, 4),
    };
    if (outputFormat.trim().isNotEmpty) {
      body['output_format'] = outputFormat.trim();
    }
    final urls = referenceImageUrls
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toList();
    if (referenceImageField.shouldSend && urls.isNotEmpty) {
      if (urls.length == 1) {
        body[referenceImageField.wireName] = urls.first;
      } else {
        body[referenceImageField.wireName] = urls;
      }
    }
    return body;
  }

  String get normalizedBaseUrl {
    final base = baseUrl.trim().isEmpty
        ? 'https://api.openai.com/v1'
        : baseUrl.trim();
    return base.replaceAll(RegExp(r'/+$'), '');
  }

  String get endpoint => '$normalizedBaseUrl/images/generations';

  String get prettyRequestJson {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(toRequestBody());
  }
}

enum ImageReferencePayloadField {
  none('', '不发送'),
  image('image', 'image'),
  referenceImage('reference_image', 'reference_image'),
  inputImage('input_image', 'input_image');

  const ImageReferencePayloadField(this.wireName, this.label);

  final String wireName;
  final String label;

  bool get shouldSend => this != ImageReferencePayloadField.none;

  static ImageReferencePayloadField fromWireName(String value) {
    final normalized = value.trim();
    for (final field in ImageReferencePayloadField.values) {
      if (field.wireName == normalized || field.name == normalized) {
        return field;
      }
    }
    return ImageReferencePayloadField.none;
  }
}

class ImageGeneratorDraft {
  const ImageGeneratorDraft({
    required this.baseUrl,
    required this.platformBaseUrl,
    required this.accessMode,
    required this.model,
    required this.prompt,
    required this.negativePrompt,
    required this.referenceImageUrls,
    required this.referenceImageField,
    required this.size,
    required this.quality,
    required this.outputFormat,
    required this.count,
  });

  factory ImageGeneratorDraft.defaults() {
    return const ImageGeneratorDraft(
      baseUrl: 'https://api.openai.com/v1',
      platformBaseUrl: '',
      accessMode: ImageGeneratorAccessMode.ownKey,
      model: 'gpt-image-1',
      prompt: '一张用于工具箱 App 的 AI 生图入口海报，蓝紫渐变，玻璃拟态，科技感构图，移动端 UI 宣传图',
      negativePrompt: '低清晰度，文字错误，水印，畸形手指',
      referenceImageUrls: [],
      referenceImageField: ImageReferencePayloadField.none,
      size: '1024x1024',
      quality: 'auto',
      outputFormat: 'png',
      count: 1,
    );
  }

  factory ImageGeneratorDraft.fromJson(Map<String, dynamic> json) {
    final defaults = ImageGeneratorDraft.defaults();
    // 兼容旧版 single-string referenceImageUrl
    final rawUrls = json['referenceImageUrls'];
    final List<String> urls;
    if (rawUrls is List) {
      urls = rawUrls.cast<String>();
    } else {
      final oldUrl = _asString(json['referenceImageUrl']);
      urls = oldUrl.isNotEmpty ? [oldUrl] : [];
    }
    return ImageGeneratorDraft(
      baseUrl: _asString(json['baseUrl'], defaults.baseUrl),
      platformBaseUrl: _asString(
        json['platformBaseUrl'],
        defaults.platformBaseUrl,
      ),
      accessMode: ImageGeneratorAccessMode.fromWireName(
        _asString(json['accessMode'], defaults.accessMode.wireName),
      ),
      model: _asString(json['model'], defaults.model),
      prompt: _asString(json['prompt'], defaults.prompt),
      negativePrompt: _asString(
        json['negativePrompt'],
        defaults.negativePrompt,
      ),
      referenceImageUrls: urls,
      referenceImageField: ImageReferencePayloadField.fromWireName(
        _asString(json['referenceImageField']),
      ),
      size: _asString(json['size'], defaults.size),
      quality: _asString(json['quality'], defaults.quality),
      outputFormat: _asString(json['outputFormat'], defaults.outputFormat),
      count: _asInt(json['count'], defaults.count).clamp(1, 4),
    );
  }

  final String baseUrl;
  final String platformBaseUrl;
  final ImageGeneratorAccessMode accessMode;
  final String model;
  final String prompt;
  final String negativePrompt;
  final List<String> referenceImageUrls;
  final ImageReferencePayloadField referenceImageField;
  final String size;
  final String quality;
  final String outputFormat;
  final int count;

  Map<String, dynamic> toJson() {
    return {
      'baseUrl': baseUrl,
      'platformBaseUrl': platformBaseUrl,
      'accessMode': accessMode.wireName,
      'model': model,
      'prompt': prompt,
      'negativePrompt': negativePrompt,
      'referenceImageUrls': referenceImageUrls,
      'referenceImageUrl': referenceImageUrls.isNotEmpty
          ? referenceImageUrls.first
          : '',
      'referenceImageField': referenceImageField.wireName,
      'size': size,
      'quality': quality,
      'outputFormat': outputFormat,
      'count': count,
    };
  }
}

class ImagePlatformQuota {
  const ImagePlatformQuota({
    required this.remaining,
    required this.dailyLimit,
    required this.usedToday,
    this.totalLimit,
    this.status = 'normal',
    this.message = '',
  });

  factory ImagePlatformQuota.fromJson(Map<String, dynamic> json) {
    return ImagePlatformQuota(
      remaining: _asInt(
        json['remaining'] ?? json['remainingQuota'] ?? json['quota'],
        0,
      ),
      dailyLimit: _asInt(json['dailyLimit'] ?? json['dailyQuota'], 0),
      usedToday: _asInt(
        json['usedToday'] ?? json['dailyUsed'] ?? json['used'],
        0,
      ),
      totalLimit: json['totalLimit'] == null
          ? null
          : _asInt(json['totalLimit'], 0),
      status: _asString(json['status'], 'normal'),
      message: _asString(json['message']),
    );
  }

  final int remaining;
  final int dailyLimit;
  final int usedToday;
  final int? totalLimit;
  final String status;
  final String message;

  bool get hasQuota => remaining > 0;
}

class GeneratedImageResult {
  const GeneratedImageResult({
    required this.image,
    this.revisedPrompt,
    this.rawUrl,
  });

  final String image;
  final String? revisedPrompt;
  final String? rawUrl;

  bool get isDataUrl => image.startsWith('data:image/');
}

class ImageGenerationResponse {
  const ImageGenerationResponse({required this.images, this.rawPreview = ''});

  final List<GeneratedImageResult> images;
  final String rawPreview;
}

class ImageGeneratorRequestDiagnostics {
  const ImageGeneratorRequestDiagnostics({
    required this.createdAt,
    required this.endpoint,
    required this.requestJson,
    required this.referenceField,
    required this.success,
    this.statusCode,
    this.message = '',
    this.rawPreview = '',
    this.imageCount = 0,
    this.resultFormat = '',
  });

  final DateTime createdAt;
  final String endpoint;
  final String requestJson;
  final ImageReferencePayloadField referenceField;
  final bool success;
  final int? statusCode;
  final String message;
  final String rawPreview;
  final int imageCount;
  final String resultFormat;

  String get statusLabel {
    if (success) return '请求成功';
    final code = statusCode;
    if (code == null) return '请求失败';
    return '请求失败 HTTP $code';
  }

  String get timeLabel {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(createdAt.hour)}:${two(createdAt.minute)}:${two(createdAt.second)}';
  }

  String get referenceLabel {
    if (!referenceField.shouldSend) return '不发送';
    return referenceField.wireName;
  }

  String toCopyText() {
    final buffer = StringBuffer()
      ..writeln('AI 生图请求诊断')
      ..writeln('时间: ${createdAt.toIso8601String()}')
      ..writeln('状态: $statusLabel')
      ..writeln('Endpoint: $endpoint')
      ..writeln('参考图字段: $referenceLabel')
      ..writeln()
      ..writeln('JSON Body:')
      ..writeln(requestJson);
    if (success) {
      buffer
        ..writeln()
        ..writeln('图片数量: $imageCount')
        ..writeln('返回格式: ${resultFormat.isEmpty ? '未知' : resultFormat}');
    } else {
      buffer
        ..writeln()
        ..writeln('错误: ${message.isEmpty ? '未知错误' : message}');
      if (rawPreview.isNotEmpty) {
        buffer.writeln('原始响应: $rawPreview');
      }
    }
    return buffer.toString().trimRight();
  }
}

class ImageGenerationHistoryItem {
  const ImageGenerationHistoryItem({
    required this.prompt,
    required this.negativePrompt,
    required this.referenceImageUrls,
    required this.referenceImageField,
    required this.model,
    required this.size,
    required this.quality,
    required this.outputFormat,
    required this.createdAt,
    required this.images,
  });

  factory ImageGenerationHistoryItem.fromJson(Map<String, dynamic> json) {
    final imageList = json['images'];
    // 兼容旧版 single-string referenceImageUrl
    final rawUrls = json['referenceImageUrls'];
    final List<String> urls;
    if (rawUrls is List) {
      urls = rawUrls.cast<String>();
    } else {
      final oldUrl = _asString(json['referenceImageUrl']);
      urls = oldUrl.isNotEmpty ? [oldUrl] : [];
    }
    return ImageGenerationHistoryItem(
      prompt: _asString(json['prompt']),
      negativePrompt: _asString(json['negativePrompt']),
      referenceImageUrls: urls,
      referenceImageField: ImageReferencePayloadField.fromWireName(
        _asString(json['referenceImageField']),
      ),
      model: _asString(json['model'], 'gpt-image-1'),
      size: _asString(json['size'], '1024x1024'),
      quality: _asString(json['quality'], 'auto'),
      outputFormat: _asString(json['outputFormat'], 'png'),
      createdAt:
          DateTime.tryParse(_asString(json['createdAt'])) ?? DateTime.now(),
      images: imageList is List
          ? imageList
                .map((e) => _asString(e))
                .where((e) => e.isNotEmpty)
                .toList()
          : const [],
    );
  }

  final String prompt;
  final String negativePrompt;
  final List<String> referenceImageUrls;
  final ImageReferencePayloadField referenceImageField;
  final String model;
  final String size;
  final String quality;
  final String outputFormat;
  final DateTime createdAt;
  final List<String> images;

  bool get hasImages => images.isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'prompt': prompt,
      'negativePrompt': negativePrompt,
      'referenceImageUrls': referenceImageUrls,
      'referenceImageUrl': referenceImageUrls.isNotEmpty
          ? referenceImageUrls.first
          : '',
      'referenceImageField': referenceImageField.wireName,
      'model': model,
      'size': size,
      'quality': quality,
      'outputFormat': outputFormat,
      'createdAt': createdAt.toIso8601String(),
      'images': images,
    };
  }

  String toJsonString() => jsonEncode(toJson());
}

String _asString(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

int _asInt(dynamic value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}
