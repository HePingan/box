import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/local_tools/presentation/local_tools_registry.dart';
import 'package:box/features/tools/application/tool_catalog.dart';

/// 本地工具接线的「防假入口」测试。
///
/// 这组测试守的是一条产品底线：**目录里能点的工具，点进去必须真的有东西**。
///
/// 之前踩过的坑是「名单加上了、页面没实现」—— 徽标显示可用，点进去
/// 空面板或掉进 Photopea。所有测试都是针对真实代码结构的核对，
/// 不靠人工记忆（漏一个 id 就红）。
void main() {
  group('kLocalTools ↔ kToolTargets 一致性', () {
    test('每个本地工具 id 都能在 kLocalTools 里定位（无悬空引用）', () {
      final localTargets = <String, String>{};
      for (final e in kToolTargets.entries) {
        final t = e.value;
        if (t is LocalToolTarget) {
          localTargets[e.key] = t.localId;
        }
      }
      expect(localTargets, isNotEmpty, reason: '本地工具一个都没接上？');

      for (final e in localTargets.entries) {
        expect(
          kLocalTools.containsKey(e.value),
          isTrue,
          reason: '目录条目「${e.key}」指向 localId=「${e.value}」，'
              '但 kLocalTools 里没有这个 id —— 点了会进「未找到」页',
        );
      }
    });

    test('kLocalTools 里每个工具都被目录引用（无孤儿实现）', () {
      final referenced = <String>{};
      for (final t in kToolTargets.values) {
        if (t is LocalToolTarget) referenced.add(t.localId);
      }
      for (final id in kLocalTools.keys) {
        expect(
          referenced.contains(id),
          isTrue,
          reason: 'kLocalTools 里的「$id」没有任何目录条目指向它 —— '
              '实现了但用户到不了，等于没做',
        );
      }
    });

    test('每个 LocalToolTarget 的 localId 都非空', () {
      for (final e in kToolTargets.entries) {
        final t = e.value;
        if (t is LocalToolTarget) {
          expect(t.localId.trim(), isNotEmpty, reason: '「${e.key}」的 id 是空的');
        }
      }
    });

    test('本批接入的 9 个工具确实在目录里（回归护栏）', () {
      // 精确名，不是模糊匹配 —— 目录里没有「BMI计算」这个条目，所以
      // 它没有被接线（domain 逻辑保留，等有人往目录里加条目再接）。
      const expected = [
        '科学计算器',
        '单位换算',
        '房贷计算器',
        '日期计算',
        '时间戳转换',
        '进制转换',
        '大小写转换',
        '随机密码',
        '亲戚称呼计算',
      ];
      for (final name in expected) {
        expect(
          kToolTargets[name],
          isA<LocalToolTarget>(),
          reason: '「$name」应当已接线为本地工具',
        );
      }
    });
  });

  group('每个本地工具都能真的 build 出内容（防空壳）', () {
    for (final entry in kLocalTools.entries) {
      testWidgets('「${entry.value.title}」渲染出非空 UI', (tester) async {
        await tester.pumpWidget(
          MaterialApp(home: LocalToolPage(localId: entry.key)),
        );
        await tester.pump(const Duration(milliseconds: 50));

        // 标题必须出现 —— 空壳 / 白屏 / 未找到页都会让这条红。
        expect(
          find.text(entry.value.title),
          findsWidgets,
          reason: '「${entry.key}」没有渲染出标题，可能是空壳实现',
        );

        // 而且不能是「未找到本地工具」那个兜底页。
        expect(
          find.textContaining('未找到本地工具'),
          findsNothing,
          reason: '「${entry.key}」掉进了兜底页 —— id 对不上',
        );
      });
    }
  });

  group('LocalToolPage 的兜底行为', () {
    testWidgets('未知 localId 给明确错误页而不是白屏/崩溃', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: LocalToolPage(localId: 'no_such_tool_xyz')),
      );
      await tester.pump();

      expect(find.textContaining('未找到本地工具'), findsOneWidget);
      // 要有返回出口，不能把用户困住。
      expect(find.text('返回'), findsOneWidget);
    });
  });
}
