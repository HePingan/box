// AI 读屏凭证分流回归（方案 A：服务端代理 + 匿名设备令牌）。
//
// 背景：内置 key 曾烧死在 APK 里，newapi 渠道 key 随时可能被吊销（v270 事故：
// 全体用户读屏「等待超时」，只能发版救）。本轮把客户端内置 key **彻底删除**，
// 未登录用户改走服务端签发的匿名设备令牌，分流规则（domain 单一入口）：
//   ① 手填 key 或端点 → 老逻辑原样直连（ownKey，绝不动、绝不改道）；
//   ② 全空 + 已登录 → 平台代理：base=账号服务器+/api/quiz/vision，Bearer=session token；
//   ③ 全空 + 未登录 → 同一条代理：Bearer=服务端签发的匿名设备令牌（deviceProxy）；
//   ④ 都没有 → unavailable + 可读原因（**绝不回落内置 key，也绝不静默失败**）。
import 'package:box/features/quiz_plugin/domain/quiz_config.dart';
import 'package:box/features/quiz_plugin/domain/quiz_vision_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';

const _server = 'https://background.hpa888.top';
const _proxyBase = 'https://background.hpa888.top/api/quiz/vision';

void main() {
  group('resolveQuizVisionEndpoint 凭证分流（零内置密钥）', () {
    test('① 手填 key → ownKey 直连默认端点（控制组：用户凭证照旧，不因代理改道）', () {
      final r = resolveQuizVisionEndpoint(
        const QuizConfig(apiKey: 'sk-user-self-key'),
        serverUrl: _server,
        sessionToken: 'sess-token-abc123',
        deviceToken: 'device-token-abc123',
      );
      expect(r.mode, QuizVisionMode.ownKey);
      expect(r.apiKey, 'sk-user-self-key');
      expect(r.baseUrl, defaultVisionApiUrl);
      expect(r.viaProxy, isFalse);
    });

    test('② 手填端点无 key → ownKey 用用户端点、key 留空（零内置密钥，且不改道代理）', () {
      final r = resolveQuizVisionEndpoint(
        const QuizConfig(apiUrl: 'https://my.example.com/v1'),
        serverUrl: _server,
        sessionToken: 'sess-token-abc123',
        deviceToken: 'device-token-abc123',
      );
      expect(r.mode, QuizVisionMode.ownKey);
      expect(r.baseUrl, 'https://my.example.com/v1');
      expect(
        r.apiKey,
        isEmpty,
        reason: '用户没填 key 就没有 key：内置密钥已删除，也不许悄悄改道到平台代理',
      );
      expect(r.baseUrl, isNot(contains(QuizVisionEndpoint.proxyPathSegment)));
    });

    test('③ 全空 + 已登录 → 平台代理，Bearer=session token', () {
      final r = resolveQuizVisionEndpoint(
        const QuizConfig(),
        serverUrl: _server,
        sessionToken: 'sess-token-abc123',
        deviceToken: 'device-token-abc123',
      );
      expect(r.mode, QuizVisionMode.platformProxy);
      expect(r.baseUrl, _proxyBase);
      expect(r.apiKey, 'sess-token-abc123', reason: '已登录优先用登录凭证，设备令牌不参与');
      expect(r.viaProxy, isTrue);
    });

    test('④ 全空 + 未登录 + 已签发设备令牌 → 平台代理，Bearer=设备令牌', () {
      final r = resolveQuizVisionEndpoint(
        const QuizConfig(),
        serverUrl: _server,
        deviceToken: 'device-token-abc123',
      );
      expect(r.mode, QuizVisionMode.deviceProxy);
      expect(
        r.baseUrl,
        _proxyBase,
        reason: '未登录与已登录走**同一条**代理路由，只是 Bearer 不同',
      );
      expect(r.apiKey, 'device-token-abc123');
      expect(r.viaProxy, isTrue);
    });

    test('⑤ 全空 + 无 session 无设备令牌 → unavailable + 可读原因（不静默、不回落）', () {
      final r = resolveQuizVisionEndpoint(const QuizConfig(), serverUrl: _server);
      expect(r.mode, QuizVisionMode.unavailable);
      expect(r.isUnavailable, isTrue);
      expect(r.errorMessage, isNotEmpty, reason: '必须给出可读原因，不能空手退回「未搜到答案」');
      expect(r.baseUrl, isEmpty, reason: '不可用档不得带着端点出去发请求');
      expect(r.apiKey, isEmpty);
    });

    test('⑥ 未登录且账号服务器地址缺失 → unavailable，不给半截 URL', () {
      final r = resolveQuizVisionEndpoint(
        const QuizConfig(),
        serverUrl: '   ',
        deviceToken: 'device-token-abc123',
      );
      expect(r.mode, QuizVisionMode.unavailable);
      expect(r.errorMessage, contains('服务器地址'));
      expect(r.baseUrl, isEmpty);
    });

    test('⑦ 未登录 + 手填端点 → 仍 ownKey（控制组反向：绝不因未登录改道）', () {
      final r = resolveQuizVisionEndpoint(
        const QuizConfig(apiUrl: 'https://my.example.com/v1'),
        serverUrl: '',
      );
      expect(r.mode, QuizVisionMode.ownKey);
      expect(r.baseUrl, 'https://my.example.com/v1');
    });

    test('⑧ 服务器地址末尾斜杠被归一（不产生 //api/quiz/vision）', () {
      final r = resolveQuizVisionEndpoint(
        const QuizConfig(),
        serverUrl: '$_server/',
        deviceToken: 'device-token-abc123',
      );
      expect(r.baseUrl, _proxyBase);
    });
  });

  group('visionHttpErrorText 代理模式专属文案', () {
    test('429（代理）→ 今日次数用完提示', () {
      final t = visionHttpErrorText(429, viaProxy: true);
      expect(t, contains('今日'));
      expect(t, contains('次数'));
    });

    test('401（代理）→ 与设备令牌自愈判定同源（单一常量，防两处字面量漂移）', () {
      expect(
        visionHttpErrorText(401, viaProxy: true),
        visionProxyCredentialExpiredText,
      );
      expect(visionProxyCredentialExpiredText, contains('登录'));
    });

    test('403（代理）→ 提示代理不可用', () {
      expect(visionHttpErrorText(403, viaProxy: true), contains('代理'));
    });

    test('401（直连）→ 保留旧「鉴权不稳」口径', () {
      final t = visionHttpErrorText(401, viaProxy: false);
      expect(t, contains('鉴权不稳'));
    });

    test('400 → 通用返回码口径不变', () {
      expect(visionHttpErrorText(400, viaProxy: true), contains('400'));
    });
  });
}
