import 'package:box/features/tools/application/tool_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final categories = createDefaultToolCategories();

  group('工具目录数据自洽', () {
    test('分类非空，且每个分类都有标题、副标题与至少一个工具', () {
      expect(categories, isNotEmpty);
      for (final c in categories) {
        expect(c.title.trim(), isNotEmpty);
        expect(c.subtitle.trim(), isNotEmpty);
        expect(c.tools, isNotEmpty, reason: '${c.title} 不应是空分类');
      }
    });

    test('副标题若声称工具数量，必须与实际条目数一致', () {
      final claimPattern = RegExp(r'(\d+)\s*个工具');
      for (final c in categories) {
        final match = claimPattern.firstMatch(c.subtitle);
        if (match == null) continue;
        final claimed = int.parse(match.group(1)!);
        expect(
          claimed,
          c.tools.length,
          reason:
              '${c.title} 副标题声称 $claimed 个工具，实际只有 ${c.tools.length} 个，'
              '用户会数出差额',
        );
      }
    });

    test('工具名不跨分类重复，避免同名条目行为歧义', () {
      final seen = <String, String>{};
      final duplicates = <String>[];
      for (final c in categories) {
        for (final tool in c.tools) {
          final previous = seen[tool];
          if (previous != null) {
            duplicates.add('$tool（$previous / ${c.title}）');
          } else {
            seen[tool] = c.title;
          }
        }
      }
      expect(duplicates, isEmpty, reason: '重复工具：${duplicates.join('、')}');
    });

    test('同一分类内工具名不重复', () {
      for (final c in categories) {
        expect(
          c.tools.toSet().length,
          c.tools.length,
          reason: '${c.title} 内部存在重复工具名',
        );
      }
    });

    test('工具名无前后空白、无空串', () {
      for (final c in categories) {
        for (final tool in c.tools) {
          expect(tool, tool.trim(), reason: '${c.title} 的「$tool」含多余空白');
          expect(tool.trim(), isNotEmpty);
        }
      }
    });

    test('分类标题不重复', () {
      final titles = categories.map((c) => c.title).toList();
      expect(titles.toSet().length, titles.length);
    });

    test('默认最多只有一个分类处于展开态', () {
      final expanded = categories.where((c) => c.isExpanded).toList();
      expect(
        expanded.length,
        lessThanOrEqualTo(1),
        reason: '首屏同时展开多个分类会把列表推得很长',
      );
    });
  });

  group('可用工具名单', () {
    test('名单非空，且每个名字都真实存在于目录中', () {
      expect(kAvailableToolNames, isNotEmpty);
      final all = categories.expand((c) => c.tools).toSet();
      for (final name in kAvailableToolNames) {
        expect(all, contains(name), reason: '可用名单里的「$name」在目录中找不到，说明改名后名单没同步');
      }
    });

    test('isToolAvailable 只对名单内的工具返回 true', () {
      expect(isToolAvailable('在线PS'), isTrue);
      expect(isToolAvailable('汇率换算'), isTrue);
      expect(isToolAvailable('节假日查询'), isTrue);
      expect(isToolAvailable('API能力中心'), isTrue);
      expect(isToolAvailable('扫雷'), isFalse);
      expect(isToolAvailable(''), isFalse);
      expect(isToolAvailable('不存在的工具'), isFalse);
    });

    test('可用工具远少于目录总数，可用数不能用总数顶替', () {
      final total = categories.fold<int>(0, (sum, c) => sum + c.tools.length);
      expect(
        kAvailableToolNames.length,
        lessThan(total),
        reason: '若两者相等则说明可用性判断退化成了「全部可用」',
      );
    });

    test('逐分类统计的可用数与名单一致', () {
      var counted = 0;
      for (final c in categories) {
        counted += c.tools.where(isToolAvailable).length;
      }
      expect(
        counted,
        kAvailableToolNames.length,
        reason: '目录里存在重复或缺失，导致可用数统计与名单不符',
      );
    });
  });

  group('ToolCategory', () {
    test('isExpanded 默认为 false，可变更', () {
      final c = ToolCategory(
        title: 't',
        subtitle: 's',
        icon: categories.first.icon,
        iconBgColor: categories.first.iconBgColor,
        tools: const ['a'],
      );
      expect(c.isExpanded, isFalse);
      c.isExpanded = true;
      expect(c.isExpanded, isTrue);
    });

    test('createDefaultToolCategories 每次返回独立实例，互不串状态', () {
      final first = createDefaultToolCategories();
      final second = createDefaultToolCategories();

      first.first.isExpanded = !first.first.isExpanded;

      expect(
        second.first.isExpanded,
        isNot(first.first.isExpanded),
        reason: '两次调用应互相独立，否则搜索结果的展开态会污染原始目录',
      );
    });
  });
}
