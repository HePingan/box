// 播放器「收起」的护栏。
//
// 这件事只有一个关键风险：**收起不能中断正在播的音频**。
// 用户点「收起播放器」是为了腾出空间翻选集，不是要停播。
//
// 实现上必须“视觉收起”而不是“销毁重建” —— `VideoPlayContainer` 的 state
// 里握着解码器与播放进度，一旦换 key 或移出树，播放就断了。
// 所以这里锁住三条：
//   1. 收起时播放器**仍在 widget 树里**（Offstage，不是被删掉）
//   2. 收起/展开不改变播放器的 key
//   3. 收起态有一个能点回来、且显示当前集名的迷你条
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String page;

  setUpAll(() {
    page = File('lib/video/pages/video_detail_page.dart').readAsStringSync();
  });

  group('收起是"视觉收起"，不销毁播放器', () {
    test('收起态用 Offstage 包住播放器，而不是条件渲染掉', () {
      expect(
        page.contains('Offstage('),
        isTrue,
        reason: '必须让播放器留在树里（Offstage 只是不可见/不参与布局）',
      );
      expect(
        page.contains('offstage: true'),
        isTrue,
      );
    });

    test('收起/展开走的是同一个 _buildPlayerShell 调用', () {
      // 两处都用 _buildPlayerShell(controller, detail)，说明收起态没换实现
      final calls = RegExp(r'_buildPlayerShell\(\s*controller,\s*detail,?\s*\)')
          .allMatches(page)
          .length;
      expect(
        calls,
        greaterThanOrEqualTo(2),
        reason: '收起态与展开态都调同一个 builder —— 说明没有另造一个"假播放器"',
      );
    });

    test('播放器的 key 只依赖 url/线路/集数，不依赖收起状态', () {
      // key 里出现 _playerCollapsed 就说明收起会触发重建 → 播放中断
      final keyMatch = RegExp(
        r'key:\s*ValueKey<String>\((.*?)\)',
        dotAll: true,
      ).firstMatch(page);
      expect(keyMatch, isNotNull, reason: '没找到播放器 key');
      expect(
        keyMatch!.group(1)!.contains('_playerCollapsed'),
        isFalse,
        reason: '收起状态进了 key 就会重建播放器，音频会断',
      );
    });
  });

  group('收起态有可用的回退入口', () {
    test('迷你条显示当前集名', () {
      expect(
        page.contains("'正在播放 · \$episode'"),
        isTrue,
        reason: '收起后至少要看到"在播什么"',
      );
    });

    test('迷你条有展开按钮，且把状态改回去', () {
      expect(
        page.contains('_playerCollapsed = false'),
        isTrue,
      );
      // 第五轮（顶部重排）：展开入口从 `TextButton.icon(label: '展开')`
      // 换成共用的 `_CollapsedPlayerToggle(collapsed: true, ...)` —— 文案由
      // 该组件按 collapsed 给出（'展开' / '收起播放器'），不再散在调用点。
      // 这里锁的是**语义**：收起态那个开关必须是「展开」方向，且点了改回 false。
      expect(
        page.contains('_CollapsedPlayerToggle('),
        isTrue,
        reason: '收起态的展开入口应走共用开关组件',
      );
      expect(
        RegExp(r'collapsed:\s*true').hasMatch(page),
        isTrue,
        reason: '收起态要传 collapsed: true（图标朝下、文案是「展开」）',
      );
      final toggle = page.substring(
        page.indexOf('class _CollapsedPlayerToggle'),
        page.indexOf('class _PlaybackChip'),
      );
      expect(
        toggle.contains("collapsed ? '展开' : '收起播放器'"),
        isTrue,
        reason: '开关文案随状态切换，收起态显示「展开」',
      );
    });

    test('展开态有收起按钮', () {
      expect(
        page.contains('_playerCollapsed = true'),
        isTrue,
      );
      // 同上：入口换成 _CollapsedPlayerToggle(collapsed: false, ...)。
      expect(
        RegExp(r'collapsed:\s*false').hasMatch(page),
        isTrue,
        reason: '展开态要传 collapsed: false（图标朝上、文案是「收起播放器」）',
      );
      final toggle = page.substring(
        page.indexOf('class _CollapsedPlayerToggle'),
        page.indexOf('class _PlaybackChip'),
      );
      expect(
        toggle.contains("'收起播放器'"),
        isTrue,
        reason: '展开态的收起入口文案必须还在',
      );
    });

    test('同一屏不许出现「展开」与「收起播放器」两个反向开关', () {
      // 真机截到过：点「收起播放器」后，播放器位置换成迷你条（写「展开」），
      // 而下方工具行**还画着一个「收起播放器」** —— 两个按钮方向相反，
      // 且下面那个点了没反应（播放器已经收起了）。
      //
      // 判据：`_buildPlayerToolsRow` 里那个开关必须挂在 `!_playerCollapsed`
      // 条件下。写成源码断言，是因为这段是私有 State 里的布局分支；用渲染
      // 断言要拉起整个播放器（会去打真实 m3u8 并等 12s 超时）。
      final start = page.indexOf('Widget _buildPlayerToolsRow(');
      expect(start, greaterThan(0), reason: '没找到工具行定义');
      final end = page.indexOf('Widget _buildLineStrip(');
      expect(end, greaterThan(start), reason: '没找到线路条定义，区间取错');
      final toolsRow = page.substring(start, end);

      final guardIdx = toolsRow.indexOf('if (!_playerCollapsed)');
      final toggleIdx = toolsRow.indexOf('_CollapsedPlayerToggle(');
      expect(
        guardIdx,
        greaterThan(0),
        reason: '收起态工具行里不能再画「收起播放器」',
      );
      expect(
        toggleIdx,
        greaterThan(guardIdx),
        reason: '开关要落在 !_playerCollapsed 分支内部，否则收起后还会出现',
      );
    });
  });

  group('动画与主题', () {
    test('收起/展开有过渡动画（不是瞬间跳变）', () {
      expect(
        page.contains('AnimatedSize('),
        isTrue,
      );
      expect(
        page.contains('Curves.easeOutCubic'),
        isTrue,
      );
    });

    test('迷你条用 token，不写死浅色底', () {
      // 迷你条的 Container 装饰里必须是 AppTokens.surface 而不是 Colors.white。
      //
      // 注意 indexOf 会先命中**调用点**（`_buildCollapsedPlayerBar(controller)`），
      // 要定位**函数定义**（`Widget _buildCollapsedPlayerBar(`），否则取到的是
      // 调用处附近那段，断言会假失败。
      final idx = page.indexOf('Widget _buildCollapsedPlayerBar(');
      expect(idx, greaterThan(0), reason: '没找到迷你条的定义');
      final body = page.substring(idx, idx + 1600);
      expect(
        body.contains('AppTokens.surface'),
        isTrue,
        reason: '深色档下要跟着变',
      );
      expect(
        body.contains('Colors.white'),
        isFalse,
        reason: '写死白色在深色档下会变白块',
      );
    });
  });
}
