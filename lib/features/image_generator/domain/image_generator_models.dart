import 'dart:convert';

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
  final int count;

  String get effectivePrompt {
    final negative = negativePrompt.trim();
    if (negative.isEmpty) return prompt.trim();
    return '${prompt.trim()}\n\nNegative prompt: $negative';
  }
}

class ImageGeneratorDraft {
  const ImageGeneratorDraft({
    required this.baseUrl,
    required this.model,
    required this.prompt,
    required this.negativePrompt,
    required this.size,
    required this.quality,
    required this.outputFormat,
    required this.count,
  });

  factory ImageGeneratorDraft.defaults() {
    return const ImageGeneratorDraft(
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-image-1',
      prompt: '一张用于工具箱 App 的 AI 生图入口海报，蓝紫渐变，玻璃拟态，科技感构图，移动端 UI 宣传图',
      negativePrompt: '低清晰度，文字错误，水印，畸形手指',
      size: '1024x1024',
      quality: 'auto',
      outputFormat: 'png',
      count: 1,
    );
  }

  factory ImageGeneratorDraft.fromJson(Map<String, dynamic> json) {
    final defaults = ImageGeneratorDraft.defaults();
    return ImageGeneratorDraft(
      baseUrl: _asString(json['baseUrl'], defaults.baseUrl),
      model: _asString(json['model'], defaults.model),
      prompt: _asString(json['prompt'], defaults.prompt),
      negativePrompt: _asString(
        json['negativePrompt'],
        defaults.negativePrompt,
      ),
      size: _asString(json['size'], defaults.size),
      quality: _asString(json['quality'], defaults.quality),
      outputFormat: _asString(json['outputFormat'], defaults.outputFormat),
      count: _asInt(json['count'], defaults.count).clamp(1, 4),
    );
  }

  final String baseUrl;
  final String model;
  final String prompt;
  final String negativePrompt;
  final String size;
  final String quality;
  final String outputFormat;
  final int count;

  Map<String, dynamic> toJson() {
    return {
      'baseUrl': baseUrl,
      'model': model,
      'prompt': prompt,
      'negativePrompt': negativePrompt,
      'size': size,
      'quality': quality,
      'outputFormat': outputFormat,
      'count': count,
    };
  }
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

class ImageGenerationHistoryItem {
  const ImageGenerationHistoryItem({
    required this.prompt,
    required this.negativePrompt,
    required this.model,
    required this.size,
    required this.quality,
    required this.outputFormat,
    required this.createdAt,
    required this.images,
  });

  factory ImageGenerationHistoryItem.fromJson(Map<String, dynamic> json) {
    final imageList = json['images'];
    return ImageGenerationHistoryItem(
      prompt: _asString(json['prompt']),
      negativePrompt: _asString(json['negativePrompt']),
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
