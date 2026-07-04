import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/design_system/widgets/empty_error_states.dart';
import 'package:box/design_system/widgets/shimmer_skeleton.dart';
import 'package:box/design_system/app_tokens.dart';
import 'package:box/novel/pages/source_manager/widgets/book_source_manager_widgets.dart';
import 'package:box/novel/pages/source_manager/book_source_model.dart';
import 'package:box/novel/pages/source_manager/book_source_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ──────────────────────────────────────────
// 辅助方法
// ──────────────────────────────────────────

Widget wrapApp(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: AppTokens.seed),
      useMaterial3: true,
    ),
    home: Scaffold(body: child),
  );
}

void main() {
  // ── EmptyStateView ──
  group('EmptyStateView', () {
    testWidgets('renders icon, title, and subtitle', (tester) async {
      await tester.pumpWidget(wrapApp(
        const EmptyStateView(
          icon: Icons.book_rounded,
          title: '没有找到书籍',
          subtitle: '试试换个关键词',
        ),
      ));

      expect(find.text('没有找到书籍'), findsOneWidget);
      expect(find.text('试试换个关键词'), findsOneWidget);
      expect(find.byIcon(Icons.book_rounded), findsOneWidget);
    });

    testWidgets('renders action button when provided', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrapApp(
        EmptyStateView(
          icon: Icons.refresh_rounded,
          title: '出错了',
          actionLabel: '重试',
          actionIcon: Icons.refresh_rounded,
          onAction: () => tapped = true,
        ),
      ));

      expect(find.text('重试'), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsWidgets);

      await tester.tap(find.text('重试'));
      expect(tapped, isTrue);
    });

    testWidgets('renders without subtitle', (tester) async {
      await tester.pumpWidget(wrapApp(
        const EmptyStateView(
          icon: Icons.info_rounded,
          title: '暂无内容',
        ),
      ));

      expect(find.text('暂无内容'), findsOneWidget);
      expect(find.text('试试换个关键词'), findsNothing);
    });
  });

  // ── ErrorStateView ──
  group('ErrorStateView', () {
    testWidgets('renders error message and retry button', (tester) async {
      var retried = false;
      await tester.pumpWidget(wrapApp(
        ErrorStateView(
          message: '网络连接失败',
          onRetry: () => retried = true,
        ),
      ));

      expect(find.text('网络连接失败'), findsOneWidget);
      expect(find.text('重新加载'), findsOneWidget);

      await tester.tap(find.text('重新加载'));
      expect(retried, isTrue);
    });
  });

  // ── ShimmerSkeleton ──
  group('ShimmerSkeleton', () {
    testWidgets('DetailPageSkeleton renders without crash', (tester) async {
      await tester.pumpWidget(wrapApp(
        const DetailPageSkeleton(),
      ));
      // 骨架屏内部使用 ShimmerAnimation + RepaintBoundary，验证能渲染
      expect(find.byType(DetailPageSkeleton), findsOneWidget);
    });

    testWidgets('BookshelfSkeleton renders without crash', (tester) async {
      await tester.pumpWidget(wrapApp(
        const BookshelfSkeleton(),
      ));
      expect(find.byType(BookshelfSkeleton), findsOneWidget);
    });

    testWidgets('BookListSkeleton renders without overflow', (tester) async {
      await tester.pumpWidget(wrapApp(
        const SizedBox(
          width: double.infinity,
          height: 900,
          child: SingleChildScrollView(
            child: BookListSkeleton(),
          ),
        ),
      ));

      expect(find.byType(BookListSkeleton), findsOneWidget);
    });
  });

  // ── AppTokens (design tokens) ──
  group('AppTokens', () {
    test('brand colors are correctly defined', () {
      expect(AppTokens.primaryBlue, equals(const Color(0xFF2563EB)));
      expect(AppTokens.violet, equals(const Color(0xFF7C3AED)));
      expect(AppTokens.emerald, equals(const Color(0xFF10B981)));
      expect(AppTokens.rose, equals(const Color(0xFFF43F5E)));
      expect(AppTokens.ink, equals(const Color(0xFF0F172A)));
    });

    test('spacing tokens are positive', () {
      expect(AppTokens.spaceXs, greaterThan(0));
      expect(AppTokens.spaceSm, greaterThan(0));
      expect(AppTokens.spaceMd, greaterThan(0));
      expect(AppTokens.spaceLg, greaterThan(0));
      expect(AppTokens.spaceXl, greaterThan(0));
    });

    test('radius tokens are positive', () {
      expect(AppTokens.radiusXs, greaterThan(0));
      expect(AppTokens.radiusSm, greaterThan(0));
      expect(AppTokens.radiusMd, greaterThan(0));
      expect(AppTokens.radiusLg, greaterThan(0));
    });

    test('gradients have correct number of colors', () {
      expect(AppTokens.blueGradient.colors.length, 2);
      expect(AppTokens.pageGradient.colors.length, 3);
      expect(AppTokens.violetGradient.colors.length, 2);
      expect(AppTokens.emeraldGradient.colors.length, 2);
    });

    test('shadows are correctly structured', () {
      final shadows = AppTokens.cardShadow();
      expect(shadows.length, 3);
    });
  });

  // ── BookSourceSimpleChip ──
  group('BookSourceSimpleChip', () {
    testWidgets('renders with text and color', (tester) async {
      await tester.pumpWidget(wrapApp(
        const BookSourceSimpleChip(
          text: '已启用',
          color: Colors.green,
        ),
      ));

      expect(find.text('已启用'), findsOneWidget);
    });

    testWidgets('renders with custom background color', (tester) async {
      await tester.pumpWidget(wrapApp(
        const BookSourceSimpleChip(
          text: '自定义',
          color: Colors.blue,
          backgroundColor: Color(0x1A2563EB),
        ),
      ));

      expect(find.text('自定义'), findsOneWidget);
    });
  });

  // ── BookSourceModel ──
  group('BookSourceModel', () {
    test('fromJson parses basic fields', () {
      final json = {
        'bookSourceName': '测试书源',
        'bookSourceUrl': 'https://example.com',
        'bookSourceGroup': '测试组',
        'enabled': true,
      };

      final model = BookSourceModel.fromJson(json);

      expect(model.bookSourceName, '测试书源');
      expect(model.bookSourceUrl, 'https://example.com');
      expect(model.bookSourceGroup, '测试组');
      expect(model.enabled, isTrue);
    });

    test('fromJson handles empty json', () {
      final model = BookSourceModel.fromJson({});

      expect(model.bookSourceName, isEmpty);
      expect(model.bookSourceUrl, isEmpty);
      expect(model.enabled, isTrue); // 默认启用
    });

    test('toJson round-trip preserves data', () {
      final original = BookSourceModel.fromJson({
        'bookSourceName': '往返测试',
        'bookSourceUrl': 'https://test.com',
        'bookSourceGroup': '测试',
        'enabled': false,
        'customOrder': 5,
        'weight': 10,
      });

      final json = original.toJson();
      final restored = BookSourceModel.fromJson(json);

      expect(restored.bookSourceName, '往返测试');
      expect(restored.bookSourceUrl, 'https://test.com');
      expect(restored.bookSourceGroup, '测试');
      expect(restored.enabled, isFalse);
      expect(restored.customOrder, 5);
      expect(restored.weight, 10);
    });

    test('id is unique for different sources', () {
      final a = BookSourceModel.fromJson({
        'bookSourceName': '源A',
        'bookSourceUrl': 'https://a.com',
      });
      final b = BookSourceModel.fromJson({
        'bookSourceName': '源B',
        'bookSourceUrl': 'https://b.com',
      });

      expect(a.id, isNot(equals(b.id)));
    });

    test('copyWith creates modified copy', () {
      final original = BookSourceModel.fromJson({
        'bookSourceName': '原名称',
        'bookSourceUrl': 'https://original.com',
      });

      final modified = original.copyWith(
        bookSourceName: '新名称',
        enabled: false,
      );

      expect(modified.bookSourceName, '新名称');
      expect(modified.enabled, isFalse);
      expect(modified.bookSourceUrl, original.bookSourceUrl); // 保持不变
    });
  });

  // ── BookSourceManager.decodeStoredList ──
  group('BookSourceManager.decodeStoredList', () {
    test('decodes valid JSON', () {
      final json =
          '[{"bookSourceName":"源1","bookSourceUrl":"https://a.com"},{"bookSourceName":"源2","bookSourceUrl":"https://b.com"}]';
      final list = BookSourceManager.decodeStoredList(json);
      expect(list.length, 2);
      expect(list[0].bookSourceName, '源1');
      expect(list[1].bookSourceName, '源2');
    });

    test('returns empty list for null input', () {
      expect(BookSourceManager.decodeStoredList(null), isEmpty);
    });

    test('returns empty list for empty string', () {
      expect(BookSourceManager.decodeStoredList(''), isEmpty);
    });

    test('returns empty list for invalid JSON', () {
      expect(BookSourceManager.decodeStoredList('not json'), isEmpty);
    });
  });

  // ── BookSourceManager ──
  group('BookSourceManager', () {
    late BookSourceManager manager;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      manager = BookSourceManager(prefs);
      await manager.load();
    });

    test('starts with empty items', () {
      expect(manager.items, isEmpty);
    });

    test('addOrUpdate adds new source', () async {
      final source = BookSourceModel.fromJson({
        'bookSourceName': '新源',
        'bookSourceUrl': 'https://new.com',
      });
      await manager.addOrUpdate(source);

      expect(manager.items.length, 1);
      expect(manager.items.first.bookSourceName, '新源');
    });

    test('addOrUpdate updates existing source', () async {
      final source = BookSourceModel.fromJson({
        'bookSourceName': '初始',
        'bookSourceUrl': 'https://orig.com',
      });
      await manager.addOrUpdate(source);

      // copyWith 只改 enabled/weight 等不改变 id 的字段
      final updated = source.copyWith(enabled: false);
      await manager.addOrUpdate(updated);

      expect(manager.items.length, 1);
      expect(manager.items.first.enabled, isFalse);
    });

    test('enabledItems returns only enabled', () async {
      await manager.addOrUpdate(BookSourceModel.fromJson({
        'bookSourceName': '已启用',
        'bookSourceUrl': 'https://a.com',
        'enabled': true,
      }));
      await manager.addOrUpdate(BookSourceModel.fromJson({
        'bookSourceName': '已禁用',
        'bookSourceUrl': 'https://b.com',
        'enabled': false,
      }));

      expect(manager.enabledItems.length, 1);
      expect(manager.enabledItems.first.bookSourceName, '已启用');
    });

    test('deleteById removes source', () async {
      final s1 = BookSourceModel.fromJson({
        'bookSourceName': '源1',
        'bookSourceUrl': 'https://a.com',
      });
      final s2 = BookSourceModel.fromJson({
        'bookSourceName': '源2',
        'bookSourceUrl': 'https://b.com',
      });
      await manager.addOrUpdate(s1);
      await manager.addOrUpdate(s2);

      await manager.deleteById(s1.id);

      expect(manager.items.length, 1);
      expect(manager.items.first.bookSourceName, '源2');
    });

    test('setCurrentSource works', () async {
      final s1 = BookSourceModel.fromJson({
        'bookSourceName': '源1',
        'bookSourceUrl': 'https://a.com',
      });
      await manager.addOrUpdate(s1);

      await manager.setCurrentSource(s1.id);
      expect(manager.currentSourceId, s1.id);
      expect(manager.currentSource?.bookSourceName, '源1');
    });

    test('search filters by name', () async {
      await manager.addOrUpdate(BookSourceModel.fromJson({
        'bookSourceName': '快眼看书',
        'bookSourceUrl': 'https://ky.com',
      }));
      await manager.addOrUpdate(BookSourceModel.fromJson({
        'bookSourceName': '猫眼看书',
        'bookSourceUrl': 'https://my.com',
      }));

      final results = manager.search('快眼');
      expect(results.length, 1);
      expect(results.first.bookSourceName, '快眼看书');
    });

    test('search filters by URL', () async {
      await manager.addOrUpdate(BookSourceModel.fromJson({
        'bookSourceName': '源A',
        'bookSourceUrl': 'https://example.com',
      }));
      await manager.addOrUpdate(BookSourceModel.fromJson({
        'bookSourceName': '源B',
        'bookSourceUrl': 'https://other.com',
      }));

      final results = manager.search('example');
      expect(results.length, 1);
      expect(results.first.bookSourceName, '源A');
    });
  });
}
