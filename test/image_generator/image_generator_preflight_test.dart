import 'package:box/features/image_generator/domain/image_generator_models.dart';
import 'package:box/features/image_generator/domain/image_generator_preflight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ImageGenerationParams makeParams({
    String baseUrl = 'https://api.openai.com/v1',
    String apiKey = 'sk-test',
    String model = 'gpt-image-1',
    String prompt = 'a cat',
    List<String> referenceImageUrls = const [],
    ImageReferencePayloadField field = ImageReferencePayloadField.none,
    int count = 1,
  }) {
    return ImageGenerationParams(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      prompt: prompt,
      size: '1024x1024',
      quality: 'auto',
      outputFormat: 'png',
      referenceImageUrls: referenceImageUrls,
      referenceImageField: field,
      count: count,
    );
  }

  group('Base URL validation', () {
    test('valid base URL reports ok', () {
      final items = buildImageGeneratorPreflight(makeParams());
      expect(items.any((i) => i.message.contains('格式正常')), isTrue);
    });

    test('invalid base URL reports error', () {
      final items = buildImageGeneratorPreflight(
        makeParams(baseUrl: 'not-a-valid-url'),
      );
      expect(items.any((i) => i.level == ImageGeneratorPreflightLevel.error),
          isTrue);
    });

    test('missing /v1 in path warns', () {
      final items = buildImageGeneratorPreflight(
        makeParams(baseUrl: 'https://custom.com'),
      );
      expect(
        items.any((i) => i.message.contains('未包含 /v1')),
        isTrue,
      );
    });
  });

  group('API Key validation', () {
    test('empty API key reports error', () {
      final items = buildImageGeneratorPreflight(makeParams(apiKey: ''));
      expect(
        items.any(
          (i) =>
              i.level == ImageGeneratorPreflightLevel.error &&
              i.message.contains('API Key'),
        ),
        isTrue,
      );
    });

    test('non-empty API key reports ok', () {
      final items = buildImageGeneratorPreflight(makeParams(apiKey: 'sk-xxx'));
      expect(items.any((i) => i.message.contains('已填写')), isTrue);
    });
  });

  group('Prompt validation', () {
    test('empty prompt reports error', () {
      final items = buildImageGeneratorPreflight(makeParams(prompt: ''));
      expect(
        items.any(
          (i) =>
              i.level == ImageGeneratorPreflightLevel.error &&
              i.message.contains('Prompt'),
        ),
        isTrue,
      );
    });

    test('non-empty prompt reports ok', () {
      final items = buildImageGeneratorPreflight(
        makeParams(prompt: 'hello world'),
      );
      expect(items.any((i) => i.message.contains('Prompt 已填写')), isTrue);
    });
  });

  group('Model validation', () {
    test('empty model warns about default', () {
      final items = buildImageGeneratorPreflight(makeParams(model: ''));
      expect(
        items.any(
          (i) =>
              i.level == ImageGeneratorPreflightLevel.warning &&
              i.message.contains('默认'),
        ),
        isTrue,
      );
    });
  });

  group('Count validation', () {
    test('count out of range warns', () {
      final items = buildImageGeneratorPreflight(makeParams(count: 10));
      expect(
        items.any(
          (i) =>
              i.level == ImageGeneratorPreflightLevel.warning &&
              i.message.contains('数量'),
        ),
        isTrue,
      );
    });

    test('count 0 warns', () {
      final items = buildImageGeneratorPreflight(makeParams(count: 0));
      expect(
        items.any(
          (i) =>
              i.level == ImageGeneratorPreflightLevel.warning &&
              i.message.contains('数量'),
        ),
        isTrue,
      );
    });

    test('valid count reports ok', () {
      final items = buildImageGeneratorPreflight(makeParams(count: 2));
      expect(items.any((i) => i.message.contains('数量范围正常')), isTrue);
    });
  });

  group('Reference image validation', () {
    test('field=none with empty URLs: nothing mentioned', () {
      final items = buildImageGeneratorPreflight(makeParams());
      expect(items.any((i) => i.message.contains('参考图')), isFalse);
    });

    test('field=image with empty URLs warns about auto-switch', () {
      final items = buildImageGeneratorPreflight(
        makeParams(
          field: ImageReferencePayloadField.image,
          referenceImageUrls: [],
        ),
      );
      expect(
        items.any(
          (i) =>
              i.level == ImageGeneratorPreflightLevel.warning &&
              i.message.contains('自动切'),
        ),
        isTrue,
      );
    });

    test('field=none with non-empty URLs warns about not sending', () {
      final items = buildImageGeneratorPreflight(
        makeParams(
          field: ImageReferencePayloadField.none,
          referenceImageUrls: ['https://img.com/a.png'],
        ),
      );
      expect(
        items.any(
          (i) =>
              i.level == ImageGeneratorPreflightLevel.warning &&
              i.message.contains('不会发送'),
        ),
        isTrue,
      );
    });

    test('field=image with valid URLs reports ok with count', () {
      final items = buildImageGeneratorPreflight(
        makeParams(
          field: ImageReferencePayloadField.image,
          referenceImageUrls: [
            'https://img.com/a.png',
            'https://img.com/b.png',
          ],
        ),
      );
      expect(
        items.any(
          (i) =>
              i.level == ImageGeneratorPreflightLevel.ok &&
              i.message.contains('2 张参考图') &&
              i.message.contains('image'),
        ),
        isTrue,
      );
    });

    test('invalid URL in reference image reports error', () {
      final items = buildImageGeneratorPreflight(
        makeParams(
          field: ImageReferencePayloadField.image,
          referenceImageUrls: ['not-a-valid-url'],
        ),
      );
      expect(
        items.any(
          (i) =>
              i.level == ImageGeneratorPreflightLevel.error &&
              i.message.contains('参考图 URL'),
        ),
        isTrue,
      );
    });
  });
}
