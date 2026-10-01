// 登录档 401 → 匿名设备令牌降级重试（2026-10-01 真机事故的回归测试）。
//
// 事故：服务端会话有 30 天 TTL，到期后**所有**账号接口 401；读屏走"已登录"档
// （Bearer = session token）→ 401 → 用户看到「读屏凭证已失效，请重新登录」，
// 而匿名设备令牌那条路本来是通的（服务端 device-token 端点已上线）。
// 修法：登录档 401 时引擎降级到匿名档重试一次，不再把"登录过期"当成读屏的死刑。
//
// 本文件锁四件事：
//   1) 登录档 401 → 换匿名 Bearer + 匿名 base，**立即**重试（不退避），成功出答案；
//   2) 没给降级回调时行为不变（立即失败，文案 = visionProxyCredentialExpiredText）；
//   3) 降级不可用（签发失败）→ 只发一次请求，错误文案取签发原因；
//   4) 降级后仍 401 → 不再反复降级（总请求数 = 2，不烧退避预算）。
//
// 走真实压缩路径（960×960 真 PNG + dart:ui 编解码），不喂假字节：降级分支发生在
// HTTP 层，若压缩路径先炸，测试就应该红灯。
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:box/features/quiz_plugin/domain/quiz_vision_usage.dart';
import 'package:box/features/quiz_plugin/data/quiz_engine.dart';
import 'package:box/features/quiz_plugin/domain/quiz_config.dart';
import 'package:box/features/quiz_plugin/domain/quiz_vision_endpoint.dart';
import 'package:flutter/material.dart' show Canvas, Color, Paint, Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _server = 'https://background.hpa888.top';
const _proxyBase = '$_server/api/quiz/vision';
const _sessionToken = 'sess-token-abc123';
const _deviceToken = 'dev-token-xyz789';

/// 服务端 401 的原文（线上实测 108 字节那条）——降级分支的触发条件。
const _proxy401Body =
    '{"error":{"message":"登录已失效或设备令牌无效，请重新登录或重新获取设备令牌。"}}';

/// 上游 200 的最小可用响应（content 里是模型给的 JSON）。
const _visionJson =
    '{"stem":"题干","options":["A. 甲","B. 乙"],"answer":"A","confidence":0.9}';

Future<String> _okBody() async => jsonEncode({
  'choices': [
    {
      'index': 0,
      'finish_reason': 'stop',
      'message': {'role': 'assistant', 'content': _visionJson},
    },
  ],
});

/// 真图：960×960 纯色 PNG（== [QuizEngine.visionMaxEdge]，压缩路径不缩放）。
Future<Uint8List> _png960() async {
  const size = QuizEngine.visionMaxEdge;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    Paint()..color = const Color(0xFF202020),
  );
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// 记录每个请求的假上游：按 [statuses] 逐次返回（用完后重复最后一项）。
({http.Client client, List<http.Request> requests}) _recordingClient(
  List<int> statuses,
) {
  final requests = <http.Request>[];
  final client = MockClient((req) async {
    requests.add(req);
    final status = statuses[(requests.length - 1).clamp(0, statuses.length - 1)];
    final headers = {
      'content-type': 'application/json; charset=utf-8',
      // B1（2026-10-01）：服务端在响应头回报额度用量，客户端要把它记下来。
      'X-Quiz-Vision-Used': '7',
      'X-Quiz-Vision-Cap': '100',
    };
    if (status == 200) return http.Response(await _okBody(), 200, headers: headers);
    return http.Response(_proxy401Body, status, headers: headers);
  });
  return (client: client, requests: requests);
}

/// 登录档的引擎（base 指向平台代理、Bearer = 会话令牌）。
QuizEngine _engine(http.Client client) => QuizEngine(
  config: const QuizConfig(
    allowExternalApi: true,
    apiUrl: _proxyBase,
    apiKey: _sessionToken,
  ),
  httpClient: client,
);

/// 降级回调：按真实实现返回匿名档（走 domain 的同一套分流规则）。
Future<QuizVisionEndpoint> _anonymous() async => resolveQuizVisionEndpoint(
  const QuizConfig(),
  serverUrl: _server,
  deviceToken: _deviceToken,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('读屏登录档 401 → 匿名降级', () {
    test('登录档 401 → 换匿名 Bearer、立即重试并成功出答案', () async {
      final rec = _recordingClient([401, 200]);
      final result = await _engine(rec.client).searchVisionApi(
        await _png960(),
        hintQuestion: '驾驶校车…一次记几分？',
        onCredentialRejected: _anonymous,
      );

      expect(result.isSuccess, isTrue, reason: result.error ?? '降级后应成功');
      expect(result.answers.single.correctAnswer, 'A');
      expect(rec.requests, hasLength(2), reason: '401 后只重试一次');
      expect(
        rec.requests[0].headers['Authorization'],
        'Bearer $_sessionToken',
        reason: '第一次必须用登录档（几何不变：先登录后匿名）',
      );
      expect(
        rec.requests[1].headers['Authorization'],
        'Bearer $_deviceToken',
        reason: '降级后 Bearer 必须是匿名设备令牌',
      );
      expect(
        rec.requests[1].url.toString(),
        '$_proxyBase/chat/completions',
        reason: '匿名档与登录档同一条代理路径，只换 Bearer',
      );
    });

    test('B1：响应头里的用量被记下来（自检页据此显示「今日 X/100」）', () async {
      QuizVisionUsage.reset();
      addTearDown(QuizVisionUsage.reset);
      final rec = _recordingClient([200]);
      final result = await _engine(rec.client).searchVisionApi(
        await _png960(),
        hintQuestion: '驾驶校车…一次记几分？',
      );

      expect(result.isSuccess, isTrue, reason: result.error ?? '应成功');
      expect(QuizVisionUsage.usedToday, 7);
      expect(QuizVisionUsage.dailyCap, 100);
      expect(QuizVisionUsage.describe(), contains('7/100'));
    });

    test('没给降级回调 → 行为不变：立即失败，文案仍是「凭证已失效」', () async {
      final rec = _recordingClient([401, 200]);
      final result = await _engine(
        rec.client,
      ).searchVisionApi(await _png960(), hintQuestion: '题干');

      expect(result.isSuccess, isFalse);
      expect(result.error, visionProxyCredentialExpiredText);
      expect(rec.requests, hasLength(1), reason: '代理确定性失败不重试');
    });

    test('降级不可用（签发失败）→ 只发一次请求，错误取签发原因', () async {
      final rec = _recordingClient([401, 200]);
      final result = await _engine(rec.client).searchVisionApi(
        await _png960(),
        hintQuestion: '题干',
        onCredentialRejected: () async =>
            const QuizVisionEndpoint.unavailable('匿名令牌签发失败：HTTP 429'),
      );

      expect(result.isSuccess, isFalse);
      expect(result.error, contains('429'));
      expect(rec.requests, hasLength(1), reason: '拿不到匿名凭证就不该再打一次');
    });

    test('降级后仍 401 → 不再反复降级（总请求数 = 2）', () async {
      final rec = _recordingClient([401, 401]);
      final result = await _engine(rec.client).searchVisionApi(
        await _png960(),
        hintQuestion: '题干',
        onCredentialRejected: _anonymous,
      );

      expect(result.isSuccess, isFalse);
      expect(result.error, visionProxyCredentialExpiredText);
      expect(rec.requests, hasLength(2), reason: '降级只做一次，避免反复换档');
      expect(
        rec.requests[1].headers['Authorization'],
        'Bearer $_deviceToken',
      );
    });
  });
}
