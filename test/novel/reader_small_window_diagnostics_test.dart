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
