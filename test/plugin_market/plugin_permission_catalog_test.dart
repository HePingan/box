import 'dart:io';

import 'package:box/features/extensions/market/domain/plugin_market_manifest.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 插件权限目录（客户端侧）的单一事实源守卫。
///
/// 背景：权限此前只有 4 个 code（network/storage/clipboard/none），而 App 的枚举
/// 里还有 camera —— 服务端认不出就**静默丢掉**，插件带着「无权限」的假披露上架；
/// 投稿页更是把这个字段写死成 `none`。这套测试锁住三件事：
///   1. 枚举与「服务端同一份目录」的 code 集合一字不差（漂移即红）；
///   2. risk / label / description 三件套完整，且高风险集合固定；
///   3. 投稿页与市场页确实接上了这套东西（源码契约，UI 层不重复造渲染测试）。
void main() {
  /// 必须与服务端 `kPluginPermissionCatalog` 的 key 完全一致。
  const expectedCodes = <String>[
    'network',
    'storage',
    'clipboard',
    'notification',
    'background',
    'audio',
    'camera',
    'microphone',
    'overlay',
    'installPackage',
    'accessibility',
    'none',
  ];

  group('权限目录', () {
    test('枚举 code 与服务端目录一致（顺序也一致，便于人眼比对）', () {
      expect(
        PluginPermission.values.map((p) => p.name).toList(),
        expectedCodes,
      );
    });

    test('每个权限都有非空标签与说明，标签不重复', () {
      final labels = <String>{};
      for (final permission in PluginPermission.values) {
        expect(permission.label.trim(), isNotEmpty, reason: '${permission.name} 缺标签');
        expect(
          permission.description.trim(),
          isNotEmpty,
          reason: '${permission.name} 缺说明',
        );
        expect(labels.add(permission.label), isTrue,
            reason: '标签重复：${permission.label}');
      }
    });

    test('风险分级：高/中/低三档划分固定', () {
      final high = PluginPermission.values
          .where((p) => p.risk == PluginPermissionRisk.high)
          .map((p) => p.name)
          .toSet();
      final medium = PluginPermission.values
          .where((p) => p.risk == PluginPermissionRisk.medium)
          .map((p) => p.name)
          .toSet();
      final low = PluginPermission.values
          .where((p) => p.risk == PluginPermissionRisk.low)
          .map((p) => p.name)
          .toSet();

      expect(high, {'camera', 'microphone', 'overlay', 'installPackage', 'accessibility'});
      expect(medium, {'storage', 'clipboard', 'background'});
      expect(low, {'network', 'notification', 'audio'});
      expect(PluginPermission.none.risk, PluginPermissionRisk.none);
    });

    test('风险等级有 label 且 rank 单调递增', () {
      expect(PluginPermissionRisk.high.rank, greaterThan(PluginPermissionRisk.medium.rank));
      expect(PluginPermissionRisk.medium.rank, greaterThan(PluginPermissionRisk.low.rank));
      expect(PluginPermissionRisk.low.rank, greaterThan(PluginPermissionRisk.none.rank));
      for (final risk in PluginPermissionRisk.values) {
        expect(risk.label.trim(), isNotEmpty);
      }
    });
  });

  group('highestPermissionRiskOf', () {
    test('空集合 / 只有 none → none', () {
      expect(highestPermissionRiskOf(const []), PluginPermissionRisk.none);
      expect(highestPermissionRiskOf(const ['none']), PluginPermissionRisk.none);
    });

    test('取最敏感那一档', () {
      expect(highestPermissionRiskOf(const ['network']), PluginPermissionRisk.low);
      expect(
        highestPermissionRiskOf(const ['network', 'storage']),
        PluginPermissionRisk.medium,
      );
      expect(
        highestPermissionRiskOf(const ['network', 'background', 'camera']),
        PluginPermissionRisk.high,
      );
    });

    test('未知 code 不计入风险（但仍会以标签形式展示）', () {
      expect(
        highestPermissionRiskOf(const ['unknownFuturePermission']),
        PluginPermissionRisk.none,
      );
    });
  });

  group('permissionDetailsOf', () {
    test('过滤 none、去重、保持声明顺序', () {
      final details = permissionDetailsOf(const ['none', 'camera', 'network', 'camera']);
      expect(details.map((d) => d.code).toList(), ['camera', 'network']);
      expect(details.first.label, '相机');
      expect(details.first.risk, PluginPermissionRisk.high);
      expect(details.first.description, isNotEmpty);
    });

    test('未知 code 原样展示并标成高风险（宁可吓一跳，也不静默吞掉）', () {
      final details = permissionDetailsOf(const ['rootShell']);
      expect(details, hasLength(1));
      expect(details.single.label, 'rootShell');
      expect(details.single.risk, PluginPermissionRisk.high);
      expect(details.single.description, contains('不认识'));
    });
  });

  group('permissionLabelsOf', () {
    test('把全部 code 翻成中文', () {
      final labels = permissionLabelsOf(
        PluginPermission.values.where((p) => p != PluginPermission.none).map((p) => p.name),
      );
      expect(labels, hasLength(11));
      expect(labels, contains('无障碍'));
      expect(labels, isNot(contains('无')));
    });

    test('认不出的 code 原样保留', () {
      expect(permissionLabelsOf(const ['x-future']), ['x-future']);
    });
  });

  group('兼容性检查', () {
    test('未知权限 code 不会阻塞安装（服务端先扩权限、旧客户端仍可装）', () {
      const template = MarketPluginTemplate(
        id: 'demo',
        title: '演示',
        subtitle: '',
        actionCode: 'toast',
        areaCode: 'recommend',
        permissions: ['network', 'someFuturePermission'],
        icon: Icons.extension_outlined,
        color: Color(0xFF4F46E5),
        payload: '',
      );
      final result = PluginCompatibilityChecker.check(
        template,
        currentAppVersion: '1.21.20',
        actionExists: (_) => true,
      );
      expect(result.blockingIssues, isEmpty);
      expect(result.canInstall, isTrue);
    });
  });

  group('UI 接线（源码契约）', () {
    test('投稿页有权限多选，且不再写死 none', () {
      final source = File(
        'lib/features/extensions/market/presentation/plugin_submit_page.dart',
      ).readAsStringSync();
      expect(source, contains('final Set<String> _permissions'));
      expect(source, contains('FilterChip('));
      expect(source, contains('highestPermissionRiskOf(_permissions)'));
      // 提交时必须把真实选择发出去
      expect(
        source,
        contains("'permissions': _permissions.isEmpty ? 'none' : _permissions.join(',')"),
      );
      expect(source, contains("_permissions.isEmpty ? const ['none'] : _permissions.toList()"));
      // 旧的写死两处必须已消失
      expect(source, isNot(contains("'permissions': 'none',")));
      expect(source, isNot(contains("'permissions': const ['none'],")));
    });

    test('市场页安装确认逐条展示权限 + 风险色', () {
      final source = File(
        'lib/features/extensions/market/presentation/plugin_market_page.dart',
      ).readAsStringSync();
      expect(source, contains('permissionDetailsOf(item.permissions)'));
      expect(source, contains('_permissionRiskColor(detail.risk)'));
      expect(source, contains('该插件声明将访问（按敏感度标注）'));
      expect(source, contains('⚠ 高权限'));
    });
  });
}
