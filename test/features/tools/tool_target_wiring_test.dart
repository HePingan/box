// 工具页「可用性 / 点击去向」的单一事实源验证。
//
// 背景（真实缺陷，本测试就是为了锁住它）：
// 可用名单曾是一份手抄的 `const Set<String> kAvailableToolNames`，点击派发是
// `tool_widgets.dart` 里的硬编码 if 链，末尾还有一个**无条件 Photopea fallback**。
// 两者各存一份事实，于是漂移出这些问题：
//
//   1. 「图书搜索」派发 `ApiHubPage(initialTool: 'books')`，但 registry 里
//      压根没有 `books` 这个 id。`PublicApiRegistry.byId` 的
//      `orElse: () => weather` 把它静默兜到了**天气预报**面板。
//      用户点「图书搜索」看到的是天气 —— 而既有测试只用正则扫源码里有没有
//      `initialTool: 'books'` 这个字符串，所以一路绿着放过。
//   2. registry 里已实现的能力（英文词典 / 短链 / 头像 / 随机封面 / 占位图）
//      在工具目录里没有任何入口，用户到不了。
//   3. 目录里两个不同名条目指向同一个 API Hub 面板（天气预报 / Open-Meteo天气，
//      国内可用API / 国内API清单）。
//
// 所以这里断言的是**表驱动契约**：可用性由 `kToolTargets` 派生，且表里每个
// API Hub 目标都必须在 registry 里真实存在。
library;

import 'dart:io';

import 'package:box/features/api_hub/application/public_api_registry.dart';
import 'package:box/features/tools/application/tool_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 去掉 `//` 行注释，避免源码扫描断言被本文件/被测文件里的解释性注释误伤。
String _stripLineComments(String src) => src
    .split('\n')
    .map((line) {
      final idx = line.indexOf('//');
      return idx == -1 ? line : line.substring(0, idx);
    })
    .join('\n');

Set<String> _allCatalogToolNames() {
  final names = <String>{};
  for (final category in createDefaultToolCategories()) {
    names.addAll(category.tools);
  }
  return names;
}

