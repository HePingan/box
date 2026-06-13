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
