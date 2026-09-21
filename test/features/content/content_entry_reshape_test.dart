import 'dart:io';

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/content/domain/warehouse_cleanup.dart';
import 'package:box/features/content/domain/warehouse_models.dart';
import 'package:box/features/tools/application/tool_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内容页重构契约（用户 2026-09-06 决策）：
///
///  1. 入口六合四 —— 只留 影视 / 小说 / 漫画 / 音乐
///  2. 「导入资源」卡与收藏库 ＋ 一起撤掉，手填存量数据一起清掉
///  3. OpenLibrary 搜索挪去工具页
///  4. 音乐 = 本地播放 + 在线源爬取下载（不是「本地收藏」）
///
/// 这里锁的是**数据与结构契约**，UI 布局由 widget 测试另测。
void main() {
  group('A1 入口六合四', () {
    test('入口网格只剩四个卡片，且不再有「导入资源」「小说搜索」「书架」', () {
      final src = _read(
        'lib/features/content/presentation/widgets/warehouse_widgets.dart',
      );
      final grid = _classBody(src, 'ContentEntryGrid');
      expect(grid, isNotEmpty, reason: 'ContentEntryGrid 不存在了？结构变了要同步改测试');

      // 只取入口卡（AppCompactActionCard）的 title，不能扫全类：
      // AppSectionHeader 也有 title: '内容入口'，一起扫进来会让断言永远失败。
      final titles = RegExp(
        r"AppCompactActionCard\(\s*title:\s*'([^']+)'",
      ).allMatches(grid).map((m) => m.group(1)!).toList();

      expect(
        titles,
        equals(['影视', '小说', '漫画', '音乐']),
        reason: '用户要求只留四个入口：影视/小说/漫画/音乐',
      );

      // 撤掉的三个旧入口不许残留（同样先剥注释，避免注释提及即误判）
      final gridCode = _stripComments(grid);
      // '书架' 带引号精确匹配，不会和小说/漫画副标题 '书架与阅读' 撞车
      for (final gone in ['导入资源', '小说搜索', '书架']) {
        expect(
          gridCode.contains("'$gone'"),
          isFalse,
          reason: '「$gone」应已从入口网格撤掉',
        );
      }
    });

    test('音乐副标题不得再写「本地收藏」——音乐要做本地播放+在线源下载', () {
      final src = _read(
        'lib/features/content/presentation/widgets/warehouse_widgets.dart',
      );
      // 去掉注释再判：解释「不能写本地收藏」的注释本身含这四个字，
      // 不剥注释的话源码闸门会假红（或改坏后假绿）。
      final grid = _stripComments(_classBody(src, 'ContentEntryGrid'));

      // 找音乐卡那一段
      final musicIdx = grid.indexOf("title: '音乐'");
      expect(musicIdx, greaterThan(-1));
      final musicCard = grid.substring(
        musicIdx,
        (musicIdx + 400).clamp(0, grid.length),
      );

      expect(
        musicCard.contains('本地收藏'),
        isFalse,
        reason: '音乐不再是「仓库的一个收藏分类」，副标题必须反映真实规划（本地播放）',
      );
    });
  });

  group('A2 撤掉手填入口并清掉存量', () {
    test('warehouse_tab 不再有 _showAddDialog / _showQuickImport / _showCategoryPicker',
        () {
      final src = _read(
        'lib/features/content/presentation/warehouse_tab.dart',
      );
      for (final gone in [
        '_showAddDialog',
        '_showQuickImport',
        '_showCategoryPicker',
      ]) {
        expect(
          src.contains(gone),
          isFalse,
          reason: '手填收藏入口应整体撤掉，$gone 仍在',
        );
      }
    });

    test('存在一次性清理器，且只清 warehouse_center 命名空间', () {
      // 同样先剥注释：清理器的文档注释会提到「不碰 bookshelf」，
      // 直接扫原文会把这句解释当成越界代码。
      final src = _stripComments(
        _read('lib/features/content/domain/warehouse_cleanup.dart'),
      );
      expect(
        src.contains('warehouse_center'),
        isTrue,
        reason: '清理必须指名 warehouse_center，不能误伤别的 namespace',
      );
      // 不许出现书架/小说侧的存储名 —— 那些数据不属于手填收藏
      for (final forbidden in ['bookshelf', 'novel_', 'video_favorites_box']) {
        expect(
          src.contains(forbidden),
          isFalse,
          reason: '清理器不得触碰 $forbidden —— 那是真实书架/影视数据',
        );
      }
    });
  });

  group('A2 清理行为：只清手填，不碰书架', () {
    test('清理后四个分类的手填条目全部消失', () async {
      final cache = CacheStore.inMemory('warehouse_center');
      final store = WarehouseStore(cache: cache);

      for (final c in WarehouseCategory.values) {
        await store.add(_item('手填-${c.name}', c));
      }
      // 落盘确认
      for (final c in WarehouseCategory.values) {
        expect(await store.load(c), hasLength(1));
      }

      final removed = await cache.clear();
      expect(removed, greaterThan(0), reason: '应确实删掉了条目');

      for (final c in WarehouseCategory.values) {
        expect(
          await store.load(c),
          isEmpty,
          reason: '${c.name} 的手填数据应已清空',
        );
      }
    });

    test('清理只删手填条目，非手填来源必须原样保留', () async {
      // 变异测试暴露的缺口：如果 purge 无条件清空整个 namespace，
      // 上面那条「手填数据应清空」的断言照样过 —— 但真实数据会被连带删掉。
      // 这里显式钉住边界：同一分类里混入非手填来源时，它必须活下来。
      final cache = CacheStore.inMemory('warehouse_center');
      final store = WarehouseStore(cache: cache);

      await store.add(_item('手填条目', WarehouseCategory.books));
      await store.add(
        _item('书架条目', WarehouseCategory.books, sourceLabel: '书架'),
      );
      expect(await store.load(WarehouseCategory.books), hasLength(2));

      final removed = await WarehouseCleanup(store: store).run();
      expect(removed, 1, reason: '只应删掉那 1 条手填条目');

      final left = await store.load(WarehouseCategory.books);
      expect(left, hasLength(1), reason: '非手填条目被连带删除了');
      expect(left.single.title, '书架条目');
      expect(left.single.sourceLabel, '书架');
    });

    test('清理是幂等的：再跑一次删 0 条', () async {
      final cache = CacheStore.inMemory('warehouse_center');
      final store = WarehouseStore(cache: cache);
      await store.add(_item('手填条目', WarehouseCategory.books));

      final cleanup = WarehouseCleanup(store: store);
      expect(await cleanup.run(), 1);
      expect(await cleanup.run(), 0, reason: '第二次应无事可做');
    });

    test('books 分类的书架来源条目不经过 WarehouseStore（清理伤不到它）', () {
      final src = _read(
        'lib/features/content/presentation/warehouse_tab.dart',
      );
      // 书架数据来自 NovelModule.bookshelf，与 _store 是两条通道
      expect(
        src.contains('NovelModule.bookshelf'),
        isTrue,
        reason: '书架实时数据通道应保留 —— 清理只针对手填的 CacheStore',
      );
    });
  });

  group('OpenLibrary 搜索挪去工具页', () {
    test('内容页不再直接跳 ApiHubPage(initialTool: books)', () {
      final src = _read(
        'lib/features/content/presentation/warehouse_tab.dart',
      );
      expect(
        RegExp(r"""initialTool:\s*'books'""").hasMatch(src),
        isFalse,
        reason: 'OpenLibrary 图书搜索按用户决策挪去工具页',
      );
    });

    test('工具目录里有一条指向图书搜索的可用工具', () {
      // 这里**故意不再正则扒源码**。旧写法是 grep `kAvailableToolNames = {...}`
      // 里有没有「图书搜索」四个字 —— 源码里出现了字符串就判绿，而当时它指向的
      // `books` 面板并不存在，点下去开出天气，这条测试却一直是绿的。
      // 改为直接调真实 API：进了映射表才算可用，去向由 tool_target_wiring_test
      // 逐个核对是否真实存在。
      expect(
        isToolAvailable('图书搜索'),
        isTrue,
        reason: '图书搜索已接线，必须在 kToolTargets 里',
      );
      expect(
        kAvailableToolNames,
        contains('图书搜索'),
        reason: '可用名单必须派生出图书搜索',
      );

      final target = toolTargetOf('图书搜索');
      expect(
        target,
        isA<ApiHubToolTarget>(),
        reason: '图书搜索应指向 API 能力中心的面板',
      );
      expect((target! as ApiHubToolTarget).toolId, 'books');
    });
  });
}

WarehouseItem _item(
  String title,
  WarehouseCategory c, {
  String sourceLabel = '手动收藏',
}) => WarehouseItem(
  id: title,
  title: title,
  subtitle: '',
  coverUrl: '',
  detailUrl: 'https://example.com/$title',
  meta: '',
  category: c,
  sourceLabel: sourceLabel,
  createdAt: DateTime.now().millisecondsSinceEpoch,
);

String _read(String path) {
  final f = File(path);
  if (!f.existsSync()) fail('找不到 $path');
  return f.readAsStringSync();
}

/// 去掉 `//` 行注释。
///
/// 源码闸门类断言必须先剥注释：解释性注释里常引用「不该出现的字符串」
/// （例如说明「副标题不能写本地收藏」），不剥就会假红/假绿。
String _stripComments(String src) => src
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

/// 取出 `class <name>` 到下一个顶层 `class ` 之间的正文。
String _classBody(String src, String name) {
  final start = src.indexOf('class $name');
  if (start < 0) return '';
  final next = src.indexOf('\nclass ', start + 1);
  return src.substring(start, next < 0 ? src.length : next);
}
