import 'dart:io';

import 'package:box/features/about/data/about_content.dart';
import 'package:flutter_test/flutter_test.dart';

/// 文案里写出的**入口路径**必须真的走得通。
///
/// 由来（真实翻车）：推荐教程第一步原来写「路径：侧边栏 → 书源管理 → 添加」，
/// 而侧边栏（抽屉）里**根本没有**「书源管理」—— 抽屉只有 公告 / 设置 / 备份与恢复 /
/// 反馈 / 调试日志 / 检查更新 / 关于。用户照着找只会一脸茫然。
///
/// 为什么原来的内容准确性用例没拦住：它验的是「书源管理这个**页面**存在」，
/// 不验「这条路**通不通**」。本文件补的就是这一跳。
///
/// 判据：把文案里每一条 `A → B` 链拆成相邻两段；若 A 是**已知容器**
/// （侧边栏 / 设置 / 关于 / 首页），则 B 必须出现在该容器的真实入口清单里。
/// B 自己也可以是个中间站（例如「首页 → 小说 → 书源管理」里的「小说」），
/// 那一跳不做检查 —— 只有已知容器才有可靠的入口清单。
void main() {
  String readLib(String path) => File('lib/$path').readAsStringSync();

  /// 从页面源码里抠出入口名（`title: '...'`）。
  Set<String> titlesOf(List<String> paths) {
    final names = <String>{};
    for (final path in paths) {
      final source = readLib(path);
      for (final m in RegExp(r"title: '([^']+)'").allMatches(source)) {
        names.add(m.group(1)!);
      }
    }
    return names;
  }

  /// 从页面源码里抠出**分区标题**（页面上真会渲染出来的区块名）。
  ///
  /// 三种写法都要认，否则清单会静默变窄（漏掉的分区名会让文案里的路径被误判为
  /// "走不通"，也会让真走不通的路径混进来）：
  ///   * `_buildSectionHeader(title: '快捷入口')` / `_buildSectionHeader('已安装插件')`
  ///   * `AppSectionHeader(title: '内容入口')`
  ///   * `_tabChip(HomeFeedTab.news, '热闻')`（首页资讯卡里的两个 tab）
  Set<String> sectionTitlesOf(String path) {
    final source = readLib(path);
    final names = <String>{};
    for (final re in [
      RegExp(r"_buildSectionHeader\(\s*(?:title:\s*)?'([^']+)'"),
      RegExp(r"AppSectionHeader\(\s*(?:title:\s*)?'([^']+)'"),
      RegExp(r"_tabChip\([^,]+,\s*'([^']+)'\)"),
    ]) {
      for (final m in re.allMatches(source)) {
        names.add(m.group(1)!);
      }
    }
    return names;
  }

  /// 各容器的真实入口清单。
  ///
  /// **一律从渲染源码里取，不许手写**。这里踩过一次大的：原来「首页」那一档是
  /// 「内置插件目录的 title + 手写的六个专区名（推荐/音乐/影视/漫画/小说/工具）」，
  /// 而首页**根本不按专区渲染** —— `HomePluginArea` 全仓只在投稿页当下拉选项用，
  /// `home_page.dart` 实际只有问候栏 / 快捷入口 / 已安装插件 / 继续使用 / 资讯卡。
  /// 于是「首页 → 影视」这类路径写了很久、用户照着找不到，而这条护栏还一路绿灯：
  /// 它拿文案自己的假设（专区名）去验文案，等于自己给自己盖章。
  final containers = <String, Set<String>>{
    '侧边栏': titlesOf(['app_drawer.dart']),
    '设置': titlesOf([
      'features/settings/presentation/settings_page.dart',
      'features/settings/presentation/data_settings_page.dart',
    ]),
    '关于': titlesOf(['features/about/presentation/about_page.dart']),
    // 「首页」这一档：只放首页**真的会渲染出来的**区块名，
    // 以及「快捷入口」卡片的来源（内置插件目录，默认几个入口就是它的 title）。
    '首页': {
      ...sectionTitlesOf('features/home/presentation/home_page.dart'),
      ...sectionTitlesOf('features/home/presentation/widgets/continue_rail.dart'),
      ...sectionTitlesOf('features/home/presentation/widgets/home_feed_card.dart'),
      // 快捷入口卡片的标题来自插件目录，不是首页自己写的字符串。
      ...titlesOf(['features/extensions/core/builtin_plugin_catalog.dart']),
    },
    // 「内容」页：四宫格（内容入口 → 影视/小说/漫画/音乐）+ 收藏库各分区名。
    '内容': {
      ...titlesOf(
        ['features/content/presentation/widgets/warehouse_widgets.dart'],
      ),
      ...titlesOf(['features/content/presentation/warehouse_tab.dart']),
      ...sectionTitlesOf('features/content/presentation/warehouse_tab.dart'),
    },
    // 「扩展」页：列表里列出的就是内置插件（title 来自目录），外加顶部几个动作。
    '扩展': {
      ...titlesOf(['features/extensions/core/builtin_plugin_catalog.dart']),
      ...titlesOf([
        'features/extensions/presentation/widgets/extension_management_widgets.dart',
      ]),
    },
  };

  /// 容器名在文案里的几种写法（「关于页」和「关于」是同一个容器的两种说法）。
  const aliases = <String, String>{
    '侧边栏': '侧边栏',
    '设置': '设置',
    '关于': '关于',
    '关于页': '关于',
    '首页': '首页',
    '内容': '内容',
    '扩展': '扩展',
  };

  /// 从一段里认出容器名：规范化后**以容器名结尾**就算。
  ///
  /// 为什么要「结尾」而不是「相等」：文案里的容器名常带着前导说明
  /// （`先在「侧边栏 → 书源管理」`、`路径：首页 → …`），按相等去比会整条漏掉 ——
  /// 漏掉就等于没有护栏（第一次写这个闸门时就漏了，靠「临时把错路径写回去」才发现）。
  String? containerOf(String raw) {
    final text = raw.replaceAll('「', '').replaceAll('」', '').trim();
    for (final entry in aliases.entries) {
      if (text.endsWith(entry.key)) return entry.value;
    }
    return null;
  }

  /// 把一段路径段规范化成「入口名」：砍掉前导说明、括号注释与标点。
  String normalize(String raw) {
    var text = raw.trim();
    text = text.replaceFirst(RegExp(r'^[^「]*[:：]'), '');
    // 不靠"列出所有要砍的标点"（曾经少列一个全角右括号就漏检一整条），
    // 改成**只收合法名字字符**：汉字、字母、数字、下划线、连字符与空格（「API 能力中心」里有空格），
    // 遇到别的字符就停 —— 括号注释、引号、逗号、书名号一次全砍掉。
    final buf = StringBuffer();
    for (final rune in text.runes) {
      final isNameChar = (rune >= 0x4E00 && rune <= 0x9FFF) ||
          (rune >= 0x30 && rune <= 0x39) ||
          (rune >= 0x41 && rune <= 0x5A) ||
          (rune >= 0x61 && rune <= 0x7A) ||
          rune == 0x5F ||
          rune == 0x2D ||
          rune == 0x20;
      if (!isNameChar) break;
      buf.writeCharCode(rune);
    }
    return buf.toString().trim();
  }

  /// 文案全文（用户真会读到的那些）。
  String allText() => [
    ...AboutContent.introduction.expand(
      (s) => [s.title, ...s.paragraphs, ...s.bullets],
    ),
    ...AboutContent.usageDocs.expand(
      (s) => [s.title, ...s.paragraphs, ...s.bullets],
    ),
    ...AboutContent.tutorials.expand((t) => [t.title, t.description]),
  ].join('\n');

  test('首页不按专区渲染：文案里不许再出现「首页 → 专区名」', () {
    // 由来（真实翻车）：文案曾写「首页 → 影视」「首页 → 小说」，而首页从来没有专区。
    // 根因是这条护栏原来拿 `HomePluginArea` 的 `area.title`（推荐/音乐/影视/漫画/小说/工具）
    // 当「首页的真实入口」—— 那份枚举全仓只有投稿页当下拉选项用，没有任何页面按它渲染。
    // 于是护栏拿文案自己的假设去验文案，一路绿灯。现在改成**反向**钉住：
    // 只要首页还不按专区渲染，文案里就不许出现这类路径。
    expect(
      readLib('features/home/presentation/home_page.dart')
          .contains('HomePluginArea'),
      isFalse,
      reason: '首页一旦真的按专区渲染，才能把「首页 → 影视」写回文案；在那之前不许写',
    );
    for (final area in ['推荐', '音乐', '影视', '漫画', '小说', '工具']) {
      expect(
        allText().contains('首页 → $area'),
        isFalse,
        reason: '「首页 → $area」用户走不通：首页只有问候栏 / 快捷入口 / 已安装插件 / '
            '继续使用 / 资讯卡，专区只是数据模型里的一层分类',
      );
    }
  });

  test('文案里不许出现应用没有的能力词', () {
    // 这些词都真在文案里出现过，但界面里没有对应的能力（全仓 grep 零命中），
    // 用户照着找会扑空。加进来是防止「顺手写回去」。
    const nonexistent = <String, String>{
      '练习': '没有练习模式，题库只有录入 / 查看 / 答题助手读屏',
      '错题': '没有错题本',
      '最近使用': '工具页那行是「常用」，按点击次数排，不能手动固定/置顶',
      '音乐收藏': '内容页只有书架 / 影视收藏 / 漫画收藏三类，音乐是占位页',
      '漫画源检测': '界面上的说法是「漫画源自检」',
      '四类收藏': '只有三类',
    };
    final text = allText();
    for (final entry in nonexistent.entries) {
      expect(
        text.contains(entry.key),
        isFalse,
        reason: '文案里出现「${entry.key}」，但${entry.value}',
      );
    }
  });

  test('文案里「容器 → 入口名」的每一跳都真的存在', () {
    final offenders = <String>[];

    for (final line in allText().split('\n')) {
      final segments = line.split('→');
      if (segments.length < 2) continue;
      for (var i = 0; i < segments.length - 1; i++) {
        final from = containerOf(segments[i]);
        if (from == null) continue; // 不是已知容器：这一跳不检查
        final to = normalize(segments[i + 1]);
        final entries = containers[from]!;
        if (to.isEmpty) continue;
        if (!entries.contains(to)) {
          offenders.add('$from → $to（原句：${line.trim()}）');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '这些路径在界面上走不通（目标入口不在该容器的清单里）：\n'
          '${offenders.join('\n')}\n'
          '要么改文案指向真实入口，要么把入口真的做出来。',
    );
  });

  test('顺手钉住这次修掉的那条：书源管理不在侧边栏', () {
    expect(
      containers['侧边栏']!.contains('书源管理'),
      isFalse,
      reason: '抽屉里没有「书源管理」；如果哪天加了，这条和文案一起改',
    );
    expect(
      allText().contains('侧边栏 → 书源管理'),
      isFalse,
      reason: '这条路径用户走不通，改文案前不要写回来',
    );
    // 真实入口：小说列表页顶部的书源名 → 书源管理
    expect(
      readLib('novel/pages/novel_list_page.dart')
          .contains('BookSourceManagerPage'),
      isTrue,
      reason: '「书源管理」要从小说页进，这个入口必须还在',
    );
  });
}
