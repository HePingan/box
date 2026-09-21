// 红灯回归：「大模型搜题开启了没有工作」。
//
// 真机现象（2026-09-13 用户截图）：设置里已打开「允许外部网络搜题」，
// 本地题库未命中时悬浮窗仍显示「未搜到答案（本地题库未命中）」，读屏从未发起。
//
// 真因（代码证实，非推测）：
//   quiz_config.dart 里 `apiUrl` 默认 `''`、`allowExternalApi` 默认 `false`。
//   用户只拨了开关、没填 URL，而 _tryVisionFallback 的第一行是
//     if (!config.allowExternalApi || config.apiUrl.trim().isEmpty) return null;
//   → 静默 return null，调用方按普通 miss 处理，界面上完全看不出差异。
//   即「开关开了」≠「读屏可用」，但 UI 从未提示这一点。
//
// 本测试锁定修复后的契约：开关开启即视为用户已授权读屏，
// 端点走内置默认值，不得因为用户没手填 URL 就静默失效。

import 'package:box/features/quiz_plugin/domain/quiz_config.dart';
import 'package:box/features/quiz_plugin/presentation/quiz_plugin_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AI 读屏可用性判定（开关开启即应工作）', () {
    test('开启开关但未手填 apiUrl：应使用内置默认端点，判定为可用', () {
      const config = QuizConfig(allowExternalApi: true);
      // 用户视角：开关拨开了，就该能搜。
      expect(
        QuizPluginEntry.visionFallbackEnabled(config),
        isTrue,
        reason: '开关开启时不得因 apiUrl 为空而静默失效——这正是「开启了没有工作」的成因',
      );
    });

    test('未开启开关：不可用（读屏是外部请求，必须显式授权）', () {
      const config = QuizConfig();
      expect(QuizPluginEntry.visionFallbackEnabled(config), isFalse);
    });

    test('显式关闭开关时即使填了 URL 也不可用', () {
      const config = QuizConfig(
        allowExternalApi: false,
        apiUrl: 'https://newapi.hpa888.top/v1',
      );
      expect(QuizPluginEntry.visionFallbackEnabled(config), isFalse);
    });

    test('用户手填自定义端点：沿用用户值，不被默认值覆盖', () {
      const config = QuizConfig(
        allowExternalApi: true,
        apiUrl: 'https://my-own-proxy.example.com/v1',
      );
      expect(QuizPluginEntry.visionFallbackEnabled(config), isTrue);
      expect(
        QuizPluginEntry.effectiveVisionApiUrl(config),
        'https://my-own-proxy.example.com/v1',
      );
    });
  });

  group('默认端点常量（单一事实源）', () {
    test('默认端点为空时用内置 B 档端点，且形态是 OpenAI 兼容 /v1', () {
      const config = QuizConfig(allowExternalApi: true);
      final url = QuizPluginEntry.effectiveVisionApiUrl(config);
      expect(url, isNotEmpty);
      expect(url, endsWith('/v1'), reason: '引擎会拼 /chat/completions');
    });

    test('apiUrl 只有空白字符也视为未填，回落到默认端点', () {
      const config = QuizConfig(allowExternalApi: true, apiUrl: '   ');
      expect(
        QuizPluginEntry.effectiveVisionApiUrl(config),
        QuizPluginEntry.defaultVisionApiUrl,
      );
    });
  });
}