void main() {
  group('可用性来自映射表，不再手抄名单', () {
    test('kToolTargets 非空，且 isToolAvailable 完全由它派生', () {
      expect(kToolTargets, isNotEmpty);

      for (final name in kToolTargets.keys) {
        expect(isToolAvailable(name), isTrue, reason: '$name 在映射表里，必须判定为可用');
      }

      // 表外的名字一律不可用（拿一个确定没接线的占位条目验证）。
      expect(isToolAvailable('扬声器清灰'), isFalse);
      expect(isToolAvailable('这个工具不存在'), isFalse);
    });

    test('kAvailableToolNames 只是映射表的键视图，两者不会漂移', () {
      expect(kAvailableToolNames, equals(kToolTargets.keys.toSet()));
    });
  });

  group('每个 API Hub 目标都要在 registry 里真实存在', () {
    test('byId 不会静默落回 weather —— 锁住「图书搜索开出天气」那个 bug', () {
      final registryIds = PublicApiRegistry.all.map((t) => t.id).toSet();

      for (final entry in kToolTargets.entries) {
        final target = entry.value;
        if (target is! ApiHubToolTarget) continue;
        final toolId = target.toolId;
        if (toolId == null) continue; // null = 打开 API Hub 首页，合法

        expect(
          registryIds,
          contains(toolId),
          reason:
              '「${entry.key}」派发 initialTool: $toolId，但 registry 里没有这个 id，'
              'byId 会静默兜底到 weather，用户点进去看到的是天气面板',
        );

        // 双保险：直接问 byId，确认它返回的就是目标本身而不是兜底值。
        expect(
          PublicApiRegistry.byId(toolId).id,
          toolId,
          reason: '「${entry.key}」→ $toolId 被 orElse 兜底了',
        );
      }
    });

    test('图书搜索必须指向真实存在的 books 工具', () {
      final target = kToolTargets['图书搜索'];
      expect(target, isA<ApiHubToolTarget>());
      expect((target! as ApiHubToolTarget).toolId, 'books');
      expect(PublicApiRegistry.byId('books').id, 'books');
      expect(PublicApiRegistry.byId('books').title, contains('图书'));
    });
  });

  group('registry 已实现的能力都要有工具页入口', () {
    test('12+ 个已实现工具，每个都至少被一个目录条目映射到', () {
      final mappedIds = kToolTargets.values
          .whereType<ApiHubToolTarget>()
          .map((t) => t.toolId)
          .whereType<String>()
          .toSet();

      final missing = PublicApiRegistry.all
          .map((t) => t.id)
          .where((id) => !mappedIds.contains(id))
          .toList();

      expect(missing, isEmpty, reason: '这些能力已经实现但工具页没有入口，用户到不了：$missing');
    });
  });

  group('目录与映射表互相对齐', () {
    test('映射表里的每个名字都能在某个分类里被点到', () {
      final catalogNames = _allCatalogToolNames();
      final orphans = kToolTargets.keys
          .where((name) => !catalogNames.contains(name))
          .toList();

      expect(orphans, isEmpty, reason: '这些工具接线了但目录里没有条目，点不到：$orphans');
    });

    test('没有两个目录条目指向同一个 API Hub 面板', () {
      final byToolId = <String, List<String>>{};
      for (final entry in kToolTargets.entries) {
        final target = entry.value;
        if (target is! ApiHubToolTarget) continue;
        final toolId = target.toolId;
        if (toolId == null) continue;
        byToolId.putIfAbsent(toolId, () => <String>[]).add(entry.key);
      }

      final duplicated = byToolId.entries
          .where((e) => e.value.length > 1)
          .map((e) => '${e.key} ← ${e.value}')
          .toList();

      expect(
        duplicated,
        isEmpty,
        reason: '同一个面板挂了多个不同名入口，属于同类能力散落多处：$duplicated',
      );
    });

    test('目录条目不重名', () {
      final seen = <String>{};
      final duplicated = <String>[];
      for (final category in createDefaultToolCategories()) {
        for (final name in category.tools) {
          if (!seen.add(name)) duplicated.add(name);
        }
      }
      expect(duplicated, isEmpty, reason: '目录里出现重名条目：$duplicated');
    });
  });

  group('已实现的工具不能再标「开发中」', () {
    test('天气预报 / 二维码生成 / 英文词典 等都判定为可用', () {
      for (final name in [
        '天气预报',
        '二维码生成',
        '英文词典',
        '短链接生成',
        '头像生成',
        '随机封面',
        '占位图生成',
        '图书搜索',
      ]) {
        expect(
          isToolAvailable(name),
          isTrue,
          reason: '$name 在 registry 里已实现，不该再显示「开发中」',
        );
      }
    });
  });

  group('Web 型工具把 URL 放在目录里，不放在派发代码里', () {
    test('在线PS 是 WebToolTarget，带真实 https 地址', () {
      final target = kToolTargets['在线PS'];
      expect(target, isA<WebToolTarget>());
      final web = target! as WebToolTarget;
      expect(web.url, startsWith('https://'));
      expect(web.title, isNotEmpty);
    });

    test('派发代码里不再有硬编码站点地址与无条件 fallback', () {
      final src = _stripLineComments(
        File(
          'lib/features/tools/presentation/widgets/tool_widgets.dart',
        ).readAsStringSync(),
      );

      expect(
        src.contains('photopea.com'),
        isFalse,
        reason: '站点地址应该只存在于 tool_catalog 的映射表里',
      );
      expect(
        src.contains("initialTool: 'books'"),
        isFalse,
        reason: '不该再有按名字写死的 if 分支',
      );
      expect(
        RegExp(r"toolName == '").hasMatch(src),
        isFalse,
        reason: '点击派发应改为查表，不是按名字比对的 if 链',
      );
    });
  });

  group('死代码清理', () {
    test('ToolGlassButton 已删除（全仓零引用）', () {
      final toolPage = File(
        'lib/features/tools/presentation/tool_page.dart',
      ).readAsStringSync();
      expect(
        toolPage.contains('ToolGlassButton'),
        isFalse,
        reason: '零引用的装饰按钮应删掉，不留在页面文件里',
      );
    });
  });

  group('行尾统一', () {
    test('tool_widgets.dart 与邻居一致使用 LF', () {
      final raw = File(
        'lib/features/tools/presentation/widgets/tool_widgets.dart',
      ).readAsStringSync();
      expect(
        raw.contains('\r\n'),
        isFalse,
        reason: '同目录其他文件都是 LF，这个文件是 CRLF，diff 会整片翻红',
      );
    });
  });

  group('ToolCategory 仍可正常构造', () {
    test('分类数与图标字段保持可用', () {
      final categories = createDefaultToolCategories();
      expect(categories.length, greaterThanOrEqualTo(10));
      for (final c in categories) {
        expect(c.title, isNotEmpty);
        expect(c.tools, isNotEmpty);
        expect(c.icon, isA<IconData>());
      }
    });
  });
}
