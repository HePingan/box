import 'dart:convert';

import 'package:box/features/api_hub/data/public_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

PublicApiClient _clientReturning(Map<String, dynamic> body) {
  return PublicApiClient(
    client: MockClient((http.Request request) async {
      return http.Response(
        jsonEncode(body),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    }),
  );
}

void main() {
  test('latestRates 跳过非数值币种，不得整体抛异常', () async {
    // 真实接口偶发返回 null 或字符串（限流/字段缺失），
    // 裸 `as num` 会让整个汇率面板挂掉，而不是丢掉那一个币种。
    final client = _clientReturning(<String, dynamic>{
      'rates': <String, dynamic>{
        'CNY': 7.21,
        'EUR': null,
        'JPY': 'N/A',
        'HKD': 7.8,
      },
    });

    final rates = await client.latestRates();

    expect(rates['CNY'], closeTo(7.21, 1e-9));
    expect(rates['HKD'], closeTo(7.8, 1e-9));
    expect(
      rates.containsKey('EUR'),
      isFalse,
      reason: 'null 币种应被跳过，而不是抛异常或写入 0',
    );
    expect(
      rates.containsKey('JPY'),
      isFalse,
      reason: '字符串币种应被跳过',
    );
  });

  test('latestRates 接受整数汇率（int 也是 num）', () async {
    final client = _clientReturning(<String, dynamic>{
      'rates': <String, dynamic>{'JPY': 155},
    });

    final rates = await client.latestRates();
    expect(rates['JPY'], closeTo(155.0, 1e-9));
  });

  test('latestRates 遇到 rates 非 Map 时返回空表', () async {
    final client = _clientReturning(<String, dynamic>{'rates': 'unavailable'});
    expect(await client.latestRates(), isEmpty);
  });
}
