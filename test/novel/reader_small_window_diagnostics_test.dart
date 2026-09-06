import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 小窗转圈诊断埋点的存在性闸门。
///
/// ## 背景
///
/// 「先全屏读着、再切小窗 → 正文永久转圈」这个缺陷连续三轮未定案。前两轮的
/// 诊断都被真实证据推翻：
///
/// - 第一轮怀疑分页宽被 `clamp(200,660)` 抬高 → 已修，但那是「白屏无转圈」，
///   现象不同。
/// - 第二轮怀疑恢复阅读位置遇到 `hasClients=false` 早返回 → 该缺陷真实存在
///   且已修（v1.13.1），但它只影响停在哪一页，**解释不了转圈**：同一份日志里
///   `textPages=13` 说明页数据是有的。
///
/// 第三轮用真实代码与真实执行排掉了余下的静态可能：
///
/// - 几何守卫在该窗口尺寸（约 285x452dp）下不可能触发：实测算出
///   `fitWidth=244.9`、正文高 352/374，全部健康。
/// - `ReaderPaginator` 不会吐空页：真实分页器在三组几何上首块为 1/5/1 页。
/// - `_resetPagedState`（唯一清空 `_textPages` 的地方）只能由切章触发。
/// - 骨架屏未出现 → `_controller.loading == false`。
///
/// 于是唯一站得住的转圈来源是 `_textPages.isEmpty`，而**那条分支当时一行日志
/// 都没有**，`_calculatePages` 的早返回也完全静默。缺证据，不是缺推测。
///
/// ## 第四轮：真机日志定案，上面那个结论也是错的
///
/// v1.13.3(212) 的真机日志推翻了「`_textPages.isEmpty`」这个唯一候选，
/// 转圈来自**几何守卫 SPINNER#1**：
///
/// ```
/// LAYOUT: constraints=384.0x614.4 firstTextHeight=514.4 normalTextHeight=536.4 textPages=10
/// _calculatePages: ... pagesCount=5        ← 分页正常跑完，textPages=14
/// LAYOUT: SPINNER#1 geometry guard (fitWidth=344.0 firstTextHeight=0.0 normalTextHeight=0.0)
/// ```
///
/// 同时也修正了两处早先的事实错误：小窗实测是 **384x614dp（只矮不窄）**，
/// 不是 285x452；`fitWidth` 前后恒为 344.0，与宽度相关的整条思路作废。
/// `hasClients=false` 的 8 次重试是**结果不是原因** —— 守卫返回 spinner，
/// PageView 压根没进树，控制器永远等不到 viewport。
///
/// 「永久」的成因是 `didChangeMetrics` 当时**只记日志、不请求重建**：坏帧过后
/// 引擎在 26.47/26.48/26.50/27.70 反复报正确尺寸，却没有任何东西触发重建，
/// LayoutBuilder 再也不重跑。下面 REGRESSION 组锁的就是这个修复。
///
/// ## 这组测试锁什么
///
/// 锁住「诊断能力本身」。这些埋点是为无 adb 的报障用户准备的唯一取证手段，
/// 被顺手删掉或重构掉的话，下一轮排查会退回到猜。断言打在生产源码上，
/// 因为要防的正是源码被改回静默版本。
void main() {
  final src = File('lib/novel/pages/reader_page.dart').readAsStringSync();

  // 注释里会引用这些标识符来解释缘由，扫描前先剥掉注释行，
  // 否则「文档提到」会被误判成「代码实现」而假绿。
  // 注意：不能只丢掉「整行以 // 开头」的行 —— 把一行代码注释掉
  // （`// with WidgetsBindingObserver`）时，行首确实是 //，会被丢掉；
  // 但形如 `foo(); // 说明` 的行尾注释仍需剥掉尾部，否则注释里的标识符
  // 会被当成实现。变异测试实测：只剥整行注释时，「摘掉 didChangeMetrics」
  // 和「删掉去重字段」两个变异都能骗过断言。
  final code = src
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i < 0 ? l : l.substring(0, i);
      })
      .where((l) => l.trim().isNotEmpty)
      .join('\n');

  group('两个 spinner 分支必须各自可辨认', () {
    test('几何守卫命中时留下 SPINNER#1', () {
      expect(
        code.contains('SPINNER#1'),
        isTrue,
        reason: '几何守卫静默的话，无法区分「窗口太窄」与「页没算出来」',
      );
    });

    test('空页守卫命中时留下 SPINNER#2', () {
      expect(
        code.contains('SPINNER#2'),
        isTrue,
        reason: '这是三轮排查后唯一站得住的转圈来源，必须可观测',
      );
    });

    test('SPINNER#2 必须带上区分「没排期」与「没产出」的状态', () {
      // recalcPending 是关键判据：true=重排排了没跑完，
      // false=压根没人排期（LayoutBuilder 没重跑）。
      //
      // 断言必须限定在 SPINNER#2 那段里：recalcPending 在
      // didChangeMetrics 也出现，全文搜索时把它从 SPINNER#2 删掉照样绿
      // （变异测试实测 MISSED）。
      final spinner2 = code.substring(code.indexOf('SPINNER#2'));
      final spinner2Block = spinner2.substring(0, spinner2.indexOf(');'));
      expect(
        spinner2Block.contains('recalcPending='),
        isTrue,
        reason: '缺了它就分不清「没排期」和「排了没产出」，等于白发一版',
      );
      // 同样要限定在块内：contentLen 在 LAYOUT 行也出现（变异实测 MISSED）。
      expect(
        spinner2Block.contains('contentLen='),
        isTrue,
        reason: '要能排除「内容被清空」这一支',
      );
    });
  });

  group('LayoutBuilder 是否真的拿到新尺寸（本轮核心未知量）', () {
    test('每次约束变化都记一条 LAYOUT 行', () {
      expect(code.contains("'LAYOUT: constraints="), isTrue);
    });

    test('LAYOUT 行按签名去重，避免刷满环形日志缓冲', () {
      // 只断言标识符出现是不够的：把赋值那行删掉、只留字段声明，
      // 断言照样绿（变异测试实测 MISSED）。要盯住比较 + 赋值两半。
      expect(
        code.contains('layoutSignature != _lastLoggedLayoutSignature'),
        isTrue,
        reason: 'LayoutBuilder 每帧都跑，不比较就会把真正的证据挤出缓冲区',
      );
      expect(
        code.contains('_lastLoggedLayoutSignature = layoutSignature'),
        isTrue,
        reason: '不回写签名等于没去重，日志每帧刷一条',
      );
    });

    test('重排排期不再静默', () {
      expect(code.contains('recalc SCHEDULED'), isTrue);
    });
  });

  group('引擎层尺寸变化必须可观测', () {
    test('挂上 WidgetsBindingObserver 并实现 didChangeMetrics', () {
      expect(code.contains('with WidgetsBindingObserver'), isTrue);
      expect(code.contains('void didChangeMetrics()'), isTrue,
          reason: '这是「引擎没通知」与「通知了但布局没跟上」的唯一分界证据');
    });

    test('observer 必须注册也必须注销', () {
      expect(code.contains('WidgetsBinding.instance.addObserver(this)'), isTrue);
      expect(
        code.contains('WidgetsBinding.instance.removeObserver(this)'),
        isTrue,
        reason: '不注销会让已销毁的 State 继续收回调',
      );
    });

    test('didChangeMetrics 要记录逻辑尺寸与当前页数', () {
      expect(code.contains('didChangeMetrics: logicalSize='), isTrue);
    });
  });

  group('REGRESSION 小窗永久转圈：坏帧之后必须能自愈', () {
    // 定案依据（v1.13.3+212 真机日志，红米 K80 / HyperOS）：
    //   LAYOUT: SPINNER#1 geometry guard (... firstTextHeight=0.0 normalTextHeight=0.0)
    // 此后 didChangeMetrics 连报四次正确的 384.0x614.4，却再无一条 LAYOUT ——
    // 因为当时 didChangeMetrics 只 log 不 setState，没有任何东西请求重建。
    // 「转圈一帧」是可以接受的；「永久」不行。这组锁的是自愈能力。
    test('didChangeMetrics 必须请求重建，而不是只记日志', () {
      final body = code.substring(code.indexOf('void didChangeMetrics()'));
      final end = body.indexOf('\n  }');
      final metricsBody = body.substring(0, end == -1 ? body.length : end);

      expect(
        metricsBody.contains('setState'),
        isTrue,
        reason: '只记日志不重建 → 坏帧后 LayoutBuilder 永不重跑，spinner 永久留屏。'
            '这正是 1.13.1~1.13.3 现场的成因，删掉它就是把缺陷放回去',
      );
    });

    test('几何守卫必须报出输入，否则无法区分约束坏还是 topPad 脏', () {
      // 上一轮 SPINNER#1 只打印结果（都是 0.0），拿不到 topPad /
      // availableForText，白丢一轮取证。
      final guard = code.substring(code.indexOf('SPINNER#1 geometry guard'));
      final guardLog = guard.substring(0, guard.indexOf(');'));

      expect(guardLog.contains('topPad='), isTrue,
          reason: 'constraints 已证明正常，topPad 是唯一嫌疑，必须打出来');
      expect(guardLog.contains('availableForText='), isTrue,
          reason: '这是 resolve() 返回 0 的直接输入，缺它就只能靠反推');
      expect(guardLog.contains('constraints='), isTrue,
          reason: '守卫自带约束，才不必依赖另一条可能被去重吞掉的 LAYOUT 行');
    });

    test('LAYOUT 去重键必须含 topPad', () {
      // 坏帧与好帧的 constraints 完全相同（384.0x614.4），
      // 只含 constraints 的签名会把坏帧那条 LAYOUT 整条吞掉。
      final sigStart = code.indexOf('final layoutSignature =');
      final sig = code.substring(sigStart, code.indexOf(';', sigStart));

      expect(
        sig.contains('topPad'),
        isTrue,
        reason: '坏帧 constraints 与好帧一致，签名不含 topPad 就会被判重复而丢证据',
      );
    });
  });

  group('_calculatePages 的早返回不得静默', () {
    test('跳过时打出 SKIPPED 及其原因', () {
      expect(code.contains('_calculatePages: SKIPPED'), isTrue);
      expect(code.contains('contentEmpty='), isTrue);
      expect(code.contains('scrollMode='), isTrue);
    });
  });

  group('诊断必须落在统一日志设施里', () {
    test('全部走 ReaderDebugLog（阅读频道），不新建 logger', () {
      // 用户明确要求单一事实源：诊断日志只能有一套，报障人才能一次性复制全。
      expect(code.contains('ReaderDebugLog.log('), isTrue);
      expect(
        code.contains('debugPrint('),
        isFalse,
        reason: 'debugPrint 在 Release 里报障人拿不到，等于没埋',
      );
    });
  });
}
