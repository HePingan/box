import 'dart:convert';

import 'package:box/features/api_hub/presentation/api_hub_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 按 host 决定延迟：天气慢、IP 快，制造「后发先至」。
MockClient _racingClient({
  required Duration weatherDelay,
  required Duration ipDelay,
  bool weatherFails = false,
}) {
  return MockClient((http.Request request) async {
    final host = request.url.host;

    if (host.contains('open-meteo')) {
      await Future<void>.delayed(weatherDelay);
      if (weatherFails) {
        return http.Response('boom-weather', 500);
      }
      return http.Response(
        jsonEncode(<String, dynamic>{
          'daily': <String, dynamic>{
            'time': <String>['2026-07-12', '2026-07-13', '2026-07-14'],
            'temperature_2m_max': <double>[31.0, 32.0, 33.0],
            'temperature_2m_min': <double>[24.0, 25.0, 26.0],
            'precipitation_sum': <double>[0.0, 1.0, 2.0],
            'weathercode': <int>[0, 1, 2],
          },
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    }

    // IP 工具
    await Future<void>.delayed(ipDelay);
    return http.Response(
      jsonEncode(<String, dynamic>{
        'ip': '203.0.113.9',
        'city': 'Shanghai',
        'country_name': 'China',
        'org': 'TestNet',
        'timezone': 'Asia/Shanghai',
      }),
      200,
      headers: <String, String>{'content-type': 'application/json'},
    );
  });
}

Future<void> _pumpMany(WidgetTester tester, {int times = 14}) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('慢的天气请求失败后，不得把错误写到已切换的 IP 工具上', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ApiHubPage(
          initialTool: 'weather',
          httpClientForTesting: _racingClient(
            weatherDelay: const Duration(milliseconds: 700),
            ipDelay: const Duration(milliseconds: 50),
            weatherFails: true,
          ),
        ),
      ),
    );

    // 天气请求已发出（700ms 后才失败）。
    await tester.pump(const Duration(milliseconds: 50));

    // 用户切到 IP 工具：它 50ms 就成功返回。
    final dynamic state = tester.state(find.byType(ApiHubPage));
    // ignore: avoid_dynamic_calls
    state.switchToolForTesting('ip');

    await _pumpMany(tester);

    // ignore: avoid_dynamic_calls
    final String? errorNow = state.errorForTesting as String?;
    expect(
      errorNow,
      isNull,
      reason: '过期的天气请求失败不得把错误写到当前 IP 工具（旧请求错误串台）',
    );

    // ignore: avoid_dynamic_calls
    final bool loadingNow = state.loadingForTesting as bool;
    expect(loadingNow, isFalse, reason: 'IP 请求已完成，spinner 必须停止');
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('过期请求的收尾不得复位新请求的加载态', (tester) async {
    // 天气很慢(700ms)且失败；IP 更慢(1200ms)。切到 IP 后天气才收尾，
    // 若 finally 不判过期，它会把 IP 请求正在进行的 _loading 复位成 false，
    // 界面上 spinner 提前消失、却什么内容都没有。
    await tester.pumpWidget(
      MaterialApp(
        home: ApiHubPage(
          initialTool: 'weather',
          httpClientForTesting: _racingClient(
            weatherDelay: const Duration(milliseconds: 700),
            ipDelay: const Duration(milliseconds: 1200),
            weatherFails: true,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 50));

    final dynamic state = tester.state(find.byType(ApiHubPage));
    // ignore: avoid_dynamic_calls
    state.switchToolForTesting('ip');

    // 推进到 800ms：天气(700ms)已收尾，IP(1200ms)仍在途。
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // ignore: avoid_dynamic_calls
    expect(
      state.loadingForTesting as bool,
      isTrue,
      reason: '过期的天气请求收尾不得把仍在途的 IP 请求的加载态复位',
    );
    // ignore: avoid_dynamic_calls
    expect(
      state.errorForTesting as String?,
      isNull,
      reason: '过期天气请求的失败不得写进当前工具的错误态',
    );

    // 再推进到 IP 返回，加载态应正常收尾。
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // ignore: avoid_dynamic_calls
    expect(
      state.loadingForTesting as bool,
      isFalse,
      reason: 'IP 请求返回后加载态必须收尾',
    );
  }, timeout: const Timeout(Duration(seconds: 45)));
}
