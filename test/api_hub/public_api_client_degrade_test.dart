import 'dart:convert';

import 'package:box/features/api_hub/data/public_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 这些用例只针对「服务端返回畸形数据」时的降级行为：
/// 免费公开接口经常缺字段、给 null、把数字返回成字符串，
/// 客户端必须跳过坏字段而不是整体抛异常。
void main() {
  PublicApiClient clientReturning(Object? body, {int status = 200}) {
    return PublicApiClient(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(body),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
  }

  group('convertCurrency', () {
    test('同币种直接返回原额，不发请求', () async {
      var called = false;
      final client = PublicApiClient(
        client: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );

      final result = await client.convertCurrency(
        amount: 12.5,
        from: 'cny',
        to: 'CNY',
      );

      expect(result, 12.5);
      expect(called, isFalse, reason: '同币种换算无需网络往返');
    });

    test('目标币种缺失时返回 null 而不是抛异常', () async {
      final client = clientReturning({
        'rates': {'JPY': 20.0},
      });

      final result = await client.convertCurrency(
        amount: 1,
        from: 'CNY',
        to: 'USD',
      );

      expect(result, isNull);
    });

    test('目标币种是字符串时返回 null', () async {
      final client = clientReturning({
        'rates': {'USD': '0.14'},
      });

      final result = await client.convertCurrency(
        amount: 1,
        from: 'CNY',
        to: 'USD',
      );

      expect(result, isNull);
    });

    test('正常返回时取到目标币种数值', () async {
      final client = clientReturning({
        'rates': {'USD': 0.14},
      });

      final result = await client.convertCurrency(
        amount: 1,
        from: 'CNY',
        to: 'USD',
      );

      expect(result, closeTo(0.14, 1e-9));
    });
  });

  group('publicHolidays', () {
    test('返回非列表时降级为空列表', () async {
      final client = clientReturning({'error': 'boom'});

      expect(await client.publicHolidays(year: 2026), isEmpty);
    });

    test('列表中的非 Map 元素被跳过', () async {
      final client = clientReturning([
        'garbage',
        42,
        {'date': '2026-01-01', 'localName': '元旦', 'name': "New Year's Day"},
      ]);

      final result = await client.publicHolidays(year: 2026);

      expect(result, hasLength(1));
      expect(result.single.date, '2026-01-01');
      expect(result.single.localName, '元旦');
    });

    test('缺字段时降级为空串，countryCode 回落到请求值', () async {
      final client = clientReturning([
        {'date': '2026-05-01'},
      ]);

      final result = await client.publicHolidays(year: 2026, countryCode: 'jp');

      expect(result.single.date, '2026-05-01');
      expect(result.single.localName, '');
      expect(result.single.name, '');
      expect(result.single.countryCode, 'JP');
    });
  });

  group('weatherForecast', () {
    test('daily 整段缺失时仍返回结果，daily 为空', () async {
      final client = clientReturning({'latitude': 30.0, 'longitude': 120.0});

      final result = await client.weatherForecast(latitude: 30, longitude: 120);

      expect(result.daily, isEmpty);
      expect(result.currentTemperature, isNull);
      expect(result.currentWindSpeed, isNull);
    });

    test('温度数组比日期数组短时，缺的那天温度为 null 而不越界', () async {
      final client = clientReturning({
        'daily': {
          'time': ['2026-01-01', '2026-01-02', '2026-01-03'],
          'temperature_2m_max': [10.0],
          'temperature_2m_min': [1.0, 2.0],
          'weather_code': [0],
        },
      });

      final result = await client.weatherForecast(latitude: 30, longitude: 120);

      expect(result.daily, hasLength(3));
      expect(result.daily[0].maxTemperature, 10.0);
      expect(result.daily[1].maxTemperature, isNull);
      expect(result.daily[1].minTemperature, 2.0);
      expect(result.daily[2].minTemperature, isNull);
      expect(result.daily[2].weatherCode, isNull);
    });

    test('经纬度缺失时回落到请求参数', () async {
      final client = clientReturning({'timezone': 'Asia/Shanghai'});

      final result = await client.weatherForecast(
        latitude: 31.2304,
        longitude: 121.4737,
      );

      expect(result.latitude, closeTo(31.2304, 1e-6));
      expect(result.longitude, closeTo(121.4737, 1e-6));
      expect(result.timezone, 'Asia/Shanghai');
    });

    test('daily 超过 7 天时截断到 7 条', () async {
      final days = List.generate(
        12,
        (i) => '2026-01-${(i + 1).toString().padLeft(2, '0')}',
      );
      final client = clientReturning({
        'daily': {
          'time': days,
          'temperature_2m_max': List.filled(12, 10.0),
          'temperature_2m_min': List.filled(12, 1.0),
          'weather_code': List.filled(12, 0),
        },
      });

      final result = await client.weatherForecast(latitude: 30, longitude: 120);

      expect(result.daily, hasLength(7));
    });

    test('forecast_days 被夹在 1..7 之间', () async {
      final captured = <Uri>[];
      final client = PublicApiClient(
        client: MockClient((req) async {
          captured.add(req.url);
          return http.Response(
            '{}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await client.weatherForecast(latitude: 30, longitude: 120, days: 99);
      await client.weatherForecast(latitude: 30, longitude: 120, days: 0);

      expect(captured[0].queryParameters['forecast_days'], '7');
      expect(captured[1].queryParameters['forecast_days'], '1');
    });
  });

  group('dictionaryLookup', () {
    test('空关键词直接返回 null，不发请求', () async {
      var called = false;
      final client = PublicApiClient(
        client: MockClient((_) async {
          called = true;
          return http.Response('[]', 200);
        }),
      );

      expect(await client.dictionaryLookup('   '), isNull);
      expect(called, isFalse);
    });

    test('返回空列表时降级为 null', () async {
      final client = clientReturning(const []);

      expect(await client.dictionaryLookup('word'), isNull);
    });

    test('首元素非 Map 时降级为 null', () async {
      final client = clientReturning(const ['nope']);

      expect(await client.dictionaryLookup('word'), isNull);
    });

    test('word 缺失时回落到查询关键词', () async {
      final client = clientReturning([
        {'phonetic': '/tɛst/'},
      ]);

      final result = await client.dictionaryLookup('test');

      expect(result, isNotNull);
      expect(result!.word, 'test');
      expect(result.phonetic, '/tɛst/');
    });
  });
}
