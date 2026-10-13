import 'package:flutter/material.dart';
import '../../../design_system/app_tokens.dart';

import '../../account/data/account_store.dart';
import '../data/resource_registry.dart';
import '../domain/admin_resource_provider.dart';

/// 统一管理后台首页
///
/// 通过 [ResourceRegistry] 自动发现所有已注册的资源类型。
///
/// 布局策略（2026-10-12 改版，移动优先）：
///   原实现用横向可滚动 TabBar。实测在手机上 7 个 Tab 会有 2 个被挤出
///   屏幕且无任何提示，用户不知道左侧还有内容（截图确认：最左侧显示
///   「视频源」，而「AI 生图」「小说书源」完全不可见）。
///
///   现改为：窄屏用 Drawer 侧边导航（顶栏显示当前模块名 + 菜单按钮），
///   宽屏（>=720）仍用 TabBar 以利用横向空间。
///   两种形态共用同一份 providers 与选中索引，切换屏幕尺寸时状态不丢。
///
/// 不再全局拦截登录——各 Tab 自行决定是否需要管理员权限。
/// 本地功能（书源、视频源）无需登录即可使用；
/// AI 生图等需要后端 API 的 Tab 内部检查 session。
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> with TickerProviderStateMixin {
  TabController? _tabController;
  int _refreshKey = 0;
  int _index = 0;

  /// 宽屏阈值：超过则用 TabBar，否则用 Drawer。
  /// 720 取平板竖屏与手机横屏之间，手机竖屏（<=430 逻辑像素）稳定走 Drawer。
  static const double _wideBreakpoint = 720;

  @override
  void initState() {
    super.initState();
    _initTabs();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  void _initTabs() {
    _tabController?.dispose();
    final providers = ResourceRegistry.all;
    if (providers.length < 2) return;
    _tabController = TabController(length: providers.length, vsync: this);
    _tabController!.addListener(() {
      if (!_tabController!.indexIsChanging) {
        setState(() {
          _index = _tabController!.index;
        });
      }
    });
  }

  void _refresh() {
    setState(() {
      _refreshKey++;
    });
  }

  /// 切换模块：同时更新 TabController 与本地索引，保证两种布局一致。
  void _select(int index) {
    setState(() => _index = index);
    if (_tabController != null && _tabController!.index != index) {
      _tabController!.index = index;
    }
  }

  @override
  Widget build(BuildContext context) {
    final providers = ResourceRegistry.all;
    final isWide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;

    // 单模块时不显示任何导航
    if (providers.length < 2) {
      return Scaffold(
        appBar: AppBar(
          title: Text(providers.isEmpty ? 'Box 管理后台' : providers.first.resourceType.displayName),
          leading: const BackButton(),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: '刷新',
              onPressed: _refresh,
            ),
          ],
        ),
        body: _buildBody(providers),
      );
    }

    final current = providers[_index.clamp(0, providers.length - 1)];

    return Scaffold(
      // 窄屏：Drawer 侧边导航
      drawer: isWide ? null : _buildDrawer(providers),
      appBar: AppBar(
        // 窄屏用菜单按钮 + 当前模块名；宽屏保留全局标题
        title: Text(isWide ? 'Box 管理后台' : current.resourceType.displayName),
        leading: isWide ? const BackButton() : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新当前模块',
            onPressed: _refresh,
          ),
        ],
        bottom: isWide ? _buildTabBar(providers) : null,
      ),
      body: _buildBody(providers),
    );
  }

  /// 窄屏侧边导航：竖排列表，7 项全部可见，无需横向滚动。
  Widget _buildDrawer(List<ResourceProvider> providers) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Box 管理后台',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${providers.length} 个模块',
                    style: TextStyle(fontSize: 12, color: AppTokens.textSecondary),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: providers.length,
                itemBuilder: (context, i) {
                  final p = providers[i];
                  final selected = i == _index;
                  return ListTile(
                    dense: false,
                    selected: selected,
                    selectedTileColor: AppTokens.primaryBlue.withValues(alpha: 0.10),
                    leading: Icon(
                      _iconFor(p.resourceType.type),
                      size: 22,
                      color: selected ? AppTokens.primaryBlue : AppTokens.textSecondary,
                    ),
                    title: Text(
                      p.resourceType.displayName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected ? AppTokens.primaryBlue : AppTokens.textPrimary,
                      ),
                    ),
                    trailing: selected
                        ? Icon(Icons.check_rounded, size: 18, color: AppTokens.primaryBlue)
                        : null,
                    onTap: () {
                      Navigator.of(context).pop(); // 关抽屉
                      _select(i);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 宽屏保留原 TabBar 形态。
  PreferredSizeWidget _buildTabBar(List<ResourceProvider> providers) {
    return TabBar(
      controller: _tabController,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      unselectedLabelStyle: const TextStyle(fontSize: 14),
      tabs: providers
          .map((p) => Tab(text: p.resourceType.displayName))
          .toList(),
    );
  }

  /// 各模块的图标。集中在此便于统一调整；未列出的用通用图标兜底。
  ///
  /// ⚠️ 选图标注意（2026-10-12 踩坑）：
  ///   Flutter 构建时会对 MaterialIcons 做 tree-shaking，只保留
  ///   「静态可达」的字形。实测若某图标【仅在此 switch 中引用一次】，
  ///   字形可能被裁掉 —— 表现为列表里该项图标空白（题库、插件策略曾中招）。
  ///
  ///   规避方式（任一）：
  ///     1. 优先选码点在 BMP 内（<= U+FFFF）且项目别处也有引用的图标；
  ///     2. 需要新图标时，先在别处以 const 形式引用一次再用。
  ///   本次 `quiz_rounded`(U+F00D4) 与 `policy_rounded`(U+F00AE) 被裁，
  ///   换成 `checklist_rounded`(U+F637) 与 `policy_outlined`(U+F2BC) 后正常。
  static IconData _iconFor(String type) {
    switch (type) {
      case 'image-provider':
        return Icons.auto_awesome_rounded;
      case 'book-source':
        return Icons.menu_book_rounded;
      case 'video-source':
        return Icons.movie_creation_outlined;
      case 'quiz-bank':
        return Icons.checklist_rounded;
      case 'plugin-policy':
        return Icons.policy_outlined;
      case 'plugin-market':
        return Icons.storefront_rounded;
      case 'announcement':
        return Icons.campaign_rounded;
      default:
        return Icons.widgets_rounded;
    }
  }

  Widget _buildBody(List<ResourceProvider> providers) {
    if (providers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.extension_off_rounded,
                size: 48,
                color: Colors.grey,
              ),
              const SizedBox(height: 12),
              Text('暂无可用功能', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                '未注册任何管理模块',
                style: TextStyle(color: AppTokens.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    // 从 session 获取 serverUrl/token（可能为 null）
    final session = globalSessionNotifier.value;
    final serverUrl = session?.serverUrl;
    final token = session?.token;

    if (providers.length == 1) {
      return KeyedSubtree(
        key: ValueKey('${providers[0].resourceType.type}_$_refreshKey'),
        child: providers[0].buildListPage(
          context: context,
          serverUrl: serverUrl,
          token: token,
        ),
      );
    }

    // 窄屏没有 TabBarView（TabController 与 Drawer 不同步），
    // 直接渲染当前选中模块的页面，避免手势滑动与抽屉语义冲突。
    final isWide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;
    if (!isWide) {
      final p = providers[_index.clamp(0, providers.length - 1)];
      return KeyedSubtree(
        key: ValueKey('${p.resourceType.type}_${_refreshKey}_$_index'),
        child: p.buildListPage(
          context: context,
          serverUrl: serverUrl,
          token: token,
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: providers.map((p) {
        return KeyedSubtree(
          key: ValueKey('${p.resourceType.type}_$_refreshKey'),
          child: p.buildListPage(
            context: context,
            serverUrl: serverUrl,
            token: token,
          ),
        );
      }).toList(),
    );
  }
}
