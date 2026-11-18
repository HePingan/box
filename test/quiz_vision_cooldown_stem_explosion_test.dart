// 标志图题（同题干候选爆炸）不该被「同屏读屏冷却」挡死（2026-11-18 自检页证据）。
//
// 真机自检输出（21:14:03~05）：
//   MATCH 拒绝：同题干候选爆炸（疑似标志图题） cand=244 bestQ=100 bestO=100 tieAnswers=3
//   RESULT engine.search 返回 ok=false ms=396
//   RESULT 无结果：引擎未命中，悬浮窗停在检索中
//   RESULT 读屏跳过：同一屏冷却中 cooldownMs=10000
//   RESULT 读屏跳过：同一屏冷却中 cooldownMs=10000
//
// 两件事同时错：
//   ① 本地题库对标志图题**必然**无解（244 条同题干、3 种互斥答案），AI 读屏是唯一
//      出路，却被 10 秒同屏冷却挡在门外 ⇒ 用户只能对着「未搜到」干等；
//   ② 冷却不分上次成败。上次读屏明明失败了，没有任何「已经出过答案」需要保护，
//      仍按 10 秒拦，等于把失败惩罚成双倍等待。
import 'dart:io';

import 'package:box/features/quiz_plugin/presentation/quiz_plugin_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(QuizPluginEntry.debugResetVisionState);

  group('冷却时长', () {
    test('失败后的冷却必须明显短于成功后的冷却', () {
      expect(
        QuizPluginEntry.visionRepeatCooldownAfterFailure.inSeconds,
        lessThan(QuizPluginEntry.visionRepeatCooldown.inSeconds),
        reason: '失败后没有答案需要保护，冷却只为防连环烧钱',
      );
    });

    test('失败冷却不得短于 2 秒（否则每一拍扫描都会真打一次付费请求）', () {
      expect(QuizPluginEntry.visionRepeatCooldownAfterFailure.inSeconds,
          greaterThanOrEqualTo(2));
    });

    test('成功冷却不得短于 8 秒（答案已在屏上，不该重复烧钱）', () {
      expect(QuizPluginEntry.visionRepeatCooldown.inSeconds,
          greaterThanOrEqualTo(8));
    });
  });

  group('源码契约：爆炸题放行 + 失败短冷却 + 原因可见', () {
    final dart = File(
      'lib/features/quiz_plugin/presentation/quiz_plugin_entry.dart',
    ).readAsStringSync();

    test('题库爆炸的题要把 bypassRepeatCooldown 传进读屏链路', () {
      expect(dart.contains('bypassRepeatCooldown: textPathResult?.stemExplosion ?? false'), isTrue,
          reason: '标志图题唯一出路是 AI 读屏，不许被冷却挡住');
    });

    test('冷却时长按上次成败分流', () {
      expect(dart.contains('_lastVisionOk == false'), isTrue);
      expect(dart.contains('visionRepeatCooldownAfterFailure'), isTrue);
    });

    test('起跑即记「未成功」，任何非成功出口都不会被当成成功', () {
      expect(
        dart.contains('_lastVisionOk = false;'),
        isTrue,
        reason: '截图为空/上游失败/换题丢弃都必须算失败',
      );
    });

    test('爆炸题的未命中文案必须说出「同题干 N 条、只能看题图」', () {
      expect(dart.contains('条同题干、答案互不相同'), isTrue,
          reason: '只说「未搜到」会被误解成识别坏了');
      expect(dart.contains('stemExplosionCount'), isTrue);
    });

    test('visionPhase 流程结束要归位（自检页不许显示残留「截图」）', () {
      expect(dart.contains("visionPhase = '空闲';"), isTrue);
    });
  });
}
