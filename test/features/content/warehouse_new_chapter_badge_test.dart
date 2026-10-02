// 「有新话」角标（内容页漫画收藏的卡片）。**不联网**：直接给条目塞新话数。
//
// 为什么要锁：这是这次改动里唯一"用户直接看得到"的东西，而且它和雷同的
// 「进度百分比」「读到第几话」两个角标挤在同一张封面上 —— 位置撞了就白做。
library;

import 'package:box/features/content/domain/warehouse_models.dart';
import 'package:box/features/content/presentation/widgets/warehouse_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WarehouseItem _item({int newChapters = 0, String subtitle = '在线 · 3 页'}) =>
    WarehouseItem(
      id: 'comic_1',
      title: '航海王',
      subtitle: subtitle,
      coverUrl: '',
      detailUrl: '',
      meta: '',
      category: WarehouseCategory.comics,
      sourceLabel: '漫画收藏',
      createdAt: 0,
      newChapters: newChapters,
    );

Future<void> _pump(WidgetTester tester, WarehouseItem item) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: WarehouseCard(item: item, onTap: () {})),
      ),
    ),
  );
}

void main() {
  testWidgets('有新话（1 话）：显示「有新话」', (tester) async {
    await _pump(tester, _item(newChapters: 1));

    expect(find.text('有新话'), findsOneWidget);
  });

  testWidgets('新话多于 1：显示话数（"新 3 话"）', (tester) async {
    await _pump(tester, _item(newChapters: 3));

    expect(find.text('新 3 话'), findsOneWidget);
  });

  testWidgets('没有新话：不显示角标（不凭空造红点）', (tester) async {
    await _pump(tester, _item());

    expect(find.text('有新话'), findsNothing);
    expect(find.textContaining('新 '), findsNothing);
  });

  test('withNewChapters 不改原条目（条目是 const 的）', () {
    final base = _item();
    final updated = base.withNewChapters(2);

    expect(base.newChapters, 0);
    expect(updated.newChapters, 2);
    expect(updated.title, base.title);
    expect(updated.category, base.category);
  });
}
