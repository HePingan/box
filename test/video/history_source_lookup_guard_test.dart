import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 源码结构护栏：这条误报修过两次了，别再退回去。
///
/// 现象：首页「继续使用」点一条影视卡片 → 「该视频的片源已失效或被移除」。
/// 两次根因都不在片源本身：
///   1. 冷启动时影视目录还没加载（`VideoController.sources` 是空的）——
///      内容页收藏库当年就是这么栽的，靠 `VideoModule.ensureCatalogReady` 修掉；
///   2. 目录 JSON **没有 id 字段**，源的 id 就是接口地址，上游换过地址后
///      本地历史按 id 永远匹配不上 → 必须退到 url / 归一化名字
///      （`findVideoSourceForHistory`）。
///
/// 详情页那类 State 私有、要联网的页面没法 pump，所以这里按仓库既有做法
/// （`test/features/about/about_content_accuracy_test.dart`）读源码钉结构。
void main() {
  final libDir = Directory('lib');
  String readLib(String relative) => File('${libDir.path}/$relative').readAsStringSync();

  test('首页续播：先确保目录已加载，再按 id/url/名字找源', () {
    final code = readLib('features/home/presentation/home_page.dart');

    final ensureAt = code.indexOf('ensureCatalogReady');
    final matchAt = code.indexOf('findVideoSourceForHistory');
    expect(ensureAt, greaterThan(-1), reason: '冷启动必须先备好目录，否则好片源也被报成已失效');
    expect(matchAt, greaterThan(-1), reason: '按归一化名字兜匹配是「地址漂了」那一类的解法');
    expect(
      ensureAt,
      lessThan(matchAt),
      reason: '要先加载再匹配，顺序反了等于没修',
    );
    expect(
      code.contains('source.id == history.sourceId'),
      isFalse,
      reason: '只比 id 会重现误报（目录里没有 id，源 id 就是接口地址）',
    );
  });

  test('观看历史 / 历史快捷视图不再各自实现「只比 id」的匹配', () {
    for (final file in <String>[
      'video/pages/watch_history_page.dart',
      'video/widgets/history_quick_view.dart',
    ]) {
      final code = readLib(file);
      expect(
        code.contains('_findSourceById'),
        isFalse,
        reason: '$file 应改用共享的 findVideoSourceForHistory',
      );
      expect(
        code.contains('findVideoSourceForHistory'),
        isTrue,
        reason: '$file 没接上共享匹配器',
      );
    }
  });

  test('共享匹配器必须真的有三段兜底（id → url → 归一化名字）', () {
    final code = readLib('video/services/source_match.dart');
    expect(code.contains('source.id == id'), isTrue);
    expect(code.contains('source.url == id'), isTrue);
    expect(code.contains('normalizeSourceName(source.name)'), isTrue);
    expect(
      code.contains('return null'),
      isTrue,
      reason: '同名歧义时不许乱猜，要如实返回 null',
    );
  });
}
