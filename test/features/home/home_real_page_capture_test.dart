library;

import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:box/features/home/data/ai_hot_models.dart';
import 'package:box/features/home/data/ai_hot_service.dart';
import 'package:box/features/home/data/continue_item.dart';
import 'package:box/features/home/data/continue_repository.dart';
import 'package:box/features/home/data/daily_news_service.dart';
import 'package:box/features/home/data/home_quick_action_prefs.dart';
import 'package:box/features/home/presentation/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

/// 抓**真实 HomePage widget** 的渲染结果，并量各区块的垂直占用。
///
/// 与 home_visual_golden_capture_test.dart 的区别很重要：那个文件是手工拼的
/// 「样例板」（sectionHeader(...) 一个个摆出来），它缺「已安装插件」和
/// 「AI HOT」两个真实区块，还多了一条原型标注「热闻空态（不可点、无箭头）」。
/// 拿它做布局审查会得出错误结论。这里直接 pump 真的 HomePage。
///
/// 跑法：HOME_REAL_CAPTURE=1 flutter test test/features/home/home_real_page_capture_test.dart

const _captureKey = ValueKey('home-real-capture');

/// 手机逻辑分辨率（iQOO / 红米 K80 都在这个量级）。
const _phone = Size(392, 850);

class _StubNewsService extends DailyNewsService {
  @override
  Future<DailyNewsFeed> fetch({
    int take = DailyNewsService.previewCount,
    bool forceRefresh = false,
  }) async => const DailyNewsFeed(
    items: [
      DailyNewsItem(
        title: '国内多地迎来降温，部分地区发布寒潮预警信号',
        url: 'https://example.com/1',
      ),
      DailyNewsItem(
        title: '新一代折叠屏手机发布，续航与铰链结构均有升级',
        url: 'https://example.com/2',
      ),
      DailyNewsItem(
        title: '某科技公司公布季度财报，营收同比增长超预期',
        url: 'https://example.com/3',
      ),
    ],
  );
}

class _StubAiHotService extends AiHotService {
  @override
  Future<AiHotFeed> fetchSelected({
    int take = AiHotService.previewCount,
    bool forceRefresh = false,
  }) async => const AiHotFeed(
    items: [
      AiHotItem(id: '1', title: 'OpenAI 发布新一代推理模型，数学能力显著提升'),
      AiHotItem(id: '2', title: '开源社区推出可本地运行的多模态大模型'),
      AiHotItem(id: '3', title: '国产 AI 芯片量产，推理成本下降四成'),
    ],
    attributionSource: 'AIHOT',
  );
}

class _StubContinueRepository extends ContinueRepository {
  _StubContinueRepository(this._items)
    : super(
        loadVideoHistory: () async => [],
        loadBookshelf: () async => [],
        loadNovelProgress: (_) async => null,
      );
  final List<ContinueItem> _items;
  @override
  Future<List<ContinueItem>> load() async => _items;
}

class _StubQuickActionPrefs extends HomeQuickActionPrefs {
  _StubQuickActionPrefs(this._ids);
  final List<String> _ids;
  @override
  Future<List<String>> readSelectedIds() async => _ids;
  @override
  Future<void> saveSelectedIds(List<String> ids) async {}
}

void main() {
  String? cjk;

  setUpAll(() async {
    final file = File('/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc');
    if (file.existsSync()) {
      final loader = FontLoader('WenQuanYi')
        ..addFont(Future.value(file.readAsBytesSync().buffer.asByteData()));
      await loader.load();
      cjk = 'WenQuanYi';
    }
  });

  testWidgets(
    '抓真实 HomePage 并量各区块垂直占用',
    (tester) async {
      tester.view.physicalSize = Size(_phone.width * 3, _phone.height * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      const continueItems = <ContinueItem>[
        ContinueItem(
          kind: ContinueKind.novel,
          id: 'n1',
          title: '诡秘之主',
          subtitle: '第 128 章 罪魁祸首',
          updatedAt: 3000,
          progress: 0.42,
        ),
        ContinueItem(
          kind: ContinueKind.video,
          id: 'v1',
          title: '狂飙',
          subtitle: '第 12 集',
          updatedAt: 2000,
          progress: 0.66,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: cjk),
          home: RepaintBoundary(
            key: _captureKey,
            child: HomePage(
              quickActionPrefs: _StubQuickActionPrefs(
                HomeQuickActionPrefs.defaultIds,
              ),
              continueRepository: _StubContinueRepository(continueItems),
              newsService: _StubNewsService(),
              aiHotService: _StubAiHotService(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // ── 量真实占用 ──
      final screenH = _phone.height;
      stdout.writeln('AUDIT screen_height=$screenH');
      for (final title in <String>[
        '快捷入口',
        '已安装插件',
        '继续使用',
        '资讯',
        '热闻',
      ]) {
        final f = find.text(title);
        if (f.evaluate().isEmpty) {
          stdout.writeln('AUDIT section="$title" rendered=NO');
          continue;
        }
        final r = tester.getRect(f.first);
        stdout.writeln(
          'AUDIT section="$title" y=${r.top.toStringAsFixed(1)} '
          'first_screen=${r.top < screenH}',
        );
      }

      // 内容总高度（滚动范围），用来算首屏占比
      final scrollable = find.byType(Scrollable).first;
      final pos = tester.state<ScrollableState>(scrollable).position;
      stdout.writeln(
        'AUDIT content_extent=${(pos.maxScrollExtent + screenH).toStringAsFixed(1)} '
        'max_scroll=${pos.maxScrollExtent.toStringAsFixed(1)}',
      );

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_captureKey),
      );
      final bytes = await tester.binding.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3.0);
        final data = await image.toByteData(format: ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      expect(bytes, isNotNull);

      final out = File('build/visual/home_real_filled.png');
      out.parent.createSync(recursive: true);
      out.writeAsBytesSync(bytes!);
      stdout.writeln('REAL_PNG=${out.absolute.path} bytes=${out.lengthSync()}');
    },
    skip: Platform.environment['HOME_REAL_CAPTURE'] != '1',
  );
}
