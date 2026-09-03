import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:box/novel/pages/reader/reader_layout_metrics.dart';
import 'package:box/novel/pages/reader/reader_paginator.dart';

/// 小窗（自由窗口 / 小窗模式）里小说正文一片空白的回归测试。
///
/// ## 真实取证（红米 K80 / HyperOS 录屏，用户提供）
///
/// 逐帧像素分析定位小窗真实边界（严格护眼绿判据 + 行列投影）：
/// 在 360x800 的录屏帧里，小窗只有 **90 x 144 px**，占屏 25.0% x 18.0%。
/// 6 倍原分辨率放大后看窗口内部：**只有护眼绿底 + 右下角橙色调试按钮，
/// 没有正文、没有 loading 圈、没有骨架屏灰条**。
///
/// 调试按钮是 `_buildReaderScaffold` 里 Stack 的兄弟节点
/// （reader_page.dart:1127），跟正文状态无关 —— 它在说明「阅读页活着，
/// 只是正文区什么都没画出来」。
///
/// K80 屏幕 2712x1220 px @ density 3.0 → 逻辑约 407 x 904 dp，
/// 于是小窗逻辑尺寸 ≈ **101.7 x 162.7 dp**。
///
/// ## 缺陷：clamp 把 fitWidth 往上抬，分页器按不存在的宽度切页
///
/// `_buildPagedReaderView`（reader_page.dart:933）：
///
/// ```dart
/// final fitWidth = (constraints.maxWidth - 40.0).clamp(200.0, 660.0);
/// ```
///
/// 小窗里 `maxWidth - 40 = 61.7`，被 `clamp` 的**下限 200 强行抬到 200.0**。
/// 分页器于是按「每行 200dp」去切页，以为一行能放约 10 个汉字；
/// 而 `ReaderPagedView` 的正文实际只有 `101.7 - 20 - 20 = 61.7dp` 宽
/// （padding 见 reader_paged_view.dart:117），一行只放得下约 3 个字。
///
/// 宽度对不上不会报错，只会让每一行都溢出被裁；配合正文高度只剩
/// 76.7~122.7dp（扣掉 46dp 标题块和上下 padding），可视区域小到
/// 一两行，用户看到的就是「一片空白，内容不刷新」。
///
/// clamp 的下限本意是防止 `fitWidth<=0` 让分页器死循环，
/// 但它把「窗口真的很窄」和「窗口尺寸还没就绪」混为一谈了。
///
/// ## 这组测试锁什么
///
/// 全部打在真实的 `ReaderPaginator` 上，不用复刻类自证：
/// 1. 分页宽度必须能反映真实窄宽度，而不是被抬到 200 后与 200dp 结果雷同
/// 2. 窄宽 + 矮高的极端组合仍要产出非空页，且每页短到能塞进小窗
void main() {
  const sample = _sample;

  ReaderPaginationRequest req({
    required double fitWidth,
    required double height,
  }) =>
      ReaderPaginationRequest(
        bookId: 'b1',
        chapterIndex: 0,
        content: sample,
        fitWidth: fitWidth,
        firstPageHeight: height,
        normalPageHeight: height,
        fontSize: 18,
        lineHeight: 1.6,
      );

  setUp(ReaderPaginator.clearCache);

  List<String> pagesFor(double fitWidth, double height) {
    ReaderPaginator.clearCache();
    final r = ReaderPaginator.paginateIncremental(
      req(fitWidth: fitWidth, height: height),
      chunkSize: 400,
    );
    return r.firstChunk;
  }

  // 这一组直接打在生产代码 ReaderLayoutMetrics.resolveFitWidth 上。
  // 上一版测试只测 ReaderPaginator，把 clamp 下限从 1 改回 200（原 bug）
  // 依然全绿 —— 对真正出错的那行零区分力。变异验证抓出来后补上这组。
  group('排版宽度不能被下限抬高（小窗白屏的真正那行）', () {
    test('K80 小窗 101.7dp 必须得到 61.7dp，而不是被抬到 200', () {
      final w = ReaderLayoutMetrics.resolveFitWidth(101.7);
      expect(w, closeTo(61.7, 0.001),
          reason: '若返回 200 说明又加了下限，分页器会按一行 10 字切页，'
              '而正文只放得下 3 字 —— 正是小窗一片空白的根因');
      expect(w, lessThan(200.0));
    });

    test('一系列小窗宽度都必须原样透传（减去 40 padding）', () {
      for (final maxW in <double>[60.0, 101.7, 150.0, 200.0, 239.0]) {
        expect(
          ReaderLayoutMetrics.resolveFitWidth(maxW),
          closeTo(maxW - 40.0, 0.001),
          reason: 'maxWidth=$maxW 被改写了，说明存在不该有的下限',
        );
      }
    });

    test('宽度未就绪（<=40，减完 <=0）返回 0，交给上层 spinner 守卫', () {
      for (final maxW in <double>[0.0, 20.0, 40.0, -5.0]) {
        expect(ReaderLayoutMetrics.resolveFitWidth(maxW), 0.0,
            reason: 'maxWidth=$maxW 应判为尺寸未就绪');
      }
    });

    test('超宽屏仍然封顶 660，避免一行太长难读', () {
      expect(ReaderLayoutMetrics.resolveFitWidth(2000.0), 660.0);
      expect(ReaderLayoutMetrics.resolveFitWidth(700.0), 660.0);
      // 恰好落在上限边界内的不受影响
      expect(ReaderLayoutMetrics.resolveFitWidth(699.0), closeTo(659.0, 0.001));
    });
  });

  // 源码级闸门：光有 resolveFitWidth 不够 —— 调用点如果被改回
  // `(maxWidth - 40).clamp(200.0, 660.0)`，analyze 和上面所有测试都照样绿，
  // 而小窗白屏 bug 会原样复活。这里直接盯生产源码。
  group('reader_page 必须真的走 resolveFitWidth', () {
    final src = File('lib/novel/pages/reader_page.dart').readAsStringSync();

    test('排版宽度由 ReaderLayoutMetrics.resolveFitWidth 计算', () {
      expect(
        src.contains('ReaderLayoutMetrics.resolveFitWidth('),
        isTrue,
        reason: '调用点被改回手写 clamp 了？小窗白屏会复活',
      );
    });

    test('源码里不得再出现把排版宽抬到 200 的下限', () {
      final offenders = RegExp(r'clamp\(\s*200(\.0)?\s*,')
          .allMatches(src)
          .map((m) => m.group(0))
          .toList();
      expect(offenders, isEmpty,
          reason: '发现 clamp(200, ...)：这正是小窗把 61.7dp 抬到 200dp 的元凶');
    });

    test('不得再硬编码 46/24 标题高度算正文高（应走 metrics）', () {
      expect(
        src.contains('paddingTotal - 46.0 - 24.0'),
        isFalse,
        reason: '硬编码标题高度会让 <=124dp 的窗口算出负正文高而永久 spinner',
      );
    });
  });

  group('小窗真实尺寸下分页必须跟着窄宽度走', () {
    // K80 小窗实测：101.7 x 162.7 dp
    // 正文可用宽 = 101.7-40 = 61.7dp，可用高 ≈ 76.7~122.7dp
    const narrowWidth = 61.7;
    const narrowHeight = 100.7;

    test('61.7dp 宽切出的首页，必须明显短于 200dp 宽切出的首页', () {
      final narrow = pagesFor(narrowWidth, narrowHeight);
      final atClampFloor = pagesFor(200.0, narrowHeight);

      expect(narrow, isNotEmpty);
      expect(atClampFloor, isNotEmpty);

      expect(
        narrow.first.length,
        lessThan(atClampFloor.first.length),
        reason: '61.7dp 宽每行只放约 3 字，200dp 放约 10 字，首页字数必须差一截。'
            '若两者相等，说明分页对真实窄宽不敏感 —— 生产代码正是被 '
            'clamp(200,660) 抬到 200 才画不出内容',
      );
    });

    test('首页字数要能塞进小窗可视区（约 3 行 x 3 字）', () {
      final narrow = pagesFor(narrowWidth, narrowHeight);
      // 61.7dp 宽 / 100.7dp 高，18 号字行高 1.6 → 约 3 行，每行约 3 字
      expect(
        narrow.first.length,
        lessThan(40),
        reason: '小窗一页塞不下 40 字。首页过长意味着大部分正文被裁在可视区外，'
            '用户看到的就是「空白 / 不刷新」',
      );
    });

    test('极窄宽度仍必须产出非空页，不能空转', () {
      for (final w in <double>[61.7, 40.0, 20.0, 1.0]) {
        final pages = pagesFor(w, narrowHeight);
        expect(pages, isNotEmpty, reason: 'fitWidth=$w 产出空页 → 正文区永久空白');
        expect(pages.first, isNotEmpty, reason: 'fitWidth=$w 首页是空串');
      }
    });

    test('极矮高度仍必须产出非空页', () {
      for (final h in <double>[122.7, 100.7, 76.7, 38.7, 10.0]) {
        final pages = pagesFor(narrowWidth, h);
        expect(pages, isNotEmpty, reason: 'height=$h 产出空页 → 正文区永久空白');
        expect(pages.first, isNotEmpty, reason: 'height=$h 首页是空串');
      }
    });

    test('所有页拼起来不丢字（窄窗下也不能吞正文）', () {
      ReaderPaginator.clearCache();
      final r = ReaderPaginator.paginateIncremental(
        req(fitWidth: narrowWidth, height: narrowHeight),
        chunkSize: 100000,
      );
      final all = <String>[...r.firstChunk];
      while (!r.remaining.isDone) {
        all.addAll(r.remaining.nextChunk());
      }
      final joined = all.join();
      expect(
        joined.replaceAll(RegExp(r'\s'), '').length,
        sample.replaceAll(RegExp(r'\s'), '').length,
        reason: '窄窗分页后总字数必须守恒，丢字等于内容被吃掉',
      );
    });
  });

  group('尺寸非法时的兜底不能被误用来掩盖窄窗', () {
    test('fitWidth<=0 退化成整章一页', () {
      for (final bad in <double>[0.0, -5.0]) {
        ReaderPaginator.clearCache();
        final r = ReaderPaginator.paginateIncremental(
          req(fitWidth: bad, height: 500),
        );
        expect(r.firstChunk, isNotEmpty);
        expect(r.remaining.isDone, isTrue,
            reason: 'fitWidth=$bad 应一次性吐完，作为「尺寸未就绪」的安全兜底');
      }
    });

    test('合法但极窄的宽度走正常分页，不该退化成整章一页', () {
      ReaderPaginator.clearCache();
      final r = ReaderPaginator.paginateIncremental(
        req(fitWidth: 61.7, height: 100.7),
        chunkSize: 3,
      );
      expect(r.firstChunk.length, 3,
          reason: '窄窗应正常切成多页，而不是塞成一页蒙混过关');
      expect(r.remaining.isDone, isFalse);
    });
  });
}

