import 'dart:io';

import 'package:box/video/models/video_source.dart';
import 'package:box/video/models/vod_item.dart';
import 'package:box/video/pages/detail/detail_info_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 详情页观感优化的护栏。
///
/// 起因：真机截图被指「看着很别扭」，逐处对齐后发现三个具体问题 ——
/// ① 单片时标题下「正在播放 · X」与唯一那个橙色剧集胶囊重复；
/// ② 「线路」行有图标+文字、剧集行直接铺满，两行起点差约 54px；
/// ④ 影片资料每行一个浅灰描边方框、值一律 w900，像方块阵又重。
///
/// 这类问题不会让测试变红，只能靠**结构性断言**防回退：
/// 结构断言（间距/对齐/重复）用源码与渲染树验证，不靠感觉。
void main() {
  String readLib(String path) => File('lib/$path').readAsStringSync();

  const source = VideoSource(
    id: 'quantum',
    name: '量子资源',
    url: 'https://example.com/api.php/provide/vod/',
    detailUrl: 'https://example.com/api.php/provide/vod/',
  );

  VodItem buildDetail() => VodItem(
    vodId: 1,
    vodName: '欢迎来龙餐馆',
    typeName: '战争片',
    vodRemarks: 'HD',
    vodTime: '2026-08-31 09:10:07',
    vodArea: '中国大陆',
    vodLang: '汉语普通话,阿拉伯语',
    vodDirector: '文牧野',
    vodContent: '剧情简介第一段。\n剧情简介第二段。',
  );

  group('④ 影片资料改成一张表（不再是一排方框）', () {
    Future<void> pumpCard(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DetailInfoCard(detail: buildDetail(), source: source),
            ),
          ),
        ),
      );
    }

    testWidgets('⑥ 不再出现「来源」行（资源名只在顶部标题卡说一次）', (tester) async {
      await pumpCard(tester);
      expect(find.textContaining('来源'), findsNothing);
      expect(find.textContaining('量子资源'), findsNothing);
    });

    testWidgets('标签不带全角冒号，值渲染在标签右侧', (tester) async {
      await pumpCard(tester);
      expect(find.text('分类'), findsOneWidget);
      expect(find.text('分类：'), findsNothing);
      expect(find.text('战争片'), findsOneWidget);
      expect(find.text('导演'), findsOneWidget);
      expect(find.text('文牧野'), findsOneWidget);
    });

    testWidgets('行与行之间用 1px 分隔线：n 行 → n-1 条线', (tester) async {
      await pumpCard(tester);
      // 本用例的数据有 5 行：分类 / 更新 / 时间 / 地区·语言 / 导演（无主演）。
      final dividers = tester
          .widgetList<Divider>(find.byType(Divider))
          .where((d) => d.thickness == 1)
          .toList();
      expect(dividers.length, 4);
    });

    testWidgets('值的字重不再是 w900（方块阵之外的另一半「重」）', (tester) async {
      await pumpCard(tester);
      final value = tester.widget<Text>(find.text('战争片'));
      expect(value.style?.fontWeight, isNot(FontWeight.w900));
      expect(value.style?.fontWeight, FontWeight.w600);
    });

    testWidgets('④ 长值允许两行，「主演」不再只剩下前两个名字', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DetailInfoCard(
                detail: VodItem(
                  vodId: 2,
                  vodName: '欢迎来龙餐馆',
                  vodActor: '沈腾,蒋奇明,奥马尔·谢里夫,李治廷,王传君,张子枫',
                ),
                source: source,
              ),
            ),
          ),
        ),
      );
      final actor = tester.widget<Text>(find.textContaining('沈腾'));
      expect(actor.maxLines, 2);
    });
  });

  group('② / ⑦ 详情页源码结构护栏', () {
    test('剧集行走 _LabeledRow；线路已上提到播放器下方（第四轮重排）', () {
      // 第四轮把线路从"选集卡里的一行"改成"贴在播放器下面的一条".
      // 原因：换线路是**播放动作**，和"选第几集"是两件事，塞在选集卡里
      // 要先展开 Tab 再往下找，多两步。
      //
      // 因此这条断言从"两行都要 _LabeledRow"改成：
      //   * 剧集行仍走 _LabeledRow（保证与"选集"标题左对齐）；
      //   * 线路改用 _buildLineStrip，且**紧跟在播放器之后**。
      final page = readLib('video/pages/video_detail_page.dart');
      expect(
        RegExp(r"_LabeledRow\(\s*label: '剧集'").hasMatch(page),
        isTrue,
        reason: '剧集行必须走 _LabeledRow，否则和上方标题错开',
      );
      expect(
        page.contains('_buildLineStrip(controller)'),
        isTrue,
        reason: '线路改成独立的紧凑条',
      );
      final playerIdx = page.indexOf('_buildPlayerShell(controller, detail)');
      final stripIdx = page.indexOf('_buildLineStrip(controller)');
      expect(
        playerIdx,
        greaterThan(0),
        reason: '没找到播放器调用点，断言失效',
      );
      expect(
        stripIdx,
        greaterThan(playerIdx),
        reason: '线路条要紧跟在播放器之后（播放中换线的动作）',
      );
    });

    test('⑦ 顶部不再用「全部线路集数之和」当集数', () {
      final page = readLib('video/pages/video_detail_page.dart');
      expect(
        page.contains(r'$totalEpisodes'),
        isFalse,
        reason: '那是最容易和单条线路集数对不上的写法（单片会被写成 2 集）',
      );
      expect(
        page.contains(r'fold<int>'),
        isFalse,
        reason: '集数求和的老写法应已删除，需要集数时按当前线路算',
      );
    });

    test('① 选集卡标题下不挂任何副标题（单片/多集都不挂）', () {
      // 这条的前身是「单片时不再显示『正在播放 · X』」—— 当时副标题挂在
      // `if (!isSingleEpisode)` 分支下，所以断言那段分支存在。
      //
      // 第六轮（去重）把副标题整块删了（「当前线路 N 集」与「共 N 集」重复），
      // 于是"分支存在"这个断言失去意义。现在锁的是**结果**：
      // 选集卡标题后面既没有「正在播放 ·」，也没有「当前线路 N 集」。
      final page = readLib('video/pages/video_detail_page.dart');
      final panelIdx = page.indexOf('Widget _buildPlaybackPanel(');
      final panelEnd = page.indexOf('Widget _buildEpisodeSection(');
      expect(panelIdx, greaterThan(0));
      expect(panelEnd, greaterThan(panelIdx));
      final panelSrc = page.substring(panelIdx, panelEnd);

      expect(
        panelSrc.contains("'正在播放 · "),
        isFalse,
        reason: '网格里当前集已橙色高亮，副标题再说一遍是重复',
      );
      expect(
        panelSrc.contains("'当前线路 "),
        isFalse,
        reason: '集数只保留「共 N 集」一处',
      );
    });

    test('③ 线路条行高紧凑（32，别又变回那个空荡的 42）', () {
      // 第四轮：线路从选集卡里的行（34）改成贴播放器的条（32）。
      // 共同点是不许回到 42 —— 两条线路用 42 会显得那一片很空。
      final page = readLib('video/pages/video_detail_page.dart');
      expect(
        RegExp(r'height: 32,').hasMatch(page),
        isTrue,
        reason: '线路条行高应保持紧凑',
      );
      expect(
        RegExp(r'height: 42,').hasMatch(page),
        isFalse,
        reason: '42 是上一轮修掉的空荡高度，别回来',
      );
    });
  });

  group('第二轮（①②③④⑤⑥⑦）护栏', () {
    test('① 同一屏只留一个刷新入口：选集卡那个已删', () {
      final page = readLib('video/pages/video_detail_page.dart');
      final refreshIcons = RegExp(r'Icons\.refresh_rounded').allMatches(page);
      expect(
        refreshIcons.length,
        2,
        reason:
            '剩下的两个应该只有：顶部导航的刷新、错误页的「重试」；'
            '选集卡右上角那个和顶部是同一个动作，不该再出现',
      );
    });

    test('② 三处卡片标题都走 AppSectionTitle', () {
      expect(
        readLib(
          'video/pages/video_detail_page.dart',
        ).contains("AppSectionTitle('选集')"),
        isTrue,
        reason: '选集标题要和影片资料/剧情简介同一套样式',
      );
      expect(
        readLib(
          'video/pages/detail/detail_info_card.dart',
        ).contains('AppSectionTitle'),
        isTrue,
      );
    });

    test('③ 区块间距用 token，不再散落 10/12/36', () {
      final page = readLib('video/pages/video_detail_page.dart');
      expect(RegExp(r'SizedBox\(height: 36\)').hasMatch(page), isFalse);
      expect(page.contains('AppTokens.spaceMd'), isTrue);
      expect(page.contains('AppTokens.space2xl'), isTrue);
    });

    test('⑦ 播放器与卡片圆角统一 20', () {
      final page = readLib('video/pages/video_detail_page.dart');
      expect(
        RegExp(r'BorderRadius\.circular\(22\)').hasMatch(page),
        isFalse,
        reason: '播放器外壳的 22 已并入 20',
      );
    });
  });

  /// ② 线路「最近取不到流」要在**点进去之前**看出来，且默认不落在它上面。
  /// 行为判据在 `test/video/line_reachability_test.dart`；这里只钉界面接线，
  /// 免得哪天重构把标注或默认跳过的落点弄丢（这两处都在私有 State 里）。
  group('第三轮（2026-10-18）：序号优先 + 权重修正', () {
    test('剧集格子：序号与副注两行，不再把整串塞一行截断', () {
      final src = readLib('video/pages/video_detail_page.dart');
      expect(
        src.contains('parseEpisodeLabel(label)'),
        isTrue,
        reason: '集名要先拆成「序号 + 其余文字」，否则长名字会把序号截掉',
      );
      expect(
        src.contains('parts.number ?? label'),
        isTrue,
        reason: '抽不到序号时回落到原名（不猜编号）',
      );
    });

    test('当前集用描边而不是渐变填充（把橙色强调留给"这一集"）', () {
      final src = readLib('video/pages/video_detail_page.dart');
      // 剧集格子选区不应再有 LinearGradient 做背景
      final cellIdx = src.indexOf('class _EpisodeCell');
      final cellSrc = src.substring(cellIdx, cellIdx + 2000);
      expect(
        cellSrc.contains('LinearGradient'),
        isFalse,
        reason: '渐变填充视觉太重，和线路 chip 的选中态撞在一起',
      );
      expect(
        cellSrc.contains('0xFFFB923C'),
        isTrue,
        reason: '改用橙色描边标识当前集',
      );
    });

    test('线路不再是"大胶囊抢在选集前"——它已收成播放器下的一条', () {
      // 第三轮的做法是「剧集在前、线路在后」，都塞在选集卡里。
      // 第四轮改了：线路**上提到播放器下方**（播放动作），选集卡里只剩剧集。
      //
      // 原意图「次要信息不压主要信息」仍然成立，但实现方式变了：
      // 线路不再是带渐变的大胶囊，而是 32dp 高的紧凑条，且不在选集卡里。
      final src = readLib('video/pages/video_detail_page.dart');
      expect(
        src.contains("label: '剧集'"),
        isTrue,
        reason: '选集卡里仍有剧集行',
      );
      // 选集卡（_buildPlaybackPanel）内部不该再出现线路选择
      final panelIdx = src.indexOf('Widget _buildPlaybackPanel(');
      final panelEnd = src.indexOf('Widget _buildEpisodeSection(');
      expect(panelIdx, greaterThan(0));
      expect(panelEnd, greaterThan(panelIdx));
      final panelSrc = src.substring(panelIdx, panelEnd);
      expect(
        panelSrc.contains('_buildLineStrip'),
        isFalse,
        reason: '线路条在播放器下方，不在选集卡内部 —— 否则就是"又回到卡里"',
      );
    });

    test('展开按钮文案是「展开剩余 N 集」，不再重复总数', () {
      final src = readLib('video/pages/video_detail_page.dart');
      expect(
        src.contains('展开剩余 '),
        isTrue,
        reason: '「展开全部 (28)」与旁边「共 28 集」两个 28 并列，容易误读',
      );
      expect(
        src.contains("'展开全部 ("),
        isFalse,
      );
    });

    test('选集卡副标题不再重复「正在播放 · X」，也不再重复集数', () {
      // 范围要限定在**选集卡内部**：收起播放器后的迷你条也会写「正在播放 · X」，
      // 但那里没有橙色高亮的集数胶囊作视觉提示，不算重复 —— 全文件禁用这个词
      // 会把正常用法一起误杀。
      final src = readLib('video/pages/video_detail_page.dart');
      final panelIdx = src.indexOf('Widget _buildPlaybackPanel(');
      final panelEnd = src.indexOf('Widget _buildEpisodeSection(');
      expect(panelIdx, greaterThan(0));
      expect(panelEnd, greaterThan(panelIdx));
      final panelSrc = src.substring(panelIdx, panelEnd);

      expect(
        panelSrc.contains("'正在播放 · "),
        isFalse,
        reason: '网格里当前集已高亮，同一件事说两遍',
      );

      // 第六轮（去重）：第三轮把副标题换成「当前线路 N 集」，但那个 N 与
      // 同一张卡下方的「共 N 集」、以及页面头部的「全 N 集」是同一个数
      // （都取当前线路的 episodes.length）—— 一屏三遍。
      // 现在标题下不再挂副标题，集数只留「共 N 集」一处。
      expect(
        panelSrc.contains('当前线路 \${episodes.length} 集'),
        isFalse,
        reason: '集数已经在「共 N 集」那里写过，标题下不该再说一遍',
      );
      // 「共 N 集」画在 _buildEpisodeSection 里（选集卡内部、正序按钮那一行），
      // 不在这段 substring 的范围内 —— 要整文件找。
      expect(
        src.contains('共 \$total 集'),
        isTrue,
        reason: '集数保留在「共 N 集」（与正序按钮同一行，是工具栏）',
      );
    });

    test('线路技术名改成「线路 N」+ 原名副注', () {
      final src = readLib('video/pages/video_detail_page.dart');
      expect(src.contains('lineDisplayName('), isTrue);
      expect(src.contains('lineSubName('), isTrue);
    });
  });

  group('② 线路可用性前置标注', () {
    test('线路 chip 带「取不到流」标记，且标注仍可点（不是禁用）', () {
      // 第四轮起线路条自己构造 chip，参数名从 isUnreachable 直接落到
      // _PlaybackChip 的 unreachable 字段（少一层中转）。
      final page = readLib('video/pages/video_detail_page.dart');
      expect(
        page.contains('unreachable: controller.isLineRecentlyUnreachable(index)'),
        isTrue,
      );
      expect(page.contains('Icons.wifi_off_rounded'), isTrue);
      // chip 仍然把 onTap 传下去 —— 标记是前置告知，不拦用户手动选。
      expect(page.contains('onTap: () => controller.selectLine(index)'), isTrue);
      expect(
        readLib(
          'video/pages/video_detail_page.dart',
        ).contains('child: InkWell('),
        isTrue,
        reason: '_PlaybackChip 用 InkWell 承载点击，标注不改变可点性',
      );
    });

    test('详情页把「最近取不到流」判据接进 chip 行', () {
      final page = readLib('video/pages/video_detail_page.dart');
      expect(
        page.contains('controller.isLineRecentlyUnreachable(index)'),
        isTrue,
        reason: '线路条仍要按"最近取不到流"打标',
      );
    });

    test('默认选线跳过被标记的线路，但全被标记时忽略标记', () {
      final controller = readLib(
        'video/controller/video_detail_controller.dart',
      );
      expect(controller.contains('_isLineUnreachable(lines[index])'), isTrue);
      expect(
        controller.contains(
          'final candidates = fresh.isEmpty ? playable : fresh;',
        ),
        isTrue,
        reason: '全被标记时要退回原判据，别把用户锁死',
      );
    });

    test('线路记忆不阻塞详情加载（不得在 loadDetail 里 await 存储）', () {
      final controller = readLib(
        'video/controller/video_detail_controller.dart',
      );
      expect(
        controller.contains('await LineReachabilityStore.ensureLoaded()'),
        isFalse,
        reason: '存储慢一步会把详情页永远停在 loading（实测 pumpAndSettle 超时）',
      );
      expect(
        controller.contains('unawaited(LineReachabilityStore.ensureLoaded())'),
        isTrue,
      );
    });
  });
}
