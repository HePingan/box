// 「识别成功，没出答案」兜底回归（2026-11-18 用户报障）。
//
// 现象：AI 读屏过程区写着「④ 识别成功」，结论区却是空的。
// 这类「过程说成功、结果没内容」的故障历史上出现过两次（11-17 dHash 污染
// 题目身份、11-18 未命中覆盖答案），共同点是**画面在撒谎**：状态和内容矛盾。
//
// 兜底原则：命中态**绝不允许渲染空白正文**。只要组成的正文去掉隐藏相似度
// marker 后为空，就换成一句人话，并把状态降级成 miss（不冒充命中）。
// 原生侧同样有一道防线（见源码契约最后一组）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('隐藏 marker 剥离后判空的口径', () {
    // 与 QuizPluginEntry.pushResultOverlay 中同一正则
    final marker = RegExp(r'\s*\[\[SIM:\d{1,3}]]');
    String visible(String s) => s.replaceAll(marker, '').trim();

    test('只有 marker 的正文视为空（这就是「只剩徽章没有字」）', () {
      expect(visible('[[SIM:95]]'), '');
      expect(visible('  [[SIM:0]]  '), '');
    });

    test('答案 + marker 不算空', () {
      expect(visible('答案：C\n[[SIM:95]]'), '答案：C');
      expect(visible('请人工确认\n候选 1：A\n[[SIM:72]]'), contains('请人工确认'));
    });

    test('空白字符不算内容', () {
      expect(visible('   \n\t  '), '');
    });
  });

  group('原生兜底契约（改渲染时别把空白放过去）', () {
    String service() => File(
          'android/app/src/main/kotlin/top/hpa888/box/QuizAccessibilityService.kt',
        ).readAsStringSync();

    test('非检索态的正文为空时必须替换成可读提示', () {
      final kt = service();
      expect(
        kt.contains('val shown = if (displayAnswer.isBlank())'),
        isTrue,
        reason: '命中/歧义/重试态渲染空白等于让画面撒谎',
      );
      expect(kt.contains('applyAnswerStyle(aTv, shown)'), isTrue,
          reason: '必须用替换后的文本渲染');
    });

    test('空白渲染要留下诊断日志（下次报障能定位）', () {
      final kt = service();
      expect(kt.contains('answer text blank at render'), isTrue);
    });
  });

  group('Dart 兜底契约', () {
    test('pushResultOverlay 里有「命中但正文为空」的降级分支', () {
      final dart = File(
        'lib/features/quiz_plugin/presentation/quiz_plugin_entry.dart',
      ).readAsStringSync();
      expect(dart.contains('命中但正文为空'), isTrue);
      expect(dart.contains("resultStatus = 'miss'"), isTrue,
          reason: '正文为空不能继续冒充命中');
      expect(dart.contains("answerKey: resultStatus == 'miss' ? null : ambiguity.answerKey"),
          isTrue,
          reason: '正文都没了还高亮选项键会误导');
    });
  });
}
