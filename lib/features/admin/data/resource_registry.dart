import 'package:flutter/foundation.dart';

import '../domain/admin_resource.dart';
import '../domain/admin_resource_provider.dart';

/// 资源提供者注册表
///
/// 各模块在启动时调用 [register] 注册自己的资源提供者，
/// 管理后台通过 [all] 获取所有已注册的类型，自动生成 Tab。
class ResourceRegistry {
  ResourceRegistry._();

  static final Map<AdminResourceType, ResourceProvider> _providers = {};

  /// 注册一个资源提供者
  static void register(ResourceProvider provider) {
    _providers[provider.resourceType] = provider;
  }

  /// 获取指定类型的提供者
  static ResourceProvider? get(AdminResourceType type) {
    return _providers[type];
  }

  /// 获取所有已注册的提供者（按 order 排序）
  static List<ResourceProvider> get all {
    final list = _providers.values.toList();
    list.sort((a, b) => a.resourceType.order.compareTo(b.resourceType.order));
    return list;
  }

  /// 是否已注册
  static bool isRegistered(AdminResourceType type) {
    return _providers.containsKey(type);
  }

  /// 清除所有注册（仅用于测试）
  @visibleForTesting
  static void reset() {
    _providers.clear();
  }
}
