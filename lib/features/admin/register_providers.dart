import 'data/resource_registry.dart';
import 'presentation/widgets/book_source_tab.dart';
import 'presentation/widgets/image_provider_tab.dart';
import 'presentation/widgets/plugin_policy_tab.dart';
import 'presentation/widgets/plugin_market_admin_tab.dart';
import 'presentation/widgets/announcement_tab.dart';
import 'presentation/widgets/video_source_tab.dart';
import 'presentation/widgets/quiz_bank_tab.dart';

/// 初始化所有资源提供者并注册到 [ResourceRegistry]
///
/// 在应用启动时调用一次。各模块在此注册自己的资源提供者，
/// 管理后台自动发现并显示对应的 Tab。
void registerResourceProviders() {
  // AI 生图工坊
  ResourceRegistry.register(ImageProviderResourceProvider());

  // 小说书源，本地管理，通过 BookSourceManager 操作
  ResourceRegistry.register(BookSourceResourceProvider());

  // 视频源，通过 VideoController 加载远程采集站
  ResourceRegistry.register(VideoSourceResourceProvider());

  // 远程题库，支持题目 CRUD 与待审核投稿状态
  ResourceRegistry.register(QuizBankResourceProvider());

  // 插件远程禁用策略
  ResourceRegistry.register(PluginPolicyResourceProvider());

  // 用户插件市场审核
  ResourceRegistry.register(PluginMarketAdminResourceProvider());

  // 站内公告：草稿、发布、置顶、编辑和删除
  ResourceRegistry.register(AnnouncementResourceProvider());
}
