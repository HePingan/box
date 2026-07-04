import 'package:flutter/material.dart';

import 'admin_resource.dart';

/// 资源提供者接口 — 每种资源类型实现此接口来接入管理后台
///
/// 实现此接口后，调用 [ResourceRegistry.register] 注册即可自动出现在管理后台的 Tab 中。
abstract class ResourceProvider<T extends ResourceData> {
  /// 资源类型标识，与 [AdminResourceType] 对应
  AdminResourceType get resourceType;

  /// 获取资源列表（需要服务端认证的传 serverUrl/token，否则 null）
  Future<List<T>> fetchAll(String? serverUrl, String? token);

  /// 创建资源
  Future<T> create(
    String? serverUrl,
    String? token,
    Map<String, dynamic> data,
  );

  /// 更新资源
  Future<T> update(
    String? serverUrl,
    String? token,
    String id,
    Map<String, dynamic> data,
  );

  /// 删除资源
  Future<void> delete(String? serverUrl, String? token, String id);

  /// 构建列表页面的内容
  Widget buildListPage({
    required BuildContext context,
    String? serverUrl,
    String? token,
  });
}
