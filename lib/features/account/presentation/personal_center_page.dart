import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../data/personal_center_cache_service.dart';
import '../data/account_store.dart';
import 'controllers/personal_center_controller.dart';
import '../domain/personal_center_models.dart';
import 'personal_resource_list_page.dart';

class PersonalCenterPage extends StatelessWidget {
  const PersonalCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<PersonalCenterController>(
      create: (_) => PersonalCenterController(),
      child: const _PersonalCenterView(),
    );
  }
}

class _PersonalCenterView extends StatefulWidget {
  const _PersonalCenterView();

  @override
  State<_PersonalCenterView> createState() => _PersonalCenterViewState();
}

class _PersonalCenterViewState extends State<_PersonalCenterView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  BuildContext? navigatorContext;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PersonalCenterController>().load();
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    final controller = context.read<PersonalCenterController>();
    if (!_tabController.indexIsChanging) {
      if (_tabController.index == 0) {
        controller.load();
      } else if (_tabController.index == 1) {
        controller.load();
      } else if (_tabController.index == 2) {
        controller.loadQuizzes();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    navigatorContext = context;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('个人中心'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '额度'),
            Tab(text: '我的插件'),
            Tab(text: '我的题库'),
            Tab(text: '设置'),
          ],
        ),
      ),
      body: Consumer<PersonalCenterController>(
        builder: (context, controller, _) {
          if (controller.loading && controller.overview == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (controller.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    controller.error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => controller.load(),
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }
          return _buildBody(controller);
        },
      ),
    );
  }

  Widget _buildBody(PersonalCenterController controller) {
    return TabBarView(
      controller: _tabController,
      children: [
        _QuotaTab(
          overview: controller.overview,
          quotaSummary: controller.quotaSummary,
        ),
        _PluginsTab(plugins: controller.plugins),
        _QuizzesTab(
          quizPage: controller.quizPage,
          onRefresh: () => controller.loadQuizzes(),
        ),
        const _SettingsTab(),
      ],
    );
  }
}

class _QuotaTab extends StatelessWidget {
  const _QuotaTab({required this.overview, required this.quotaSummary});

  final PersonalOverview? overview;
  final PersonalQuotaSummary? quotaSummary;

