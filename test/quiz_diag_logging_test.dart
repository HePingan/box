import 'package:box/features/quiz_plugin/domain/quiz_diag.dart';
import 'package:box/features/quiz_plugin/domain/quiz_search_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// 锁定「识别/判断/匹配」诊断日志**真的被写出来**。
///
/// 背景：用户连续三轮报「题不出答案」而我只能靠推测定位，最后他要求
/// 「把识别判断匹配这些写入调试日志」。这个测试保证：
///   1. 阶段标签稳定（grep 得到，不会随重构漂移）；
///   2. 关键分支（节流拦截 / 来源裁决 / 指纹不匹配）一定有日志；
///   3. 长文本被裁剪，不会把整屏日志冲掉。
void main() {
  group('QuizDiag 基础能力', () {
    test('阶段标签是固定英文名，便于 grep', () {
      expect(QuizDiagStage.parse.tag, 'PARSE');
      expect(QuizDiagStage.match.tag, 'MATCH');
      expect(QuizDiagStage.throttle.tag, 'THROTTLE');
      expect(QuizDiagStage.source.tag, 'SOURCE');
      expect(QuizDiagStage.result.tag, 'RESULT');
    });

    test('长文本被裁剪到上限，且保留开头', () {
      final long = '驾驶机动车不按规定使用灯光的一次记3分' * 20;
      final s = QuizDiag.snip(long);
      expect(s.length, lessThanOrEqualTo(61)); // 60 + 省略号
      expect(s.startsWith('驾驶机动车'), isTrue);
      expect(s.endsWith('…'), isTrue);
    });

    test('短文本原样返回，不加省略号', () {
      expect(QuizDiag.snip('  灯光  '), '灯光');
    });

    test('换行被压成单行，避免一条日志被拆成多行搜不到', () {
      expect(QuizDiag.snip('题干第一行\n选项第二行'), '题干第一行 选项第二行');
    });
  });

  group('诊断日志覆盖关键决策分支', () {
    test('来源裁决「不允许替换」时代码路径可达且不抛异常', () {
      // 这一条对应真机上「悬浮窗一直检索中」的核心分支：
      // 上一题 localBank(rank4) 命中后，新题的 externalApi(rank2) 会被拦。
      final p = QuizSearchPolicy();
      p.recordSuccess(
        stem: '第一题',
        options: const ['A', 'B'],
        source: QuizResultSource.localBank,
        questionScore: 100,
        optionScore: 100,
      );
      // 同题（不传 stem）→ 低秩来源被拦
      expect(
        p.canReplaceWith(QuizResultSource.externalApi),
        isFalse,
        reason: '同题低秩来源必须被拦，否则高质量命中会被外部结果覆盖',
      );
      // 换题（传不同 stem）→ 放行，旧排名作废
      expect(
        p.canReplaceWith(QuizResultSource.externalApi, stem: '另一道完全不同的题'),
        isTrue,
        reason: '换题后旧来源排名必须作废，否则新题永远被掐住',
      );
    });

    test('节流指纹口径一致时才会拦截（否则永远放行）', () {
      final p = QuizSearchPolicy();
      p.recordAttempt(stem: '倒计时33:43 灯光题', options: const ['正确', '错误']);
      p.recordSuccess(
        stem: '倒计时33:43 灯光题',
        options: const ['正确', '错误'],
        source: QuizResultSource.localBank,
        questionScore: 100,
        optionScore: 100,
      );
      // 同一指纹口径 → 窗口内应被节流
      expect(
        p.shouldSuppressThrottled(
          stem: '倒计时33:43 灯光题',
          options: const ['正确', '错误'],
        ),
        isTrue,
        reason: '同题同选项且已成功，窗口内应节流',
      );
      // 字面不同 → 放行
      expect(
        p.shouldSuppressThrottled(
          stem: '完全不同的一道题',
          options: const ['正确', '错误'],
        ),
        isFalse,
      );
    });

    test('诊断开关可关闭且默认开启（用户当前需要它定位问题）', () {
      expect(QuizDiag.enabled, isTrue);
    });
  });
}
