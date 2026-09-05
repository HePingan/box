import 'dart:convert';

import 'package:box/features/image_generator/data/image_generator_client.dart';
import 'package:box/features/image_generator/domain/image_generator_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('ImageGeneratorClient 注入的 httpClient 必须真正被使用', () {
    test('fetchPlatformQuota 走注入的 MockClient，而不是自建 client', () async {
      var hit = 0;
      final mock = MockClient((req) async {
        hit++;
        expect(req.url.path, '/api/image/quota');
        expect(req.headers['Authorization'], 'Bearer tok-1');
        return http.Response(
          jsonEncode({'remaining': 43, 'dailyLimit': 50, 'usedToday': 7}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final client = ImageGeneratorClient(httpClient: mock);
      final quota = await client.fetchPlatformQuota(
        platformBaseUrl: 'https://example.invalid',
        platformToken: 'tok-1',
      );

      // 若注入的 client 未被使用，请求会打真实网络：hit 保持 0 且抛异常。
      expect(hit, 1, reason: '注入的 httpClient 必须承接请求');
      expect(quota.dailyLimit, 50);
      expect(quota.remaining, 43);
      expect(quota.usedToday, 7);
    });

    test('generateWithPlatformQuota 的 POST body 经由注入 client 发出', () async {
      var hit = 0;
      final mock = MockClient((req) async {
        hit++;
        expect(req.method, 'POST');
        expect(req.headers['Content-Type'], contains('application/json'));
        final sent = jsonDecode(req.body) as Map<String, dynamic>;
        expect(sent['prompt'], 'a cat');
        return http.Response(
          jsonEncode({
            'data': [
              {'url': 'https://img.invalid/1.png'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final client = ImageGeneratorClient(httpClient: mock);
      final res = await client.generateWithPlatformQuota(
        platformBaseUrl: 'https://example.invalid/',
        params: const ImageGenerationParams(
          baseUrl: 'https://example.invalid/v1',
          apiKey: 'k',
          model: 'm',
          prompt: 'a cat',
          size: '1024x1024',
          quality: 'standard',
          outputFormat: 'png',
        ),
      );

      expect(hit, 1, reason: '注入的 httpClient 必须承接请求');
      expect(res.images.single.image, 'https://img.invalid/1.png');
    });

    test('fetchModels 用注入 client 且带 Bearer 头', () async {
      var hit = 0;
      final mock = MockClient((req) async {
        hit++;
        expect(req.url.path, endsWith('/models'));
        expect(req.headers['Authorization'], 'Bearer key-9');
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 'model-b'},
              {'id': 'model-a'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final client = ImageGeneratorClient(httpClient: mock);
      final models = await client.fetchModels(
        baseUrl: 'https://example.invalid/v1/',
        apiKey: 'key-9',
      );

      expect(hit, 1, reason: '注入的 httpClient 必须承接请求');
      expect(models, ['model-a', 'model-b'], reason: '结果应去重并排序');
    });
  });

  group('错误路径', () {
    test('非 2xx 只抛一次 ImageGeneratorException，且带 statusCode', () async {
      final mock = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'error': {'message': '额度不足'},
          }),
          429,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final client = ImageGeneratorClient(httpClient: mock);
      await expectLater(
        client.fetchPlatformQuota(
          platformBaseUrl: 'https://example.invalid',
          platformToken: 't',
        ),
        throwsA(
          isA<ImageGeneratorException>()
              .having((e) => e.statusCode, 'statusCode', 429)
              .having((e) => e.message, 'message', contains('额度不足'))
              .having((e) => e.message, 'message', contains('HTTP 429')),
        ),
      );
    });

    test('网络异常包装为 ImageGeneratorException 而非裸 SocketException', () async {
      final mock = MockClient((req) async {
        throw const _FakeNetworkFailure();
      });

      final client = ImageGeneratorClient(httpClient: mock);
      await expectLater(
        client.fetchModels(baseUrl: 'https://example.invalid', apiKey: 'k'),
        throwsA(isA<ImageGeneratorException>()),
      );
    });

    test('空 Base URL 直接报错，不发请求', () async {
      var hit = 0;
      final mock = MockClient((req) async {
        hit++;
        return http.Response('{}', 200);
      });
      final client = ImageGeneratorClient(httpClient: mock);
      await expectLater(
        client.fetchModels(baseUrl: '   ', apiKey: 'k'),
        throwsA(isA<ImageGeneratorException>()),
      );
      expect(hit, 0);
    });
  });
}

class _FakeNetworkFailure implements Exception {
  const _FakeNetworkFailure();
  @override
  String toString() => 'network down';
}
