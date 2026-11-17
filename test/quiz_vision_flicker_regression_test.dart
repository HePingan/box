import 'package:box/features/quiz_plugin/domain/quiz_proc_throttle.dart';
import 'package:box/features/quiz_plugin/domain/quiz_search_policy.dart';
import 'package:box/features/quiz_plugin/presentation/quiz_plugin_entry.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 真机报障回归（2026-11-17）「一直读屏闪烁不出答案」。
///
/// 两条根因都不是模型/网络（后端日志实测 `quiz-vision upstream=200 bytes≈560`，
/// 答案每次真的拿到了，模型 1.0~1.5s 返回合法 JSON），而是**客户端把结果判过期**：
///
///   1. 题目身份用了带 `|image:<dHash>` 的字面量指纹 —— dHash 随屏幕任何视觉变化
///      而变（包括悬浮窗自己刚画上去的答案），于是同题被判成「换题」，
///      generation 自增，回来的答案被静默丢弃、悬浮窗重画成「检索中」→ 闪 + 没答案。
///   2. 过程区块连续推送导致原生悬浮窗反复整块重绘 → 肉眼可见的闪。
void main() {
  // 读屏守卫的用例要 mock 原生通道，先初始化测试 binding。
  TestWidgetsFlutterBinding.ensureInitialized();

  group('题目身份：dHash 后缀不得改变身份', () {
    const stem = '机动车驾驶人因服兵役、出国（境）等原因无法在规定时间内办理驾驶证审验时，可以向发证机关申请延期办理。';
    const fp1 = '$stem|image:0123456789abcdef';
    const fp2 = '$stem|image:fedcba9876543210';

    test('同题干 + 不同 dHash ⇒ 仍是同一道题（这是被丢弃的那一类）', () {
      expect(fp1 == fp2, isFalse, reason: '字面量本来就不同 —— 旧代码正是栽在这');
      expect(QuizSearchPolicy.sameStemIdentity(fp1, fp2), isTrue);
    });

    test('纯题干与带后缀的同一题等价', () {
      expect(QuizSearchPolicy.sameStemIdentity(stem, fp1), isTrue);
      expect(QuizSearchPolicy.sameStemIdentity(fp1, stem), isTrue);
    });

    test('换题必须判为新题', () {
      expect(
        QuizSearchPolicy.sameStemIdentity(
          '驾驶机动车在高速公路上行驶，遇有雾天能见度小于100米时，最高车速不得超过多少？|image:0123456789abcdef',
          fp1,
        ),
        isFalse,
      );
    });

    test('空白与大小写差异不该算换题', () {
      expect(
        QuizSearchPolicy.sameStemIdentity(
          '  ${stem.toUpperCase()}  ',
          stem,
        ),
        isTrue,
      );
    });

    test('空指纹一律不等于任何东西（避免「空 == 空」把结果张冠李戴）', () {
      expect(QuizSearchPolicy.sameStemIdentity('', ''), isFalse);
      expect(QuizSearchPolicy.sameStemIdentity('', fp1), isFalse);
      expect(QuizSearchPolicy.sameStemIdentity(fp1, ''), isFalse);
    });
  });

  group('作答过程推送合并：终态不许被节流吃掉', () {
    test('内容没变不重复推', () {
      var now = 1000;
      final t = QuizProcThrottle(clock: () => now);
      expect(t.shouldPush('① 读屏截图 120KB → 压缩至 95KB'), isTrue);
      now += 500;
      expect(t.shouldPush('① 读屏截图 120KB → 压缩至 95KB'), isFalse);
      expect(t.pushed, 1);
      expect(t.skipped, 1);
    });

    test('250ms 窗口内的多次推送被合并（这就是「闪」的来源）', () {
      var now = 1000;
      final t = QuizProcThrottle(clock: () => now);
      expect(t.shouldPush('① a'), isTrue);
      now += 40;
      expect(t.shouldPush('① a\n② b'), isFalse, reason: '40ms 内，合并');
      now += 40;
      expect(t.shouldPush('① a\n② b\n③ c'), isFalse);
      now += 400;
      expect(t.shouldPush('① a\n② b\n③ c\n④ 识别成功，用时 1400ms'), isTrue);
      expect(t.pushed, 2, reason: '4 次推送被合并成 2 次');
    });

    test('终态 force 必推，哪怕紧挨着上一次', () {
      var now = 1000;
      final t = QuizProcThrottle(clock: () => now);
      expect(t.shouldPush('③ 发请求'), isTrue);
      now += 10;
      expect(t.shouldPush('③ 发请求\n✖ 失败：读屏未返回答案', force: true), isTrue);
    });

    test('force 也内容是同一段时仍推（失败文案可能靠它刷出可见状态）', () {
      var now = 1000;
      final t = QuizProcThrottle(clock: () => now);
      expect(t.shouldPush('✖ 失败'), isTrue);
      expect(t.shouldPush('✖ 失败', force: true), isTrue);
    });

    test('换题 reset 后相同首行不会被当成「没变」', () {
      var now = 1000;
      final t = QuizProcThrottle(clock: () => now);
      expect(t.shouldPush('① 读屏截图 120KB → 压缩至 95KB'), isTrue);
      t.reset();
      expect(t.shouldPush('① 读屏截图 120KB → 压缩至 95KB'), isTrue);
    });
  });

  // 真机截图实录（2026-11-17 21:05）：过程区写着「④ 识别成功，用时 15108ms」，
  // 结论区却是「未搜到答案。点右上角紫色 AI 按钮」。读屏慢（15s），期间/之后
  // 另一条搜索流程跑完并推送了**通用未命中**，把刚拿到的答案盖掉。
  group('通用未命中不许盖掉同题的读屏命中', () {
    const stemA = '驾驶机动车在一般道路上逆向行驶，一次记6分。';
    const stemB = '驾驶机动车在高速公路上行驶，遇有雾天能见度小于100米时，最高车速不得超过多少？';

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('top.hpa888.box/quiz_plugin'),
        (call) async => null,
      );
      QuizPluginEntry.debugResetVisionState();
    });

    test('刚命中过的同题：未命中重绘被拦', () {
      QuizPluginEntry.debugMarkVisionHit('$stemA|image:0123456789abcdef');
      expect(QuizPluginEntry.debugMissPaintBlocked(stemA), isTrue);
      // 题干归一化后相同即可（dHash 后缀/空白不参与身份）
      expect(
        QuizPluginEntry.debugMissPaintBlocked('  ${stemA.toUpperCase()} |image:ffffffffffffffff'),
        isTrue,
      );
    });

    test('换了题就正常报未命中', () {
      QuizPluginEntry.debugMarkVisionHit(stemA);
      expect(QuizPluginEntry.debugMissPaintBlocked(stemB), isFalse);
    });

    test('没命中过也不拦', () {
      expect(QuizPluginEntry.debugMissPaintBlocked(stemA), isFalse);
    });

    test('空指纹不拦（避免误封所有题）', () {
      QuizPluginEntry.debugMarkVisionHit(stemA);
      expect(QuizPluginEntry.debugMissPaintBlocked(''), isFalse);
    });

    test('reset 之后不再拦', () {
      QuizPluginEntry.debugMarkVisionHit(stemA);
      expect(QuizPluginEntry.debugMissPaintBlocked(stemA), isTrue);
      QuizPluginEntry.debugResetVisionState();
      expect(QuizPluginEntry.debugMissPaintBlocked(stemA), isFalse);
    });
  });
}
