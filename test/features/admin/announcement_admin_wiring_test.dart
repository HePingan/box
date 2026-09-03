import 'package:box/features/admin/data/resource_registry.dart';
import 'package:box/features/admin/domain/admin_resource.dart';
import 'package:box/features/admin/register_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('公告 Tab 已注册进管理后台，删掉注册会红灯', () {
    registerResourceProviders();
    final types = ResourceRegistry.all.map((p) => p.resourceType);
    expect(
      types,
      contains(AdminResourceType.announcement),
      reason: '管理后台必须能发现公告 Tab，否则后台里看不到公告管理入口',
    );
  });
}
