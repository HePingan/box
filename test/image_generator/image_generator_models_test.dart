import 'dart:convert';

import 'package:box/features/image_generator/domain/image_generator_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ImageReferencePayloadField', () {
    test('fromWireName matches enum name', () {
      expect(
        ImageReferencePayloadField.fromWireName('image'),
        ImageReferencePayloadField.image,
      );
      expect(
        ImageReferencePayloadField.fromWireName('reference_image'),
        ImageReferencePayloadField.referenceImage,
      );
      expect(
        ImageReferencePayloadField.fromWireName('input_image'),
        ImageReferencePayloadField.inputImage,
      );
    });

    test('fromWireName matches wire name', () {
      expect(
        ImageReferencePayloadField.fromWireName('image'),
        ImageReferencePayloadField.image,
      );
      expect(
        ImageReferencePayloadField.fromWireName('reference_image'),
        ImageReferencePayloadField.referenceImage,
      );
      expect(
        ImageReferencePayloadField.fromWireName('input_image'),
        ImageReferencePayloadField.inputImage,
      );
    });

    test('fromWireName falls back to none for unknown values', () {
      expect(
        ImageReferencePayloadField.fromWireName('unknown'),
        ImageReferencePayloadField.none,
      );
      expect(
        ImageReferencePayloadField.fromWireName(''),
        ImageReferencePayloadField.none,
      );
    });

    test('shouldSend is false only for none', () {
      expect(ImageReferencePayloadField.none.shouldSend, isFalse);
      expect(ImageReferencePayloadField.image.shouldSend, isTrue);
      expect(ImageReferencePayloadField.referenceImage.shouldSend, isTrue);
      expect(ImageReferencePayloadField.inputImage.shouldSend, isTrue);
    });
  });

  group('ImageGeneratorDraft', () {
    test('defaults() creates valid draft', () {
      final draft = ImageGeneratorDraft.defaults();
      expect(draft.baseUrl, 'https://api.openai.com/v1');
      expect(draft.model, 'gpt-image-1');
      expect(draft.count, 1);
      expect(draft.referenceImageUrls, isEmpty);
      expect(
        draft.referenceImageField,
        ImageReferencePayloadField.none,
      );
      expect(draft.size, '1024x1024');
    });

    test('fromJson parses full JSON correctly', () {
      final json = {
        'baseUrl': 'https://custom.com/v1',
        'platformBaseUrl': '',
        'accessMode': 'ownKey',
        'model': 'dall-e-3',
        'prompt': 'a cat',
        'negativePrompt': 'ugly',
        'referenceImageUrls': ['https://img.com/a.png', 'https://img.com/b.png'],
        'referenceImageField': 'image',
        'size': '1792x1024',
        'quality': 'hd',
        'outputFormat': 'png',
        'count': 2,
      };
      final draft = ImageGeneratorDraft.fromJson(json);
      expect(draft.baseUrl, 'https://custom.com/v1');
      expect(draft.model, 'dall-e-3');
      expect(draft.prompt, 'a cat');
      expect(draft.negativePrompt, 'ugly');
      expect(draft.referenceImageUrls, [
        'https://img.com/a.png',
        'https://img.com/b.png',
      ]);
      expect(draft.referenceImageField, ImageReferencePayloadField.image);
      expect(draft.size, '1792x1024');
      expect(draft.quality, 'hd');
      expect(draft.count, 2);
    });

    test('fromJson backward compat: single referenceImageUrl string', () {
      final json = {
        'baseUrl': 'https://api.openai.com/v1',
        'platformBaseUrl': '',
        'accessMode': 'ownKey',
        'model': 'gpt-image-1',
        'prompt': 'test',
        'negativePrompt': '',
        'referenceImageUrl': 'https://img.com/old.png',
        'referenceImageField': 'image',
        'size': '1024x1024',
        'quality': 'auto',
        'outputFormat': 'png',
        'count': 1,
      };
      final draft = ImageGeneratorDraft.fromJson(json);
      expect(draft.referenceImageUrls, ['https://img.com/old.png']);
    });

    test('fromJson backward compat: no referenceImageUrl at all', () {
      final json = {
        'baseUrl': 'https://api.openai.com/v1',
        'platformBaseUrl': '',
        'accessMode': 'ownKey',
        'model': 'gpt-image-1',
        'prompt': 'test',
        'negativePrompt': '',
        'referenceImageField': 'none',
        'size': '1024x1024',
        'quality': 'auto',
        'outputFormat': 'png',
        'count': 1,
      };
      final draft = ImageGeneratorDraft.fromJson(json);
      expect(draft.referenceImageUrls, isEmpty);
    });

    test('fromJson backward compat: empty referenceImageUrl string', () {
      final json = {
        'baseUrl': 'https://api.openai.com/v1',
        'platformBaseUrl': '',
        'accessMode': 'ownKey',
        'model': 'gpt-image-1',
        'prompt': 'test',
        'negativePrompt': '',
        'referenceImageUrl': '',
        'referenceImageField': 'none',
        'size': '1024x1024',
        'quality': 'auto',
        'outputFormat': 'png',
        'count': 1,
      };
      final draft = ImageGeneratorDraft.fromJson(json);
      expect(draft.referenceImageUrls, isEmpty);
    });

    test('fromJson missing fields use defaults', () {
      final draft = ImageGeneratorDraft.fromJson({'prompt': 'hello'});
      // Falls back to defaults
      expect(draft.baseUrl, 'https://api.openai.com/v1');
      expect(draft.model, 'gpt-image-1');
      expect(draft.prompt, 'hello');
      expect(draft.count, 1);
      expect(draft.referenceImageUrls, isEmpty);
      expect(
        draft.referenceImageField,
        ImageReferencePayloadField.none,
      );
    });

    test('toJson roundtrip preserves data', () {
      final original = ImageGeneratorDraft.fromJson({
        'baseUrl': 'https://custom.com/v1',
        'platformBaseUrl': '',
        'accessMode': 'ownKey',
        'model': 'dall-e-3',
        'prompt': 'a cat',
        'negativePrompt': 'ugly',
        'referenceImageUrls': ['https://img.com/a.png'],
        'referenceImageField': 'image',
        'size': '1792x1024',
        'quality': 'hd',
        'outputFormat': 'png',
        'count': 2,
      });
      final json = original.toJson();
      final restored = ImageGeneratorDraft.fromJson(json);
      expect(restored.baseUrl, original.baseUrl);
      expect(restored.model, original.model);
      expect(restored.prompt, original.prompt);
      expect(restored.negativePrompt, original.negativePrompt);
      expect(restored.referenceImageUrls, original.referenceImageUrls);
      expect(restored.referenceImageField, original.referenceImageField);
      expect(restored.size, original.size);
      expect(restored.quality, original.quality);
      expect(restored.outputFormat, original.outputFormat);
      expect(restored.count, original.count);
    });

    test('count clamped to 1-4', () {
      final draftLow = ImageGeneratorDraft.fromJson({
        'prompt': 'test',
        'count': 0,
      });
      expect(draftLow.count, 1);

      final draftHigh = ImageGeneratorDraft.fromJson({
        'prompt': 'test',
        'count': 10,
      });
      expect(draftHigh.count, 4);
    });
  });

  group('ImageGenerationParams', () {
    ImageGenerationParams makeParams({
      String prompt = 'a cat',
      String negativePrompt = '',
      List<String> referenceImageUrls = const [],
      ImageReferencePayloadField field = ImageReferencePayloadField.none,
      int count = 1,
      String baseUrl = 'https://api.openai.com/v1',
      String apiKey = 'sk-test',
      String model = 'gpt-image-1',
      String size = '1024x1024',
      String quality = 'auto',
      String outputFormat = 'png',
    }) {
      return ImageGenerationParams(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        prompt: prompt,
        negativePrompt: negativePrompt,
        size: size,
        quality: quality,
        outputFormat: outputFormat,
        referenceImageUrls: referenceImageUrls,
        referenceImageField: field,
        count: count,
      );
    }

    test('effectivePrompt without negative prompt', () {
      final params = makeParams(prompt: '  hello  ');
      expect(params.effectivePrompt, 'hello');
    });

    test('effectivePrompt with negative prompt', () {
      final params = makeParams(
        prompt: '  hello  ',
        negativePrompt: '  bad  ',
      );
      expect(params.effectivePrompt, 'hello\n\nNegative prompt: bad');
    });

    test('toRequestBody basic fields', () {
      final body = makeParams().toRequestBody();
      expect(body['model'], 'gpt-image-1');
      expect(body['prompt'], 'a cat');
      expect(body['size'], '1024x1024');
      expect(body['quality'], 'auto');
      expect(body['n'], 1);
      expect(body['output_format'], 'png');
      expect(body.containsKey('image'), isFalse);
      expect(body.containsKey('reference_image'), isFalse);
    });

    test('toRequestBody single reference URL sends as String', () {
      final body = makeParams(
        referenceImageUrls: ['https://img.com/ref.png'],
        field: ImageReferencePayloadField.image,
      ).toRequestBody();
      expect(body['image'], 'https://img.com/ref.png');
      expect(body['image'] is String, isTrue);
    });

    test('toRequestBody multiple reference URLs sends as List', () {
      final body = makeParams(
        referenceImageUrls: [
          'https://img.com/a.png',
          'https://img.com/b.png',
        ],
        field: ImageReferencePayloadField.referenceImage,
      ).toRequestBody();
      expect(body['reference_image'], isA<List>());
      expect(
        (body['reference_image'] as List).length,
        2,
      );
    });

    test('toRequestBody field=none skips URLs even if non-empty', () {
      final body = makeParams(
        referenceImageUrls: ['https://img.com/ref.png'],
        field: ImageReferencePayloadField.none,
      ).toRequestBody();
      expect(body.containsKey('image'), isFalse);
      expect(body.containsKey('reference_image'), isFalse);
    });

    test('toRequestBody empty URLs are filtered out', () {
      final body = makeParams(
        referenceImageUrls: ['', '   ', 'https://img.com/real.png'],
        field: ImageReferencePayloadField.image,
      ).toRequestBody();
      expect(body['image'], 'https://img.com/real.png');
    });

    test('normalizedBaseUrl removes trailing slashes', () {
      final params = makeParams(baseUrl: 'https://api.openai.com/v1///');
      expect(params.normalizedBaseUrl, 'https://api.openai.com/v1');
    });

    test('normalizedBaseUrl defaults to OpenAI', () {
      final params = makeParams(baseUrl: '');
      expect(params.normalizedBaseUrl, 'https://api.openai.com/v1');
    });

    test('endpoint constructed correctly', () {
      final params = makeParams(
        baseUrl: 'https://custom.com/v1',
      );
      expect(params.endpoint, 'https://custom.com/v1/images/generations');
    });

    test('count clamped 1-4 in request body', () {
      final bodyLow = makeParams(count: 0).toRequestBody();
      expect(bodyLow['n'], 1);

      final bodyHigh = makeParams(count: 10).toRequestBody();
      expect(bodyHigh['n'], 4);
    });

    test('prettyRequestJson produces valid JSON', () {
      final params = makeParams();
      final json = params.prettyRequestJson;
      expect(() => jsonDecode(json), returnsNormally);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['prompt'], 'a cat');
    });
  });

  group('ImagePlatformQuota', () {
    test('fromJson parses standard fields', () {
      final quota = ImagePlatformQuota.fromJson({
        'remaining': 42,
        'dailyLimit': 100,
        'usedToday': 58,
        'status': 'normal',
        'message': '',
      });
      expect(quota.remaining, 42);
      expect(quota.dailyLimit, 100);
      expect(quota.usedToday, 58);
      expect(quota.status, 'normal');
      expect(quota.hasQuota, isTrue);
    });

    test('fromJson handles alternate key names', () {
      final quota = ImagePlatformQuota.fromJson({
        'remainingQuota': 10,
        'dailyQuota': 50,
        'dailyUsed': 40,
        'quota': 99,
      });
      expect(quota.remaining, 10);
      expect(quota.dailyLimit, 50);
      expect(quota.usedToday, 40);
    });

    test('hasQuota false when remaining is 0', () {
      final quota = ImagePlatformQuota.fromJson({'remaining': 0});
      expect(quota.hasQuota, isFalse);
    });

    test('hasQuota true when remaining > 0', () {
      final quota = ImagePlatformQuota.fromJson({'remaining': 1});
      expect(quota.hasQuota, isTrue);
    });

    test('fromJson missing fields default to 0', () {
      final quota = ImagePlatformQuota.fromJson({});
      expect(quota.remaining, 0);
      expect(quota.dailyLimit, 0);
      expect(quota.usedToday, 0);
      expect(quota.status, 'normal');
    });
  });

  group('GeneratedImageResult', () {
    test('isDataUrl true for data URIs', () {
      const result = GeneratedImageResult(
        image: 'data:image/png;base64,iVBORw0KGgo=',
      );
      expect(result.isDataUrl, isTrue);
    });

    test('isDataUrl false for regular URLs', () {
      const result = GeneratedImageResult(
        image: 'https://cdn.example.com/image.png',
      );
      expect(result.isDataUrl, isFalse);
    });
  });

  group('ImageGenerationResponse', () {
    test('constructor sets fields', () {
      const result = GeneratedImageResult(image: 'https://img.com/a.png');
      const response = ImageGenerationResponse(
        images: [result],
        rawPreview: 'preview text',
      );
      expect(response.images.length, 1);
      expect(response.images.first.image, 'https://img.com/a.png');
      expect(response.rawPreview, 'preview text');
    });
  });

  group('ImageGeneratorRequestDiagnostics', () {
    test('statusLabel returns correct labels', () {
      final success = ImageGeneratorRequestDiagnostics(
        createdAt: DateTime(2025, 1, 1),
        endpoint: 'https://api.com/v1/images/generations',
        requestJson: '{}',
        referenceField: ImageReferencePayloadField.none,
        success: true,
      );
      expect(success.statusLabel, '请求成功');

      final failureNoCode = ImageGeneratorRequestDiagnostics(
        createdAt: DateTime(2025, 1, 1),
        endpoint: 'https://api.com/v1/images/generations',
        requestJson: '{}',
        referenceField: ImageReferencePayloadField.none,
        success: false,
      );
      expect(failureNoCode.statusLabel, '请求失败');

      final failureWithCode = ImageGeneratorRequestDiagnostics(
        createdAt: DateTime(2025, 1, 1),
        endpoint: 'https://api.com/v1/images/generations',
        requestJson: '{}',
        referenceField: ImageReferencePayloadField.none,
        success: false,
        statusCode: 429,
      );
      expect(failureWithCode.statusLabel, '请求失败 HTTP 429');
    });

    test('timeLabel formats time with leading zeros', () {
      final diag = ImageGeneratorRequestDiagnostics(
        createdAt: DateTime(2025, 1, 1, 8, 5, 3),
        endpoint: '',
        requestJson: '{}',
        referenceField: ImageReferencePayloadField.none,
        success: true,
      );
      expect(diag.timeLabel, '08:05:03');
    });

    test('referenceLabel returns wire name or "不发送"', () {
      final none = ImageGeneratorRequestDiagnostics(
        createdAt: DateTime(2025, 1, 1),
        endpoint: '',
        requestJson: '{}',
        referenceField: ImageReferencePayloadField.none,
        success: true,
      );
      expect(none.referenceLabel, '不发送');

      final withField = ImageGeneratorRequestDiagnostics(
        createdAt: DateTime(2025, 1, 1),
        endpoint: '',
        requestJson: '{}',
        referenceField: ImageReferencePayloadField.referenceImage,
        success: true,
      );
      expect(withField.referenceLabel, 'reference_image');
    });
  });

  group('ImageGenerationHistoryItem', () {
    ImageGenerationHistoryItem makeItem({
      List<String> referenceImageUrls = const [],
    }) {
      return ImageGenerationHistoryItem(
        prompt: 'test',
        negativePrompt: '',
        referenceImageUrls: referenceImageUrls,
        referenceImageField: ImageReferencePayloadField.none,
        model: 'gpt-image-1',
        size: '1024x1024',
        quality: 'auto',
        outputFormat: 'png',
        createdAt: DateTime(2025, 6, 20, 10, 30, 0),
        images: const ['https://cdn.com/img.png'],
      );
    }

    test('fromJson parses full item', () {
      final json = {
        'prompt': 'a cat',
        'negativePrompt': '',
        'referenceImageUrls': ['https://img.com/ref.png'],
        'referenceImageField': 'image',
        'model': 'gpt-image-1',
        'size': '1024x1024',
        'quality': 'auto',
        'outputFormat': 'png',
        'createdAt': '2025-06-20T10:30:00.000',
        'images': ['https://cdn.com/img.png'],
      };
      final item = ImageGenerationHistoryItem.fromJson(json);
      expect(item.prompt, 'a cat');
      expect(item.referenceImageUrls, ['https://img.com/ref.png']);
      expect(item.images, ['https://cdn.com/img.png']);
    });

    test('fromJson backward compat with single referenceImageUrl', () {
      final json = {
        'prompt': 'test',
        'negativePrompt': '',
        'referenceImageUrl': 'https://img.com/old.png',
        'referenceImageField': 'none',
        'model': 'gpt-image-1',
        'size': '1024x1024',
        'quality': 'auto',
        'outputFormat': 'png',
        'createdAt': '2025-06-20T10:30:00.000',
        'images': ['https://cdn.com/img.png'],
      };
      final item = ImageGenerationHistoryItem.fromJson(json);
      expect(item.referenceImageUrls, ['https://img.com/old.png']);
    });

    test('toJson roundtrip preserves data', () {
      final original = makeItem(
        referenceImageUrls: ['https://img.com/a.png', 'https://img.com/b.png'],
      );
      final json = original.toJson();
      final restored = ImageGenerationHistoryItem.fromJson(json);
      expect(restored.prompt, original.prompt);
      expect(restored.referenceImageUrls, original.referenceImageUrls);
      expect(restored.images, original.images);
    });

    test('toJsonString produces valid JSON', () {
      final item = makeItem();
      final jsonString = item.toJsonString();
      expect(() => jsonDecode(jsonString), returnsNormally);
    });

    test('multiple reference images in history roundtrip', () {
      final urls = [
        'https://img.com/ref1.png',
        'https://img.com/ref2.png',
        'https://img.com/ref3.png',
      ];
      final original = makeItem(referenceImageUrls: urls);
      final json = original.toJson();
      final restored = ImageGenerationHistoryItem.fromJson(json);
      expect(restored.referenceImageUrls, urls);
    });

    test('hasImages returns true when images are not empty', () {
      final item = makeItem();
      expect(item.hasImages, isTrue);
    });

    test('hasImages returns false when images empty', () {
      final item = ImageGenerationHistoryItem(
        prompt: 'test',
        negativePrompt: '',
        referenceImageUrls: [],
        referenceImageField: ImageReferencePayloadField.none,
        model: 'gpt-image-1',
        size: '1024x1024',
        quality: 'auto',
        outputFormat: 'png',
        createdAt: DateTime(2025, 6, 20, 10, 30, 0),
        images: const [],
      );
      expect(item.hasImages, isFalse);
    });
  });
}
