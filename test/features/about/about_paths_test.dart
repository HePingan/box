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

  /// 各容器的真实入口清单。
  ///
  /// 「首页」这一档是拼出来的：首页插件的 title + 专区名（专区名由
  /// `home_plugin_core.dart` 的 `area.title` 决定，这里按同一份枚举写死并在下面
  /// 用一条断言钉住它在源码里确实存在）。
  final containers = <String, Set<String>>{
    '侧边栏': titlesOf(['app_drawer.dart']),
    '设置': titlesOf([
      'features/settings/presentation/settings_page.dart',
      'features/settings/presentation/data_settings_page.dart',
    ]),
    '关于': titlesOf(['features/about/presentation/about_page.dart']),
    '首页': {
      ...titlesOf(['features/extensions/core/builtin_plugin_catalog.dart']),
      ...titlesOf(['features/home/presentation/home_page.dart']),
      '推荐',
      '音乐',
      '影视',
      '漫画',
      '小说',
      '工具',
    },
  };

  /// 容器名在文案里的几种写法（「关于页」和「关于」是同一个容器的两种说法）。
  const aliases = <String, String>{
    '侧边栏': '侧边栏',
    '设置': '设置',
    '关于': '关于',
    '关于页': '关于',
    '首页': '首页',
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
    final cut = RegExp(r'[（(」』)，,、。；;：: ]').firstMatch(text);
    if (cut != null) text = text.substring(0, cut.start);
    return text.replaceAll('「', '').replaceAll('」', '').trim();
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

  test('专区名与源码里的枚举一致（首页那一档的清单不是编的）', () {
    final core = readLib('features/extensions/core/home_plugin_core.dart');
    for (final area in ['推荐', '音乐', '影视', '漫画', '小说', '工具']) {
      expect(
        core.contains("return '$area';"),
        isTrue,
        reason: '首页专区名「$area」在源码里找不到，清单就是编的',
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
