import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:box/novel/pages/reader/reader_layout_metrics.dart';

/// REGRESSION 小窗永久转圈第五轮：`MediaQuery.padding.top` 报出**整个窗口高度**。
///
/// ## 真实取证（iQOO / OriginOS，v1.14.1+215，报障人无 adb）
///
/// 用户在阅读中切小窗，正文永久转圈。App 内调试日志原文（截取关键 4 行）：
///
/// ```
/// [20:41:39.330468] LAYOUT: constraints=384.0x853.3@37.0 topPad=37.0  ← 全屏，正常
/// [20:41:40.899433] didChangeMetrics: logicalSize=384.0x614.4 textPages=13
/// [20:41:40.904008] LAYOUT: constraints=384.0x614.4@0.0 topPad=0.0 firstTextHeight=514.4  ← 小窗首帧，健康
/// [20:41:40.975320] LAYOUT: constraints=384.0x614.4@614.4 topPad=614.4 firstTextHeight=0.0
/// [20:41:40.975348] LAYOUT: SPINNER#1 geometry guard (... topPad=614.4 availableForText=-54.0)
/// ```
///
/// `topPad=614.4` **等于窗口高度本身**（constraints.maxHeight=614.4）。状态栏
/// 内边距不可能等于整个窗口高，这是 OriginOS 在多窗口过渡帧里给出的脏值。
/// 算术与日志逐值吻合，可以手算复核：
///
/// ```
/// paddingTotal      = 614.4 + 8 + 8            = 630.4
/// availableForText  = 614.4 - 630.4 - 24 - 14  = -54.0   ← 日志原文
/// ```
///
/// 于是 `resolve()` 按「尺寸未就绪」返回 0，几何守卫 SPINNER#1 命中。
///
/// ## 为什么上一轮的自愈修复不管用（本轮必须撤回那个结论）
///
/// v1.13.3 那轮给 `didChangeMetrics` 加了 `setState(() {})`，理由是「下一帧
/// MediaQuery 已刷新，守卫拿到正常 topPad 就会放行」。本轮日志证明这个前提
/// **不成立**：20:41:42 的三次 `didChangeMetrics` 确实触发了重建，
/// LayoutBuilder 也确实重跑了，但每次拿到的 `topPad` 依旧是 614.4 ——
/// 脏值不会自己恢复，重建再多次也只是把同一个坏输入重算一遍。
///
/// 结论：几何本身必须对脏 inset 免疫，不能依赖「下一帧会变好」。
///
/// ## 不变式
///
/// 一个把窗口吃光的 inset 是不可用的 inset：宁可让正文压在状态栏下面
/// （最坏是顶部一行被遮），也不能显示永久转圈 —— 前者用户还能读，
/// 后者整页不可用。
void main() {
  // 日志原文里的两个数，写成常量供全组复核用。
  const windowHeight = 614.4; // constraints.maxHeight，小窗真实高度
  const bogusTopPad = 614.4; // MediaQuery.padding.top 的脏值
  const realTopPad = 37.0; // 同一台机器全屏时的真实状态栏（日志首行）

  /// 复刻 `_buildPagedReaderView` 的正文高度算式，用于端到端复核。
  /// 24 = 底部页码行预留，14 = 行尾余量，8+8 = 上下 padding。
  double firstTextHeightFor(double maxHeight, double rawTopPad) {
    final topPad = ReaderLayoutMetrics.resolveTopPad(
      rawTopPad,
      maxHeight: maxHeight,
    );
    final avail = maxHeight - (topPad + 8.0 + 8.0) - 24.0 - 14.0;
    return ReaderLayoutMetrics.resolve(
      availableHeight: avail,
      isFirstPage: true,
    ).textHeight;
  }

  group('脏 inset 必须被识别并丢弃', () {
    test('topPad 等于窗口高度（日志原值）时判定为脏值，取 0', () {
      expect(
        ReaderLayoutMetrics.resolveTopPad(
          bogusTopPad,
          maxHeight: windowHeight,
        ),
        0.0,
        reason: '状态栏 inset 不可能等于整个窗口高，必须丢弃而不是照用',
      );
    });

    test('topPad 超过窗口高度（更离谱的脏值）同样丢弃', () {
      expect(
        ReaderLayoutMetrics.resolveTopPad(900.0, maxHeight: windowHeight),
        0.0,
      );
    });

    test('真实状态栏 inset 必须原样保留，不能被误伤', () {
      // 这条是防「一刀切归零」的反向闸门：修脏值不能把正常 inset 也吃掉，
      // 否则全屏下正文会顶到状态栏底下，属于用修复换新 bug。
      expect(
        ReaderLayoutMetrics.resolveTopPad(realTopPad, maxHeight: 853.3),
        realTopPad,
      );
      expect(
        ReaderLayoutMetrics.resolveTopPad(24.0, maxHeight: 853.3),
        24.0,
      );
      expect(
        ReaderLayoutMetrics.resolveTopPad(47.0, maxHeight: 844.0),
        47.0,
        reason: '刘海屏 47dp 是真实值，必须放行',
      );
    });

    test('小窗里的真实状态栏（37dp / 614dp 窗口）仍要放行', () {
      // 小窗高度只有 614dp，37dp 占 6%，远低于阈值，属于合法 inset。
      expect(
        ReaderLayoutMetrics.resolveTopPad(realTopPad, maxHeight: windowHeight),
        realTopPad,
      );
    });

    test('负值与非法窗口高不产生负 inset', () {
      expect(ReaderLayoutMetrics.resolveTopPad(-5.0, maxHeight: 800.0), 0.0);
      expect(
        ReaderLayoutMetrics.resolveTopPad(37.0, maxHeight: 0.0),
        0.0,
        reason: '窗口高还没就绪时无法判断 inset 合理性，交给上层 spinner 守卫',
      );
    });

    test('阈值边界两侧行为明确（阈值本身放行、超过丢弃）', () {
      const limit = windowHeight * ReaderLayoutMetrics.maxTopPadFraction;
      expect(
        ReaderLayoutMetrics.resolveTopPad(limit, maxHeight: windowHeight),
        limit,
        reason: '恰好等于阈值仍属可用，不做多余误伤',
      );
      expect(
        ReaderLayoutMetrics.resolveTopPad(limit + 0.1, maxHeight: windowHeight),
        0.0,
      );
    });
  });

  group('端到端：脏帧不得再产出 0 高正文（SPINNER#1 的直接成因）', () {
    test('日志原始坏帧 384x614.4@614.4 现在算出健康正文高', () {
      final h = firstTextHeightFor(windowHeight, bogusTopPad);
      expect(
        h,
        greaterThan(0),
        reason: '这一帧算出 0 就会命中 SPINNER#1，而脏值不会自愈 → 永久转圈',
      );
      // 丢弃脏 inset 后应与同一窗口的健康帧（日志 20:41:40.904 那条）一致。
      expect(
        h,
        closeTo(514.4, 0.05),
        reason: '与真机健康帧 firstTextHeight=514.4 对齐，证明取值取对了',
      );
    });

    test('坏帧与健康帧算出同一个正文高（脏值不再影响结果）', () {
      expect(
        firstTextHeightFor(windowHeight, bogusTopPad),
        closeTo(firstTextHeightFor(windowHeight, 0.0), 0.001),
      );
    });

    test('全屏帧（853.3@37.0）结果一个像素都不许变', () {
      // 加固不能动线上所有用户的分页，否则阅读进度集体跳位。
      // 期望值 = 853.3 - (37+8+8) - 24 - 14 - 46（首页标题）。
      const expected = 853.3 - (37.0 + 8.0 + 8.0) - 24.0 - 14.0 - 46.0;
      expect(firstTextHeightFor(853.3, realTopPad), closeTo(expected, 0.001));
    });
  });

  group('源码级闸门：生产代码必须真的走 resolveTopPad', () {
    // 与本项目既有闸门同源：抽出纯函数只锁住函数本体，锁不住「调用点是否
    // 绕过它」。上一次实测「调用点写回原表达式」能骗过全部行为测试。
    final src = File('lib/novel/pages/reader_page.dart').readAsStringSync();
    final code = src
        .split('\n')
        .map((l) {
          final i = l.indexOf('//');
          return i < 0 ? l : l.substring(0, i);
        })
        .where((l) => l.trim().isNotEmpty)
        .join('\n');

    test('几何计算必须调用 resolveTopPad', () {
      expect(
        code.contains('ReaderLayoutMetrics.resolveTopPad('),
        isTrue,
        reason: '调用点绕过它 → 脏 inset 直接进算式，小窗永久转圈复活',
      );
    });

    test('不得再把裸 MediaQuery padding.top 直接当 topPad 用', () {
      expect(
        RegExp(
          r'final\s+topPad\s*=\s*MediaQuery\.of\(context\)\.padding\.top',
        ).hasMatch(code),
        isFalse,
        reason: '这正是 v1.14.1 现场的元凶形状（日志 topPad=614.4）',
      );
    });

    test('脏 inset 被丢弃时要留下日志，否则下一轮又是盲区', () {
      expect(
        code.contains('BOGUS_INSET'),
        isTrue,
        reason: '报障人无 adb，脏值是否发生过只能靠 App 内日志取证',
      );
    });
  });
}
