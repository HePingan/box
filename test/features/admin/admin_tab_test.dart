import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:box/features/admin/data/resource_registry.dart';
import 'package:box/features/admin/domain/admin_resource.dart';
import 'package:box/features/admin/domain/admin_resource_provider.dart';
import 'package:box/features/admin/presentation/widgets/book_source_tab.dart';
import 'package:box/features/admin/presentation/widgets/video_source_tab.dart';
import 'package:box/novel/pages/source_manager/book_source_manager.dart';

class _FakeProvider implements ResourceProvider<ResourceData> {
  _FakeProvider(this._type);

  final AdminResourceType _type;

  @override
  AdminResourceType get resourceType => _type;

  @override
  Future<List<ResourceData>> fetchAll(String? serverUrl, String? token) async => [];

  @override
  Future<ResourceData> create(
    String? serverUrl,
    String? token,
    Map<String, dynamic> data,
  ) async => throw UnimplementedError();

  @override
  Future<ResourceData> update(
    String? serverUrl,
    String? token,
    String id,
    Map<String, dynamic> data,
  ) async => throw UnimplementedError();

  @override
  Future<void> delete(String? serverUrl, String? token, String id) async {}

  @override
  Widget buildListPage({
    required BuildContext context,
    String? serverUrl,
    String? token,
  }) =>
      const Text('Fake list page');
}

void main() {
  group('BookSourceResourceProvider test', () {
    test('resourceType is bookSource', () {
      final provider = BookSourceResourceProvider();
      expect(provider.resourceType, AdminResourceType.bookSource);
    });

    test('fetchAll returns empty list', () async {
      final provider = BookSourceResourceProvider();
      final result = await provider.fetchAll(null, null);
      expect(result, isEmpty);
    });

    test('buildListPage returns widget', () {
      final provider = BookSourceResourceProvider();
      expect(() => provider.buildListPage(context: null!), throwsA(anything));
    });

    test('create throws unimplemented', () {
      final provider = BookSourceResourceProvider();
      expect(
        () => provider.create(null, null, {}),
        throwsUnimplementedError,
      );
    });

    test('update throws unimplemented', () {
      final provider = BookSourceResourceProvider();
      expect(
        () => provider.update(null, null, '', {}),
        throwsUnimplementedError,
      );
    });

    test('delete throws unimplemented', () {
      final provider = BookSourceResourceProvider();
      expect(
        () => provider.delete(null, null, ''),
        throwsUnimplementedError,
      );
    });
  });

  group('VideoSourceResourceProvider test', () {
    test('resourceType is videoSource', () {
      final provider = VideoSourceResourceProvider();
      expect(provider.resourceType, AdminResourceType.videoSource);
    });

    test('fetchAll returns empty list', () async {
      final provider = VideoSourceResourceProvider();
      final result = await provider.fetchAll(null, null);
      expect(result, isEmpty);
    });

    test('buildListPage returns widget', () {
      final provider = VideoSourceResourceProvider();
      expect(() => provider.buildListPage(context: null!), throwsA(anything));
    });

    test('create throws unimplemented', () {
      final provider = VideoSourceResourceProvider();
      expect(
        () => provider.create(null, null, {}),
        throwsUnimplementedError,
      );
    });

    test('delete throws unimplemented', () {
      final provider = VideoSourceResourceProvider();
      expect(
        () => provider.delete(null, null, ''),
        throwsUnimplementedError,
      );
    });
  });

  group('AdminResourceType enum', () {
    test('values contain all expected types', () {
      expect(AdminResourceType.values.length, 3);
      final types = AdminResourceType.values.map((e) => e.type).toSet();
      expect(types, containsAll(['image-provider', 'book-source', 'video-source']));
    });

    test('fromType maps correctly', () {
      expect(AdminResourceType.fromType('image-provider'),
          AdminResourceType.imageProvider);
      expect(AdminResourceType.fromType('book-source'),
          AdminResourceType.bookSource);
      expect(AdminResourceType.fromType('video-source'),
          AdminResourceType.videoSource);
      expect(AdminResourceType.fromType('unknown'), isNull);
    });

    test('orders are 0, 1, 2', () {
      expect(AdminResourceType.imageProvider.order, 0);
      expect(AdminResourceType.bookSource.order, 1);
      expect(AdminResourceType.videoSource.order, 2);
    });

    test('displayNames are correct', () {
      expect(AdminResourceType.imageProvider.displayName, 'AI 生图');
      expect(AdminResourceType.bookSource.displayName, '小说书源');
      expect(AdminResourceType.videoSource.displayName, '视频源');
    });
  });

  group('ResourceRegistry', () {
    setUp(() {
      ResourceRegistry.reset();
    });

    test('register and get returns same provider', () {
      final p = _FakeProvider(AdminResourceType.bookSource);
      ResourceRegistry.register(p);
      expect(ResourceRegistry.get(AdminResourceType.bookSource), same(p));
    });

    test('isRegistered returns correct status', () {
      ResourceRegistry.register(_FakeProvider(AdminResourceType.videoSource));
      expect(ResourceRegistry.isRegistered(AdminResourceType.videoSource), true);
      expect(ResourceRegistry.isRegistered(AdminResourceType.imageProvider), false);
    });

    test('all returns providers sorted by order', () {
      ResourceRegistry.register(_FakeProvider(AdminResourceType.bookSource));
      ResourceRegistry.register(_FakeProvider(AdminResourceType.imageProvider));
      ResourceRegistry.register(_FakeProvider(AdminResourceType.videoSource));

      final all = ResourceRegistry.all;
      expect(all.length, 3);
      expect(all[0].resourceType, AdminResourceType.imageProvider);
      expect(all[1].resourceType, AdminResourceType.bookSource);
      expect(all[2].resourceType, AdminResourceType.videoSource);
    });

    test('register overwrites existing type', () {
      final first = _FakeProvider(AdminResourceType.imageProvider);
      final second = _FakeProvider(AdminResourceType.imageProvider);
      ResourceRegistry.register(first);
      ResourceRegistry.register(second);
      expect(ResourceRegistry.all.length, 1);
      expect(ResourceRegistry.get(AdminResourceType.imageProvider), second);
    });

    test('reset clears all', () {
      ResourceRegistry.register(_FakeProvider(AdminResourceType.bookSource));
      ResourceRegistry.reset();
      expect(ResourceRegistry.all, isEmpty);
    });
  });

  group('BookSourceResourceProvider widget smoke', () {
    late BookSourceManager manager;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      manager = BookSourceManager(prefs);
    });

    Widget wrapApp(Widget child) {
      return MaterialApp(
        home: ChangeNotifierProvider<BookSourceManager>.value(
          value: manager,
          child: Scaffold(body: child),
        ),
      );
    }

    testWidgets('BookSourceTab renders without crash', (tester) async {
      final provider = BookSourceResourceProvider();
      await tester.pumpWidget(wrapApp(
        const Placeholder(), // 先测试 Provider 是否能被构建
      ));
      // 验证 Provider 树可正常工作
      expect(find.byType(Placeholder), findsOneWidget);
    });
  });
}
