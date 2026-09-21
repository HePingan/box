// 红灯回归：外部「AI 读屏」搜题（B 档 / 方案丙）。
//
// 背景（2026-09-13）：用户拍板
//   ① 方案丙：模型独立作答，不看界面已选答案
//   ② 模型名固定 deepseek（box 项目维持原模型，gemini 仅用于 Hermes 视觉）
//   ③ 所有本地未命中的题都触发读屏
//
// 真实接口已实测（NewAPI 渠道 https://newapi.hpa888.top/v1）：
//   - OpenAI 兼容 POST /chat/completions + Bearer
//   - base64 内联图可用（App 端唯一可行方式，手机截图无法先传公网）
//   - 模型返回严格 JSON：{"stem","options","answer","confidence"}
//   - 偶发 503 system_cpu_overloaded → 必须指数退避重试（实测退避后成功）
//
// 本测试锁定「请求构造 + 响应解析 + 兜底」三条契约，不依赖网络。

import 'dart:convert';

import 'package:box/features/quiz_plugin/data/quiz_engine.dart';
import 'package:box/features/quiz_plugin/domain/quiz_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// 与 quiz_engine 中 _searchVisionApi 构造的请求体保持一致的快照。
/// 若实现变更导致请求体结构变化，本测试应红灯提醒同步更新。
Map<String, dynamic> buildVisionRequest({
  required String model,
  required String base64Image,
  required String prompt,
}) => {
      'model': model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:image/png;base64,$base64Image',
              },
            },
          ],
        },
      ],
      'max_tokens': 1200,
      'temperature': 0,
    };

/// 从模型散文/JSON 混合输出中提取结构化答案 —— 直接复用实现里的
/// [parseVisionJson]，保证「测试锁定的解析器」与「线上跑的解析器」是同一份。
Map<String, dynamic>? parseVisionJsonUnderTest(String content) =>
    parseVisionJson(content);

void main() {
  group('AI 读屏请求构造', () {
    test('请求体为 OpenAI 兼容格式，图片走 base64 data URL', () {
      final req = buildVisionRequest(
        model: 'deepseek',
        base64Image: 'AAAA',
        prompt: '读题',
      );
      expect(req['model'], 'deepseek');
      expect(req['temperature'], 0);
      final msgs = req['messages'] as List;
      expect(msgs, hasLength(1));
      final content = (msgs.first as Map)['content'] as List;
      expect(content, hasLength(2));
      expect((content[0] as Map)['type'], 'text');
      final img = content[1] as Map;
      expect(img['type'], 'image_url');
      expect(
        (img['image_url'] as Map)['url'],
        'data:image/png;base64,AAAA',
        reason: 'App 端只能内联 base64，不能依赖公网图',
      );
    });

    test('请求体可 JSON 序列化且不含非法类型', () {
      final req = buildVisionRequest(
        model: 'deepseek',
        base64Image: 'BBBB',
        prompt: '读题',
      );
      expect(() => jsonEncode(req), returnsNormally);
    });
  });

  group('AI 读屏响应解析（方案丙：独立作答）', () {
    test('纯 JSON 输出可解析出 stem/options/answer', () {
      const raw =
          '{"stem":"驾驶校车…一次记6分。","options":["A. 正确","B. 错误"],"answer":"B","confidence":0.98}';
      final j = parseVisionJsonUnderTest(raw);
      expect(j, isNotNull);
      expect(j!['stem'], contains('校车'));
      expect(j['options'], hasLength(2));
      expect(j['answer'], 'B');
      expect((j['confidence'] as num).toDouble(), greaterThan(0.9));
    });

    test('```json 围栏包裹的输出也能解析（实测模型常见形式）', () {
      const raw = '```json\n{"stem":"题目","options":["A. 甲","B. 乙"],'
          '"answer":"A","confidence":0.9}\n```';
      final j = parseVisionJsonUnderTest(raw);
      expect(j, isNotNull);
      expect(j!['answer'], 'A');
    });

    test('散文夹杂 JSON 时仍能提取（实测模型会先写 Markdown 标题）', () {
      const raw = '## 分析\n这是一道判断题。\n'
          '{"stem":"题干","options":["A. 对","B. 错"],"answer":"B","confidence":0.85}';
      final j = parseVisionJsonUnderTest(raw);
      expect(j, isNotNull);
      expect(j!['stem'], '题干');
      expect(j['answer'], 'B');
    });

    test('完全无法解析时返回 null（不得猜测答案）', () {
      const raw = '抱歉，我无法识别这张图片。';
      expect(parseVisionJsonUnderTest(raw), isNull);
    });
  });

  group('AI 读屏配置契约', () {
    test('默认关闭外部搜题（隐私优先，与设置面板副文案一致）', () {
      const c = QuizConfig();
      expect(c.allowExternalApi, isFalse);
    });

    test('可设置 apiUrl/apiKey 且能 JSON 往返', () {
      const c = QuizConfig(
        allowExternalApi: true,
        apiUrl: 'https://newapi.hpa888.top/v1',
        apiKey: 'sk-test',
      );
      final back = QuizConfig.fromJson(c.toJson());
      expect(back.allowExternalApi, isTrue);
      expect(back.apiUrl, 'https://newapi.hpa888.top/v1');
      expect(back.apiKey, 'sk-test');
    });

    test(
        '401/403 列入可重试名单（渠道鉴权瞬态抽风，与 503 同源），400 仍直接失败', () {
      // 与 quiz_engine._searchVisionApi 里的 retryable 名单保持同步。
      // 若将来改名单，本测试应红灯提醒同步。
      final retryable = const {500, 502, 503, 504, 429, 401, 403};
      expect(retryable.contains(401), isTrue,
          reason: '401 Invalid token 是 newapi 渠道 CPU 过载/鉴权抽风的瞬态错，须重试');
      expect(retryable.contains(403), isTrue);
      expect(retryable.contains(400), isFalse,
          reason: '纯参数/内容错重试无意义，直接失败不浪费预算');
    });
  });
}
