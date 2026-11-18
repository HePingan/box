// P0 批次回归（2026-11-18 审计第 1 批）。
//
// 锁四件事：
//   1) 代理档错误文案必须按后端 error.code 分流 —— 429 有「突发限流」与「日额度」
//      两种、403 有「代理没开 / 设备被撤销 / 账号停用」三种，按状态码一律出同一句
//      文案会把用户指向错误的排查方向。
//   2) OCR 默认关闭（默认端点 ocr.hpa888.top 实测自签证书 + 无 vhost，必然失败）。
//   3) 主题色索引越界要收敛（旧面板给 6 个色块而色板只有 5 色，存量 index 可能是 5）。
//   4) 第三方外部检索的答案置信度封顶 0.5（原来给第一条 0.9 = 把未校验网页文本
//      当成与本地题库同等可信）。
import 'package:box/features/quiz_plugin/data/quiz_engine.dart';
import 'package:box/features/quiz_plugin/domain/quiz_config.dart';
import 'package:box/features/quiz_plugin/domain/quiz_vision_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('error.code 分流（代理档）', () {
    test('能解析嵌套的 error.code', () {
      expect(
        visionErrorCodeFrom('{"error":{"code":"burst_limited","message":"x"}}'),
        'burst_limited',
      );
      expect(visionErrorCodeFrom('{"error":{"message":"x"}}'), isNull);
      expect(visionErrorCodeFrom('not json'), isNull);
      expect(visionErrorCodeFrom(''), isNull);
      expect(visionErrorCodeFrom(null), isNull);
    });

    test('突发限流 ≠ 今日用完：文案必须说「稍等」而不是「明天」', () {
      final t = visionHttpErrorText(429,
          viaProxy: true, errorCode: 'burst_limited');
      expect(t, contains('稍等'));
      expect(t.contains('今日'), isFalse, reason: '突发限流说成今日用完是历史误报');
    });

    test('日额度文案要给出真实重置时间（日键是 UTC）', () {
      final t = visionHttpErrorText(429,
          viaProxy: true, errorCode: 'daily_cap_exhausted');
      expect(t, contains('08:00'));
    });

    test('设备被撤销要指向管理员，不能指向「代理未开」', () {
      final t =
          visionHttpErrorText(403, viaProxy: true, errorCode: 'device_revoked');
      expect(t, contains('管理员'));
      expect(t.contains('代理'), isFalse);
    });

    test('账号停用给出重新登录指引', () {
      final t = visionHttpErrorText(403,
          viaProxy: true, errorCode: 'account_disabled');
      expect(t, contains('重新登录'));
    });

    test('未知 code 回退到状态码口径（不能因为新增 code 就变成空文案）', () {
      expect(
        visionHttpErrorText(403, viaProxy: true, errorCode: 'whatever'),
        contains('代理'),
      );
      expect(visionHttpErrorText(503, viaProxy: true), contains('繁忙'));
    });
  });

  group('配置默认值', () {
    test('OCR 默认关闭（否则新用户每题先跑一次必然失败的链路）', () {
      expect(const QuizConfig().ocrSearch, isFalse);
      expect(QuizConfig.fromJson(<String, dynamic>{}).ocrSearch, isFalse);
    });

    test('老配置里显式 ocrSearch=true 仍然尊重（不回退用户选择）', () {
      expect(
        QuizConfig.fromJson(<String, dynamic>{'ocrSearch': true}).ocrSearch,
        isTrue,
      );
      // 更老的键名 ocrEnabled 依旧兼容
      expect(
        QuizConfig.fromJson(<String, dynamic>{'ocrEnabled': true}).ocrSearch,
        isTrue,
      );
    });

    test('themeColorIndex 越界收敛到色板范围', () {
      final cfg = QuizConfig.fromJson(<String, dynamic>{'themeColorIndex': 5});
      expect(cfg.themeColorIndex, QuizConfig.themeColors.length - 1);
      final cfg2 = QuizConfig.fromJson(<String, dynamic>{'themeColorIndex': -3});
      expect(cfg2.themeColorIndex, 0);
    });

    test('已删除的死配置字段不再出现在序列化里', () {
      final json = const QuizConfig().toJson();
      for (final dead in ['overlayX', 'overlayY', 'bankPriority', 'regionForImage']) {
        expect(json.containsKey(dead), isFalse, reason: '$dead 已删');
      }
    });
  });

  group('外部检索不再产出高置信答案', () {
    test('内置第三方接口的答案置信度封顶 0.5', () async {
      // 通过公开入口无法只打 _searchBuiltIn，这里直接验证解析产物：
      // 用 allowExternalApi + 内置通道（apiUrl 为空）走 search()。
      final engine = QuizEngine(
        config: const QuizConfig(allowExternalApi: true, bankEnabled: false),
      );
      // 不断言真实网络结果，只断言「若来自内置(未校验)，置信度不超过 0.5」。
      final result = await engine.search('驾驶机动车逆向行驶一次记几分');
      for (final a in result.answers) {
        if (a.source.contains('内置')) {
          expect(a.confidence, lessThanOrEqualTo(0.5),
              reason: '第三方公共 API 的文本不许当高置信答案');
        }
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