  @override
  Widget build(BuildContext context) {
    if (overview == null) return const SizedBox();

    final quota = overview!.quota;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 额度卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.image, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(
                        '生图额度',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  _buildQuotaRow(context, '总可用', quota.remaining.toString()),
                  _buildQuotaRow(context, '已用今日', quota.usedToday.toString()),
                  _buildQuotaRow(context, '日限额', quota.dailyLimit.toString()),
                  if (quota.totalLimit != null)
                    _buildQuotaRow(context, '总限额', quota.totalLimit.toString()),
                  const Divider(height: 24),
                  LinearProgressIndicator(value: quota.progress),
                  const SizedBox(height: 8),
                  Text(
                    '使用进度 ${(quota.progress * 100).toStringAsFixed(1)}%',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 统计卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('今日统计', style: Theme.of(context).textTheme.titleMedium),
                  const Divider(height: 24),
                  _buildStatRow(
                    context,
                    '请求次数',
                    '${overview!.stats.todayRequests}',
                  ),
                  _buildStatRow(
                    context,
                    '成功次数',
                    '${overview!.stats.todaySuccess}',
                  ),
                  _buildStatRow(
                    context,
                    '消耗点数',
                    '${overview!.stats.todayCost}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 额度流水入口
          if (quotaSummary != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.history, color: Colors.blue),
                title: const Text('额度流水'),
                subtitle: Text('共 ${quotaSummary!.total} 条记录'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showTransactions(context),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuotaRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _showTransactions(BuildContext context) {
    final quotaSummary = context.read<PersonalCenterController>().quotaSummary;
    if (quotaSummary == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PersonalResourceListPage.quizzes(
          items: quotaSummary.transactions
              .map(
                (e) => PersonalQuizItem(
                  id: e['userId']?.toString() ?? '',
                  title: '${e['model'] ?? ''} · ${e['cost'] ?? 0} 点',
                  status: e['success'] == true ? 'approved' : 'rejected',
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _PluginsTab extends StatelessWidget {
  const _PluginsTab({required this.plugins});

  final List<Map<String, dynamic>> plugins;

  @override
  Widget build(BuildContext context) {
    if (plugins.isEmpty) {
      return const Center(child: Text('暂无插件'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: plugins.length,
      itemBuilder: (context, index) {
        final plugin = plugins[index];
        return Card(
          child: ListTile(
            title: Text(
              plugin['name']?.toString() ??
                  plugin['title']?.toString() ??
                  '未知插件',
            ),
            subtitle: Text(plugin['description']?.toString() ?? ''),
            trailing: Text(plugin['status']?.toString() ?? ''),
          ),
        );
      },
    );
  }
}

class _QuizzesTab extends StatelessWidget {
  const _QuizzesTab({required this.quizPage, required this.onRefresh});

  final PersonalQuizPage? quizPage;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    if (quizPage == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (quizPage!.questions.isEmpty) {
      return const Center(child: Text('暂无题库'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: quizPage!.questions.length,
      itemBuilder: (context, index) {
        final item = quizPage!.questions[index];
        return Card(
          child: ListTile(
            title: Text(
              item.title.length > 30
                  ? '${item.title.substring(0, 30)}...'
                  : item.title,
            ),
            subtitle: Text('${item.statusLabel} · ${item.category}'),
            trailing: Text(item.id.substring(0, 8)),
          ),
        );
      },
    );
  }
}

class _SettingsTab extends StatefulWidget {
  const _SettingsTab();

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  bool _clearing = false;
  bool _savingNickname = false;

  Future<void> _editNickname() async {
    final controller = context.read<PersonalCenterController>();
    final user = controller.session?.user;
    if (user == null) return;
    final field = TextEditingController(text: user.nickname);
    final nickname = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('编辑昵称'),
        content: TextField(
          controller: field,
          autofocus: true,
          maxLength: 32,
          decoration: const InputDecoration(labelText: '昵称'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, field.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    field.dispose();
    if (nickname == null || !mounted || nickname.trim() == user.nickname) {
      return;
    }
    setState(() => _savingNickname = true);
    try {
      await controller.updateNickname(nickname);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('昵称已更新')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('更新昵称失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _savingNickname = false);
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清除缓存'),
        content: const Text('仅清除图片和阅读器临时缓存，不会删除登录信息、离线书籍或题库数据。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      await PersonalCenterCacheService().clearRegenerableCaches();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('缓存已清除')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('清除缓存失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后仍会保留服务器地址，下次可重新登录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await BoxAccountStore().clearSession();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _showAbout() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    showAboutDialog(
      context: context,
      applicationName: 'Geek工具箱 Pro',
      applicationVersion: '${info.version} (${info.buildNumber})',
      applicationLegalese: '智能工具集，为极客而生。',
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<PersonalCenterController>().session;
    final user = session?.user;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text(
                user?.username.isNotEmpty == true
                    ? user!.username[0].toUpperCase()
                    : '?',
              ),
            ),
            title: Text(user?.nickname ?? user?.username ?? '未登录'),
            subtitle: Text(
              user == null
                  ? '请先登录账号'
                  : '${user.username} · ${user.role} · ${user.status}',
            ),
            trailing: user == null
                ? null
                : _savingNickname
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.edit_outlined),
            onTap: user == null || _savingNickname ? null : _editNickname,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: const Text('清除缓存'),
                subtitle: const Text('清除图片与阅读器临时缓存'),
                trailing: _clearing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: _clearing ? null : _clearCache,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('关于我们'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showAbout,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('退出登录', style: TextStyle(color: Colors.red)),
            onTap: _logout,
          ),
        ),
      ],
    );
  }
}
