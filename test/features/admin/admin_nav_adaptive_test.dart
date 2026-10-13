import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:box/features/admin/data/resource_registry.dart';
import 'package:box/features/admin/domain/admin_resource.dart';
import 'package:box/features/admin/domain/admin_resource_provider.dart';
import 'package:box/features/admin/presentation/admin_page.dart';

/// 护栏：管理后台导航在窄屏必须全量可见。
///
/// 根因（2026-10-12 真机截图确认）：原横向可滚动 TabBar 在手机上 7 个 Tab
/// 有 2 个被挤出屏幕且无任何提示——「视频源」可见，而「AI 生图」「小说书源」
/// 完全不可见，用户不知道左边还有内容。
///
/// 现行解法：窄屏（<720）Drawer 侧边导航，宽屏（>=720）TabBar。
/// 这条护栏钉住两端的形态，防止有人把窄屏改回横向 TabBar（那正是事故形态），
/// 或把宽屏也换成 Drawer（浪费横向空间）。
///
/// 为什么是 widget 测试而不是源码扫描：可见性是布局行为，静态扫描查不到
/// 「TabBar 之外还有没有别处挤掉导航项」这类回归；pump 出来数才是硬判据。
class _FakeProvider implements ResourceProvider<ResourceData> {
  _FakeProvider(this._type);

  final AdminResourceType _type;

  @override
  AdminResourceType get resourceType => _type;

  @override
  Widget buildListPage({
    required BuildContext context,
    String? serverUrl,
    String? token,
  }) =>
      const SizedBox.shrink();

  @override
  Future<List<ResourceData>> fetchAll(String? serverUrl, String? token) async => [];

  @override
  Future<ResourceData> create(
          String? serverUrl, String? token, Map<String, dynamic> data) =>
      throw UnimplementedError();

  @override
  Future<ResourceData> update(
          String? serverUrl, String? token, String id, Map<String, dynamic> data) =>
      throw UnimplementedError();

  @override
  Future<void> delete(String? serverUrl, String? token, String id) async {}
}

void main() {
  // 与生产一致的 7 个模块（顺序按 order）。
  const types = AdminResourceType.values;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ResourceRegistry.reset();
    for (final t in types) {
      ResourceRegistry.register(_FakeProvider(t));
    }
  });

  tearDown(() => ResourceRegistry.reset());

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: AdminPage()));
    await tester.pump();
  }

  testWidgets('窄屏(360dp)：7 个模块在 Drawer 侧边导航里全部可见，不再用 TabBar', (tester) async {
    await pumpAt(tester, const Size(360, 800));

    expect(find.byType(TabBar), findsNothing,
        reason: '窄屏渲染 TabBar 就是 2026-10-12 的事故形态：7 个 Tab 挤掉 2 个');
    // Scaffold 的 drawer 关闭时不构建，先打开再验内容。
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget,
        reason: '窄屏必须用 Drawer 导航，否则回到『Tab 被挤出屏幕』的事故形态');
    for (final t in types) {
      expect(find.text(t.displayName), findsWidgets,
          reason: '模块「${t.displayName}」在窄屏导航里不可见——导航项被挤掉了');
    }
  });

  testWidgets('宽屏(800dp)：仍用 TabBar，不再渲染 Drawer', (tester) async {
    await pumpAt(tester, const Size(800, 600));

    expect(find.byType(TabBar), findsOneWidget,
        reason: '宽屏应保留 TabBar 利用横向空间');
    expect(find.byType(Drawer), findsNothing,
        reason: '宽屏也用 Drawer 会浪费横向空间，回归本次改动的意图');
    for (final t in types) {
      expect(find.text(t.displayName), findsWidgets,
          reason: '宽屏 TabBar 上模块「${t.displayName}」缺失');
    }
  });
}
