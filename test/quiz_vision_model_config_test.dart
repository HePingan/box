// 答题插件「AI 读屏」模型名解析的回归测试（2026-11-17）。
//
// ## 这个 bug 的形状
//
// 引擎里模型名是**硬编码常量** `deepseek` —— 那是 NewAPI 渠道
// （`newapi.hpa888.top/v1`）时代的写法（该渠道用渠道名掩盖真实上游）。
//
// 2026-10-10 上游切到 flr 之后：
//   - 平台代理档没事（服务端用后台配置的 `provider.model` 覆盖）；
//   - **手填 key 直连档一直坏着**：客户端发 `model: deepseek`，flr 的模型
//     清单里没有这个名字 ⇒ 直连用户每次都是「模型不存在」。
//
// 修法：模型名进配置（`QuizConfig.apiModel`），留空则用 `qodercn/qfmodel`
// （2026-11-17 实测：1.7s 正确读出一道识别题）。

import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/quiz_plugin/data/quiz_engine.dart';
import 'package:box/features/quiz_plugin/domain/quiz_config.dart';

void main() {
  group('AI 读屏模型名解析', () {
    test('未配置 ⇒ 用 flr 上的默认模型（不再是 deepseek）', () {
      const config = QuizConfig(enabled: true, apiUrl: 'https://flr.hpa888.top/v1');
      expect(visionModelFor(config), 'qodercn/qfmodel');
      expect(
        QuizEngine.defaultVisionModel,
        'qodercn/qfmodel',
        reason: '默认值必须是 flr 上真实存在且支持识图的模型',
      );
      expect(
        QuizEngine.defaultVisionModel,
        isNot('deepseek'),
        reason: 'deepseek 是 NewAPI 渠道时代的写死值，flr 上没有这个模型',
      );
    });

    test('只填空格也算未配置（trim 后为空）', () {
      const config = QuizConfig(apiModel: '   ');
      expect(visionModelFor(config), QuizEngine.defaultVisionModel);
    });

    test('用户填了就原样使用（直连档的模型由用户通道决定）', () {
      const config = QuizConfig(apiModel: 'buddy/deepseek-v4.1-flash');
      expect(visionModelFor(config), 'buddy/deepseek-v4.1-flash');
    });

    test('用户填的值不做「帮我猜」式改写（前后空格只 trim）', () {
      const config = QuizConfig(apiModel: '  aggregate/deepseek-v4-1-flash  ');
      expect(visionModelFor(config), 'aggregate/deepseek-v4-1-flash');
    });
  });

  group('QuizConfig.apiModel 的持久化', () {
    test('进出 JSON 一轮不丢', () {
      const config = QuizConfig(apiModel: 'qodercn/jmodel');
      final round = QuizConfig.fromJson(config.toJson());
      expect(round.apiModel, 'qodercn/jmodel');
    });

    test('旧配置（没有这个键）⇒ 空串 ⇒ 走默认', () {
      final legacy = <String, dynamic>{
        'enabled': true,
        'apiUrl': 'https://newapi.hpa888.top/v1',
        'apiKey': 'sk-legacy',
      };
      final config = QuizConfig.fromJson(legacy);
      expect(config.apiModel, '', reason: '不做把 deepseek 猜成新名字的迁移');
      expect(visionModelFor(config), QuizEngine.defaultVisionModel);
    });

    test('copyWith 能单独改模型名而不动其它字段', () {
      const config = QuizConfig(
        enabled: true,
        apiUrl: 'https://flr.hpa888.top/v1',
        apiModel: 'qodercn/qfmodel',
      );
      final changed = config.copyWith(apiModel: 'qodercn/lmodel');
      expect(changed.apiModel, 'qodercn/lmodel');
      expect(changed.apiUrl, 'https://flr.hpa888.top/v1');
      expect(changed.enabled, isTrue);
    });
  });
}
