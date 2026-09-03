import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:box/features/admin/data/resource_registry.dart';
import 'package:box/features/admin/domain/admin_resource.dart';
import 'package:box/features/admin/domain/admin_resource_provider.dart';
import 'package:box/features/admin/presentation/widgets/book_source_tab.dart';
import 'package:box/features/admin/presentation/widgets/video_source_tab.dart';

void main() {
  group('AdminResourceType enum', () {
    test('values contain all expected types', () {
      expect(AdminResourceType.values.length, 7);
    });

    test('fromType finds correct enum', () {
      expect(AdminResourceType.fromType('image-provider'),
          AdminResourceType.imageProvider);
      expect(
          AdminResourceType.fromType('book-source'), AdminResourceType.bookSource);
      expect(
          AdminResourceType.fromType('video-source'), AdminResourceType.videoSource);
    });

    test('fromType returns null for unknown type', () {
      expect(AdminResourceType.fromType('unknown'), isNull);
    });

    test('order is unique per type', () {
      final orders = AdminResourceType.values.map((e) => e.order).toSet();
      expect(orders.length, AdminResourceType.values.length);
    });
  });

  group('ResourceRegistry', () {
    setUp(() {
      ResourceRegistry.reset();
    });

    test('register then get returns the same provider', () {
      final provider = _FakeResourceProvider(AdminResourceType.bookSource);
      ResourceRegistry.register(provider);
      expect(ResourceRegistry.get(AdminResourceType.bookSource), provider);
    });

    test('isRegistered returns correct status', () {
      final provider = _FakeResourceProvider(AdminResourceType.videoSource);
      ResourceRegistry.register(provider);
      expect(ResourceRegistry.isRegistered(AdminResourceType.videoSource), true);
      expect(
          ResourceRegistry.isRegistered(AdminResourceType.imageProvider), false);
    });

    test('all returns providers sorted by order', () {
      // 注册乱序
      ResourceRegistry.register(
          _FakeResourceProvider(AdminResourceType.bookSource));
      ResourceRegistry.register(
          _FakeResourceProvider(AdminResourceType.imageProvider));
      ResourceRegistry.register(
          _FakeResourceProvider(AdminResourceType.videoSource));

      final all = ResourceRegistry.all;
      expect(all.length, 3);
      // 按 order 排序：imageProvider(0) < bookSource(1) < videoSource(2)
      expect(all[0].resourceType, AdminResourceType.imageProvider);
      expect(all[1].resourceType, AdminResourceType.bookSource);
      expect(all[2].resourceType, AdminResourceType.videoSource);
    });

    test('register overwrites existing type', () {
      final first = _FakeResourceProvider(AdminResourceType.imageProvider);
      final second = _FakeResourceProvider(AdminResourceType.imageProvider);
      ResourceRegistry.register(first);
      ResourceRegistry.register(second);
      expect(
          ResourceRegistry.get(AdminResourceType.imageProvider), same(second));
    });

    test('get returns null for unregistered type', () {
      expect(ResourceRegistry.get(AdminResourceType.bookSource), isNull);
    });
  });

  group('BookSourceResourceProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('resourceType is bookSource', () {
      final provider = BookSourceResourceProvider();
      expect(provider.resourceType, AdminResourceType.bookSource);
    });

    test('fetchAll returns empty list (local management)', () async {
      final provider = BookSourceResourceProvider();
      final result = await provider.fetchAll(null, null);
      expect(result, isEmpty);
    });

    test('buildListPage, create, update, delete are callable', () {
      final provider = BookSourceResourceProvider();
      expect(provider.buildListPage, isA<Function>());
      expect(provider.create, isA<Function>());
      expect(provider.update, isA<Function>());
      expect(provider.delete, isA<Function>());
    });
  });

  group('VideoSourceResourceProvider', () {
    test('resourceType is videoSource', () {
      final provider = VideoSourceResourceProvider();
      expect(provider.resourceType, AdminResourceType.videoSource);
    });

    test('fetchAll returns empty list', () async {
      final provider = VideoSourceResourceProvider();
      final result = await provider.fetchAll(null, null);
      expect(result, isEmpty);
    });

    test('buildListPage, create, update, delete are callable', () {
      final provider = VideoSourceResourceProvider();
      expect(provider.buildListPage, isA<Function>());
      expect(provider.create, isA<Function>());
      expect(provider.update, isA<Function>());
      expect(provider.delete, isA<Function>());
    });
  });
}

/// 用于 Registry 测试的假提供者
class _FakeResourceProvider implements ResourceProvider<ResourceData> {
  _FakeResourceProvider(this._type);

  final AdminResourceType _type;

  @override
  AdminResourceType get resourceType => _type;

  @override
  Widget buildListPage({
    required BuildContext context,
    String? serverUrl,
    String? token,
  }) {
    return const SizedBox.shrink();
  }

  @override
  Future<ResourceData> create(
    String? serverUrl,
    String? token,
    Map<String, dynamic> data,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String? serverUrl, String? token, String id) {
    throw UnimplementedError();
  }

  @override
  Future<List<ResourceData>> fetchAll(String? serverUrl, String? token) async {
    return [];
  }

  @override
  Future<ResourceData> update(
    String? serverUrl,
    String? token,
    String id,
    Map<String, dynamic> data,
  ) {
    throw UnimplementedError();
  }
}
