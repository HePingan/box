import '../domain/image_generator_models.dart';

class ImageGeneratorPreflightItem {
  const ImageGeneratorPreflightItem({
    required this.message,
    required this.level,
  });

  final String message;
  final ImageGeneratorPreflightLevel level;
}

enum ImageGeneratorPreflightLevel { ok, warning, error }

List<ImageGeneratorPreflightItem> buildImageGeneratorPreflight(
  ImageGenerationParams params,
) {
  final items = <ImageGeneratorPreflightItem>[];
  final baseUrl = params.baseUrl.trim();
  final apiKey = params.apiKey.trim();
  final prompt = params.prompt.trim();
  final model = params.model.trim();
  final referenceUrl = params.referenceImageUrl.trim();

  final baseUri = Uri.tryParse(
    baseUrl.isEmpty ? params.normalizedBaseUrl : baseUrl,
  );
  if (baseUri == null ||
      !baseUri.hasScheme ||
      (baseUri.scheme != 'http' && baseUri.scheme != 'https')) {
    items.add(
      const ImageGeneratorPreflightItem(
        message: 'Base URL 不是有效 http/https 地址',
        level: ImageGeneratorPreflightLevel.error,
      ),
    );
  } else {
    items.add(
      const ImageGeneratorPreflightItem(
        message: 'Base URL 格式正常',
        level: ImageGeneratorPreflightLevel.ok,
      ),
    );
    if (!baseUri.path.contains('/v1')) {
      items.add(
        const ImageGeneratorPreflightItem(
          message: 'Base URL 未包含 /v1，请确认中转接口是否需要',
          level: ImageGeneratorPreflightLevel.warning,
        ),
      );
    }
  }

  items.add(
    ImageGeneratorPreflightItem(
      message: apiKey.isEmpty ? 'API Key 未填写' : 'API Key 已填写（不会保存）',
      level: apiKey.isEmpty
          ? ImageGeneratorPreflightLevel.error
          : ImageGeneratorPreflightLevel.ok,
    ),
  );
  items.add(
    ImageGeneratorPreflightItem(
      message: prompt.isEmpty ? 'Prompt 未填写' : 'Prompt 已填写',
      level: prompt.isEmpty
          ? ImageGeneratorPreflightLevel.error
          : ImageGeneratorPreflightLevel.ok,
    ),
  );
  items.add(
    ImageGeneratorPreflightItem(
      message: model.isEmpty ? '模型为空，将使用默认 gpt-image-1' : '模型已填写：$model',
      level: model.isEmpty
          ? ImageGeneratorPreflightLevel.warning
          : ImageGeneratorPreflightLevel.ok,
    ),
  );

  if (params.count < 1 || params.count > 4) {
    items.add(
      const ImageGeneratorPreflightItem(
        message: '数量超出 1-4，将在请求时自动限制',
        level: ImageGeneratorPreflightLevel.warning,
      ),
    );
  } else {
    items.add(
      const ImageGeneratorPreflightItem(
        message: '数量范围正常',
        level: ImageGeneratorPreflightLevel.ok,
      ),
    );
  }

  if (params.referenceImageField.shouldSend && referenceUrl.isEmpty) {
    items.add(
      const ImageGeneratorPreflightItem(
        message: '已选择参考图字段，但参考图 URL 为空',
        level: ImageGeneratorPreflightLevel.error,
      ),
    );
  } else if (!params.referenceImageField.shouldSend &&
      referenceUrl.isNotEmpty) {
    items.add(
      const ImageGeneratorPreflightItem(
        message: '参考图 URL 只会保存/预览，不会发送给接口',
        level: ImageGeneratorPreflightLevel.warning,
      ),
    );
  } else if (params.referenceImageField.shouldSend) {
    final refUri = Uri.tryParse(referenceUrl);
    if (refUri == null ||
        !refUri.hasScheme ||
        (refUri.scheme != 'http' && refUri.scheme != 'https')) {
      items.add(
        const ImageGeneratorPreflightItem(
          message: '参考图 URL 不是有效 http/https 地址',
          level: ImageGeneratorPreflightLevel.error,
        ),
      );
    } else {
      items.add(
        ImageGeneratorPreflightItem(
          message: '参考图会通过 ${params.referenceImageField.wireName} 字段发送',
          level: ImageGeneratorPreflightLevel.ok,
        ),
      );
    }
  }

  return items;
}
