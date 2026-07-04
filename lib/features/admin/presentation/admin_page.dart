import 'package:flutter/material.dart';

import '../../account/data/account_store.dart';
import '../data/resource_registry.dart';
import '../domain/admin_resource_provider.dart';

/// 统一管理后台首页
///
/// 通过 [ResourceRegistry] 自动发现所有已注册的资源类型，
/// 以 TabBar 切换各资源管理页面。
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
        setState(() {});
      }
    });
  }

  void _refresh() {
    setState(() {
      _refreshKey++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final providers = ResourceRegistry.all;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Box 管理后台'),
        leading: const BackButton(),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新所有 Tab',
            onPressed: _refresh,
          ),
        ],
        bottom: providers.length >= 2 ? _buildTabBar() : null,
      ),
      body: _buildBody(providers),
    );
  }

  PreferredSizeWidget _buildTabBar() {
    return TabBar(
      controller: _tabController,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      unselectedLabelStyle: const TextStyle(fontSize: 14),
      tabs: ResourceRegistry.all.map((p) {
        return Tab(text: p.resourceType.displayName);
      }).toList(),
    );
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
              const Text(
                '未注册任何管理模块',
                style: TextStyle(color: Colors.black54, fontSize: 13),
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
