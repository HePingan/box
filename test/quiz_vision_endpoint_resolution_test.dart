// AI 读屏端点解析回归（方案 A：服务端代理）。
//
// 背景：内置 key 烧死在 APK 里，newapi 渠道 key 随时可能被吊销（v270 事故：
// 全体用户读屏「等待超时」）。方案 A 落地后解析规则：
//   1. 用户手填 key（或手填端点）→ 老逻辑原样直连（ownKey，绝不动）；
//   2. 全空 + 已登录 → 平台代理：base=账号服务器 + /api/quiz/vision，
//      apiKey=登录 session token（服务器持真 key 转发，客户端零 key）；
//   3. 全空 + 未登录（或代理被关）→ 内置兜底 key 直连（降级，保开箱即用）。
import 'package:box/features/account/domain/account_models.dart';
import 'package:box/features/quiz_plugin/domain/quiz_vision_endpoint.dart';
import 'package:box/features/quiz_plugin/presentation/quiz_plugin_entry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/quiz_plugin/domain/quiz_config.dart';

BoxAccountSession _session() => const BoxAccountSession(
      serverUrl: 'https://background.hpa888.top',
      token: 'sess-token-abc123',
      user: BoxAccountUser(
        id: 'u1',
        username: 'tester',
        role: 'user',
        status: 'active',
      ),
    );

void main() {
  group('QuizPluginEntry.resolveVisionEndpoint 模式分流', () {
    test('① 手填 key → ownKey 直连，token 不参与', () {
      final r = QuizPluginEntry.resolveVisionEndpoint(
        const QuizConfig(apiKey: 'sk-user-key'),
        session: _session(),
      );
      expect(r.mode, QuizVisionMode.ownKey);
      expect(r.apiKey, 'sk-user-key');
      expect(r.baseUrl, QuizPluginEntry.defaultVisionApiUrl);
    });

    test('② 手填端点无 key → 直连 + 内置兜底 key（老逻辑原样）', () {
      final r = QuizPluginEntry.resolveVisionEndpoint(
        const QuizConfig(apiUrl: 'https://my.example.com/v1'),
        session: _session(),
      );
      expect(r.mode, QuizVisionMode.ownKey);
      expect(r.baseUrl, 'https://my.example.com/v1');
      expect(r.apiKey, QuizPluginEntry.defaultVisionApiKey);
    });

    test('③ 全空 + 已登录 → 平台代理：base=serverUrl+/api/quiz/vision，apiKey=session token', () {
      final r = QuizPluginEntry.resolveVisionEndpoint(
        const QuizConfig(),
        session: _session(),
      );
      expect(r.mode, QuizVisionMode.platformProxy);
      expect(r.baseUrl, 'https://background.hpa888.top/api/quiz/vision');
      expect(r.apiKey, 'sess-token-abc123');
    });

    test('④ 全空 + 未登录 → 降级：内置兜底 key 直连', () {
      final r = QuizPluginEntry.resolveVisionEndpoint(
        const QuizConfig(),
        session: null,
      );
      expect(r.mode, QuizVisionMode.ownKey);
      expect(r.baseUrl, QuizPluginEntry.defaultVisionApiUrl);
      expect(r.apiKey, QuizPluginEntry.defaultVisionApiKey);
    });

    test('⑤ proxyAvailable=false（服务端开关关/旧服务端）→ 降级内置直连', () {
      final r = QuizPluginEntry.resolveVisionEndpoint(
        const QuizConfig(),
        session: _session(),
        proxyAvailable: false,
      );
      expect(r.mode, QuizVisionMode.ownKey);
      expect(r.apiKey, QuizPluginEntry.defaultVisionApiKey);
    });
  });

  group('visionHttpErrorText 代理模式专属文案', () {
    test('429（代理）→ 今日次数用完提示', () {
      final t = visionHttpErrorText(429, viaProxy: true);
      expect(t, contains('今日'));
      expect(t, contains('次数'));
    });
    test('401（代理）→ 提示重新登录', () {
      final t = visionHttpErrorText(401, viaProxy: true);
      expect(t, contains('登录'));
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
