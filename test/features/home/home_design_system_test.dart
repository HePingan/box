import 'dart:io';

import 'package:box/design_system/app_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

/// 首页设计一致性测试。
///
/// 背景：首页 UI 改版前实测到的问题——
/// 1. 圆角有 9 种取值（9/10/12/14/15/16/24/28），AppTokens 的 radius 阶梯基本没被用上；
/// 2. 硬编码 15 处 Color(0xFF...)，其中多个与 AppTokens 已有 token 同值（重复定义）；
/// 3. 热闻兜底文案写「下拉刷新重试」，但 RefreshIndicator 零引用，是句空话。
///
/// 这些是「设计系统纪律」问题，widget 测试看不出来，所以用源码静态检查来钉。
/// 检查的是首页这两个文件，不是全仓 —— 避免给其他模块强加约束。
void main() {
  final homePage = File(
    'lib/features/home/presentation/home_page.dart',
  ).readAsStringSync();
  final homeWidgets = File(
    'lib/features/home/presentation/widgets/home_widgets.dart',
  ).readAsStringSync();
  final sources = {
    'home_page.dart': homePage,
    'home_widgets.dart': homeWidgets,
  };

  group('圆角必须走 AppTokens 阶梯', () {
    /// AppTokens 里已定义的圆角阶梯值。
    final allowedRadii = <double>{
      AppTokens.radiusXs, // 8
      AppTokens.radiusChip, // 10
      AppTokens.radiusSm, // 12
      AppTokens.radiusInner, // 14
      AppTokens.radiusCard, // 16
      AppTokens.radiusMd, // 18
      AppTokens.radiusLg, // 24
      AppTokens.radiusXl, // 30
      AppTokens.radius2Xl, // 34
      AppTokens.radiusPill, // 999
    };

    for (final entry in sources.entries) {
      test('${entry.key} 不出现阶梯外的裸圆角数字', () {
        // 匹配 circular(14) / circular(15.5) 这种字面量，
        // circular(AppTokens.radiusSm) 不匹配（里面不是数字开头）。
        final literals = RegExp(r'circular\(\s*([0-9]+(?:\.[0-9]+)?)\s*\)')
            .allMatches(entry.value)
            .map((m) => double.parse(m.group(1)!))
            .toSet();

        final offenders = literals.difference(allowedRadii).toList()..sort();

        expect(
          offenders,
          isEmpty,
          reason:
              '${entry.key} 出现了不在 AppTokens 阶梯里的圆角 $offenders。'
              '阶梯为 $allowedRadii，请改用 AppTokens.radiusXxx 或对齐到最近档位。',
        );
      });
    }
  });

  group('颜色不得重复定义已有 token', () {
    /// AppTokens 已经定义过的颜色 → 对应的 token 名，用于报错时给出改法。
    final tokenByValue = <int, String>{
      AppTokens.primaryBlue.toARGB32(): 'AppTokens.primaryBlue',
      AppTokens.cyan.toARGB32(): 'AppTokens.cyan',
      AppTokens.violet.toARGB32(): 'AppTokens.violet',
      AppTokens.emerald.toARGB32(): 'AppTokens.emerald',
      AppTokens.rose.toARGB32(): 'AppTokens.rose',
      AppTokens.amber.toARGB32(): 'AppTokens.amber',
      AppTokens.orange.toARGB32(): 'AppTokens.orange',
      AppTokens.ink.toARGB32(): 'AppTokens.ink',
      AppTokens.inkDark.toARGB32(): 'AppTokens.inkDark',
      AppTokens.divider.toARGB32(): 'AppTokens.divider',
      AppTokens.textPrimary.toARGB32(): 'AppTokens.textPrimary',
      AppTokens.textSecondary.toARGB32(): 'AppTokens.textSecondary',
      AppTokens.textTertiary.toARGB32(): 'AppTokens.textTertiary',
      AppTokens.surfaceMuted.toARGB32(): 'AppTokens.surfaceMuted',
      AppTokens.surfaceTint.toARGB32(): 'AppTokens.surfaceTint',
    };

    for (final entry in sources.entries) {
      test('${entry.key} 不硬编码与 token 同值的颜色', () {
        final hardcoded = RegExp(r'Color\(0x([0-9A-Fa-f]{8})\)')
            .allMatches(entry.value)
            .map((m) => int.parse(m.group(1)!, radix: 16))
            .toSet();

        final duplicated = <String>[];
        for (final value in hardcoded) {
          final token = tokenByValue[value];
          if (token != null) {
            duplicated.add(
              '0x${value.toRadixString(16).toUpperCase()} → 应改用 $token',
            );
          }
        }

        expect(
          duplicated,
          isEmpty,
          reason: '${entry.key} 重复定义了 AppTokens 已有的颜色：\n${duplicated.join('\n')}',
        );
      });
    }
  });

  group('兜底文案承诺的交互必须真的存在', () {
    test('热闻提示「下拉刷新」时页面必须挂 RefreshIndicator', () {
      final promisesPullToRefresh = homePage.contains('下拉刷新');
      if (!promisesPullToRefresh) return;

      expect(
        homePage.contains('RefreshIndicator'),
        isTrue,
        reason:
            '兜底文案写了「下拉刷新重试」，但首页没有 RefreshIndicator，'
            '用户下拉不会有任何反应 —— 要么实现下拉刷新，要么改掉这句文案。',
      );
    });
  });

  group('孤儿 widget 不应留在仓库里', () {
    test('home_widgets.dart 里每个公开 widget 都有真实调用方', () {
      final declared = RegExp(r'class (Home\w+) extends StatelessWidget')
          .allMatches(homeWidgets)
          .map((m) => m.group(1)!)
          .toSet();

      // 在整个 lib 下统计引用（排除声明文件自身）。
      final orphans = <String>[];
      for (final name in declared) {
        var refs = 0;
        final dir = Directory('lib');
        for (final f in dir.listSync(recursive: true)) {
          if (f is! File || !f.path.endsWith('.dart')) continue;
          if (f.path.endsWith('home_widgets.dart')) continue;
          refs += RegExp(
            r'\b' + name + r'\b',
          ).allMatches(f.readAsStringSync()).length;
        }
        if (refs == 0) orphans.add(name);
      }

      expect(
        orphans,
        isEmpty,
        reason:
            'home_widgets.dart 里这些 widget 在 lib 下零引用：$orphans。'
            '删除前须确认其 affordance 已被现役组件覆盖（能力审计），确认后删掉。',
      );
    });
  });
}
