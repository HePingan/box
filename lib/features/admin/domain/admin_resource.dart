/// 管理后台支持的资源类型枚举
///
/// 每种资源类型对应一个管理 Tab，由 [ResourceProvider] 实现其 CRUD 逻辑。
enum AdminResourceType {
  /// AI 生图工坊 — Provider 配置 + 用量 + 用户额度
  imageProvider('image-provider', 'AI 生图', 0),

  /// 小说书源 — 内置书源云端管理
  bookSource('book-source', '小说书源', 1),

  /// 视频源（预留）
  videoSource('video-source', '视频源', 2),

  /// 题库管理 — 远程题目与待审核投稿
  quizBank('quiz-bank', '题库', 3),

  /// 插件远程策略 — 全局/分插件/用户级禁用
  pluginPolicy('plugin-policy', '插件策略', 4),

  /// 插件市场审核 — 用户投稿 / 发布 / 下架
  pluginMarket('plugin-market', '插件市场', 5),

  /// 更多扩展...
  ;

  const AdminResourceType(this.type, this.displayName, this.order);

  /// 后端 API 路径标识，如 "image-provider" → /admin/resources/image-provider
  final String type;

  /// Tab 上显示的名称
  final String displayName;

  /// Tab 排序
  final int order;

  static AdminResourceType? fromType(String type) {
    for (final v in values) {
      if (v.type == type) return v;
    }
    return null;
  }
}

/// 资源数据的基类
abstract class ResourceData {
  const ResourceData();

  Map<String, dynamic> toJson();
}
