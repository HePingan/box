// 凭证解析必须有终点（2026-10-01 真机事故续）。
//
// 事故形状：点 AI 读屏后界面永远停在「读屏中」，服务端**零请求** —— 流程在
// 发请求之前就挂住了。截图那条等待已经加了超时（见 quiz_capture_timeout_test），
// 但发请求前还有**第二处无界等待**：读本机存储（Keystore / SharedPreferences）。
// 它不回来，整个流程同样永远挂住。
//
// 本文件锁：解析层把任意时长收敛成「unavailable + 可读原因」，并有时间判据
// （必须很快返回，而不是断言结果就完事 —— 永不返回的 await 会让用例自己挂死）。
import 'dart:async';
import 'dart:convert';

import 'package:box/features/account/data/account_store.dart';
import 'package:box/features/account/domain/account_models.dart';
import 'package:box/features/quiz_plugin/data/quiz_vision_credentials.dart';
import 'package:box/features/quiz_plugin/data/quiz_vision_device_token_client.dart';
import 'package:box/features/quiz_plugin/data/quiz_vision_device_token_store.dart';
import 'package:box/features/quiz_plugin/domain/quiz_config.dart';
import 'package:box/features/quiz_plugin/domain/quiz_vision_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 安全存储永不回包（等价于真机上 Keystore 卡住）。
class _HangingStore implements QuizVisionDeviceTokenStore {
  @override
  Future<String?> readDeviceId() => Completer<String?>().future;

  @override
  Future<void> writeDeviceId(String value) => Completer<void>().future;

  @override
  Future<String?> readDeviceToken() => Completer<String?>().future;

  @override
  Future<void> writeDeviceToken(String value) => Completer<void>().future;

  @override
  Future<void> clearDeviceToken() => Completer<void>().future;
}

/// 账号存储永不回包（会话 / 服务器地址读不出来）。
class _HangingAccountStore extends BoxAccountStore {
  @override
  Future<BoxAccountSession?> loadSession() =>
      Completer<BoxAccountSession?>().future;

  @override
  Future<String> loadServerUrl() => Completer<String>().future;
}

/// 正常的内存存储（控制组用）。
class _MemoryStore implements QuizVisionDeviceTokenStore {
  String? deviceId;
  String? token;

  @override
  Future<String?> readDeviceId() async => deviceId;

  @override
  Future<void> writeDeviceId(String value) async => deviceId = value;

  @override
  Future<String?> readDeviceToken() async => token;

  @override
  Future<void> writeDeviceToken(String value) async => token = value;

  @override
  Future<void> clearDeviceToken() async => token = null;
}

class _EmptyAccountStore extends BoxAccountStore {
  @override
  Future<BoxAccountSession?> loadSession() async => null;

  @override
  Future<String> loadServerUrl() async => 'https://background.hpa888.top';
}

void main() {
  setUp(() {
    QuizVisionCredentialResolver.resolveTimeout = const Duration(
      milliseconds: 60,
    );
  });

  tearDown(() {
    QuizVisionCredentialResolver.resolveTimeout = const Duration(seconds: 10);
  });

  test('本机存储不回包 → 解析超时收尾，不无限等', () async {
    final resolver = QuizVisionCredentialResolver(
      store: _HangingStore(),
      accountStore: _HangingAccountStore(),
    );
    final sw = Stopwatch()..start();

    final endpoint = await resolver.resolve(const QuizConfig());

    expect(endpoint.mode, QuizVisionMode.unavailable);
    expect(endpoint.errorMessage, contains('超时'), reason: '要给可读原因');
    expect(
      sw.elapsed,
      lessThan(const Duration(seconds: 2)),
      reason: '永不返回的 await 会让界面永远停在「读屏中」',
    );
  });

  test('匿名档解析（登录档被拒后的降级路）同样受超时保护', () async {
    final resolver = QuizVisionCredentialResolver(
      store: _HangingStore(),
      accountStore: _HangingAccountStore(),
    );
    final sw = Stopwatch()..start();

    final endpoint = await resolver.resolveAnonymous(const QuizConfig());

    expect(endpoint.mode, QuizVisionMode.unavailable);
    expect(endpoint.errorMessage, contains('超时'));
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('控制组：存储正常 → 照旧签发设备令牌（超时包装没改变正常路径）', () async {
    final store = _MemoryStore();
    final resolver = QuizVisionCredentialResolver(
      store: store,
      accountStore: _EmptyAccountStore(),
      client: QuizVisionDeviceTokenClient(
        httpClient: MockClient(
          (req) async => http.Response(
            jsonEncode({'token': 'device-token-ok', 'dailyCap': 100}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      ),
    );

    final endpoint = await resolver.resolve(const QuizConfig());

    expect(endpoint.mode, QuizVisionMode.deviceProxy);
    expect(endpoint.apiKey, 'device-token-ok');
    expect(store.token, 'device-token-ok');
  });
}