const String _sample = '第一章 风起\n\n'
    '沈砚之推开窗，江面上的雾还没散尽。他在这座城里住了十七年，'
    '从没见过这样的雾——像有人把整条江的呼吸都攥在手里，攥得发白。\n\n'
    '楼下传来敲门声，三长两短，是老周的规矩。他把桌上那封没写完的信折了两折，'
    '塞进砚台底下，这才去开门。\n\n'
    '"东西到了。"老周站在门外，肩上的雪化了一半，'
    '"但送东西的人没回来。"\n\n'
    '沈砚之侧身让他进来，顺手把门闩上。屋里那盏油灯忽地矮了一截，'
    '像是被这句话压住了。\n\n'
    '"几时的事？"\n\n'
    '"昨夜三更。城门那边有人看见他往北去了，之后就没了消息。"'
    '老周从怀里掏出一只油纸包，放在桌上，'
    '"这是他留在渡口的，托摆渡的老汉转交。"\n\n'
    '油纸包很轻，拆开是半张烧过的纸，边缘焦黑，'
    '只剩中间几个字还认得出：已换，勿信旧图。\n\n'
    '沈砚之盯着那几个字看了很久，忽然笑了一声，'
    '把纸片凑到灯上点了。火苗舔上去的时候，他说："那就按新的来。"\n\n'
    '窗外的雾更浓了，江水在雾底下走，声音闷得像隔着一层棉被。';
