import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/personal_center_cache_service.dart';
import '../data/account_store.dart';
import 'controllers/personal_center_controller.dart';
import '../domain/personal_center_models.dart';
import 'personal_quota_transactions_page.dart';
import 'widgets/personal_activity_chart.dart';
import 'widgets/personal_center_admin_entry.dart';
import '../../../app/app_routes.dart';
import '../../cloud_sync/domain/cloud_sync_models.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = context.read<PersonalCenterController>();
      controller.load();
      // 公告是公开接口，和登录态无关：首屏就拉一次，让红点尽快出现。
      controller.loadAnnouncements();
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  /// 按需加载：切到哪个 Tab 只拉该 Tab 的数据，且已加载过不重复请求。
  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final controller = context.read<PersonalCenterController>();
    switch (_tabController.index) {
      case 0:
        controller.loadQuotaTab();
      case 1:
        controller.loadPlugins();
      case 2:
        controller.loadQuizzes();
      case 3:
        break;
      case 4:
        controller.loadAnnouncements();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('个人中心'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: '额度'),
            const Tab(text: '我的插件'),
            const Tab(text: '我的题库'),
            const Tab(text: '设置'),
            Tab(
              child: Selector<PersonalCenterController, int>(
                selector: (_, c) => c.announcements.unreadCount,
                builder: (context, unread, _) =>
                    _TabLabelWithBadge(label: '公告', count: unread),
              ),
            ),
          ],
        ),
      ),
      body: Consumer<PersonalCenterController>(
        builder: (context, controller, _) {
          if (controller.loading && controller.overview == null) {
            return const Center(child: CircularProgressIndicator());
          }
          // 会话级错误只拦截需要登录的 Tab；公告是公开的，未登录也要能看，
          // 所以不再整屏 return，交给 _buildBody 按 Tab 决定。
          return Column(
            children: [
              if (controller.hasWarnings)
                MaterialBanner(
                  content: Text(controller.warningMessage),
                  leading: const Icon(Icons.info_outline),
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.secondaryContainer,
                  actions: [
                    TextButton(
                      onPressed: () => controller.load(force: true),
                      child: const Text('重试'),
                    ),
                    TextButton(
                      onPressed: controller.dismissWarnings,
                      child: const Text('忽略'),
                    ),
                  ],
                ),
              Expanded(child: _buildBody(controller)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(PersonalCenterController controller) {
    // 需要登录的 Tab 在会话失效时显示重试视图；公告 Tab 始终可用。
    Widget gated(Widget child) {
      final fatal = controller.fatalError;
      if (fatal == null) return child;
      return _FatalErrorView(
        message: fatal,
        onRetry: () => controller.load(force: true),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: [
        gated(_QuotaTab(controller: controller)),
        gated(_PluginsTab(controller: controller)),
        gated(_QuizzesTab(controller: controller)),
        gated(const _SettingsTab()),
        _AnnouncementsTab(controller: controller),
      ],
    );
  }
}

class _FatalErrorView extends StatelessWidget {
  const _FatalErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _QuotaTab extends StatelessWidget {
  const _QuotaTab({required this.controller});

  final PersonalCenterController controller;

  @override
  Widget build(BuildContext context) {
    final overview = controller.overview;
    final quotaSummary = controller.quotaSummary;
    return RefreshIndicator(
      onRefresh: () => controller.loadQuotaTab(force: true),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (overview == null)
            const _EmptySection(
              icon: Icons.speed_outlined,
              message: '额度数据暂不可用，下拉可重试',
            )
          else ...[
            _QuotaCard(quota: overview.quota),
            const SizedBox(height: 16),
            _TodayStatsCard(stats: overview.stats),
          ],
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '近 30 天生图活跃',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  PersonalActivityChart(days: controller.activity),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (quotaSummary != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.history, color: Colors.blue),
                title: const Text('额度流水'),
                subtitle: Text(
                  '共 ${quotaSummary.total} 条 · 消耗 ${quotaSummary.totalCost} 点',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PersonalQuotaTransactionsPage(
                      controller: controller,
                      initialSummary: quotaSummary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuotaCard extends StatelessWidget {
  const _QuotaCard({required this.quota});

  final PersonalQuota quota;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.image, color: Colors.blue),
                const SizedBox(width: 8),
                Text('生图额度', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const Divider(height: 24),
            _LabelValueRow(label: '总可用', value: '${quota.remaining}'),
            _LabelValueRow(label: '已用今日', value: '${quota.usedToday}'),
            _LabelValueRow(label: '日限额', value: '${quota.dailyLimit}'),
            if (quota.totalLimit != null)
              _LabelValueRow(label: '总限额', value: '${quota.totalLimit}'),
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
    );
  }
}

class _TodayStatsCard extends StatelessWidget {
  const _TodayStatsCard({required this.stats});

  final PersonalStats stats;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('今日统计', style: Theme.of(context).textTheme.titleMedium),
            const Divider(height: 24),
            _LabelValueRow(label: '请求次数', value: '${stats.todayRequests}'),
            _LabelValueRow(label: '成功次数', value: '${stats.todaySuccess}'),
            _LabelValueRow(label: '消耗点数', value: '${stats.todayCost}'),
          ],
        ),
      ),
    );
  }
}

class _LabelValueRow extends StatelessWidget {
  const _LabelValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
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
}

class _PluginsTab extends StatelessWidget {
  const _PluginsTab({required this.controller});

  final PersonalCenterController controller;

  @override
  Widget build(BuildContext context) {
    final page = controller.pluginPage;
    if (controller.pluginsLoading && page == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final items = page?.items ?? const <PersonalPluginItem>[];
    return RefreshIndicator(
      onRefresh: () =>
          controller.loadPlugins(status: controller.pluginStatus, force: true),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusFilters(
            value: controller.pluginStatus,
            statuses: const {
              '审核中': 'pending_review',
              '已发布': 'published',
              '已拒绝': 'rejected',
            },
            onChanged: (value) => controller.loadPlugins(status: value),
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            const _EmptySection(
              icon: Icons.extension_outlined,
              message: '还没有投稿过插件',
            )
          else ...[
            Text(
              '共 ${page!.total} 个投稿',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            ...items.map((item) => _PluginCard(item: item)),
            _LoadMoreButton(
              visible: page.hasMore,
              loading: controller.pluginsLoadingMore,
              onPressed: controller.loadMorePlugins,
            ),
          ],
        ],
      ),
    );
  }
}

class _PluginCard extends StatelessWidget {
  const _PluginCard({required this.item});
  final PersonalPluginItem item;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showPluginDetail(context, item),
      child: ListTile(
        leading: const Icon(Icons.extension_outlined),
        title: Text(item.title.isEmpty ? '未命名插件' : item.title),
        subtitle: Text(
          [
            item.statusLabel,
            if (item.version.isNotEmpty) 'v${item.version}',
            if (item.subtitle.isNotEmpty) item.subtitle,
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    ),
  );

  void _showPluginDetail(BuildContext context, PersonalPluginItem item) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(item.title.isEmpty ? '插件详情' : item.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailLine('状态', item.statusLabel),
              if (item.version.isNotEmpty) _DetailLine('版本', item.version),
              if (item.subtitle.isNotEmpty) _DetailLine('说明', item.subtitle),
              if (item.tags.isNotEmpty) _DetailLine('标签', item.tags.join('、')),
              if (item.permissions.isNotEmpty)
                _DetailLine('申请权限', item.permissions.join('、')),
              if (item.reviewNote.isNotEmpty)
                _DetailLine('审核反馈', item.reviewNote),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _QuizzesTab extends StatelessWidget {
  const _QuizzesTab({required this.controller});
  final PersonalCenterController controller;

  @override
  Widget build(BuildContext context) {
    final quizPage = controller.quizPage;
    final stats = controller.overview?.stats;
    if (controller.quizLoading && quizPage == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final questions = quizPage?.questions ?? const <PersonalQuizItem>[];
    return RefreshIndicator(
      onRefresh: () =>
          controller.loadQuizzes(status: controller.quizStatus, force: true),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (stats != null) _QuizStatsCard(stats: stats),
          const SizedBox(height: 12),
          _StatusFilters(
            value: controller.quizStatus,
            statuses: const {
              '审核中': 'pending',
              '已合并': 'merged',
              '已发布': 'approved',
            },
            onChanged: (value) => controller.loadQuizzes(status: value),
          ),
          const SizedBox(height: 8),
          if (questions.isEmpty)
            const _EmptySection(icon: Icons.quiz_outlined, message: '还没有提交过题目')
          else ...[
            Text(
              '共 ${quizPage!.total} 道题目',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            ...questions.map((item) => _QuizCard(item: item)),
            _LoadMoreButton(
              visible: quizPage.hasMore,
              loading: controller.quizLoadingMore,
              onPressed: controller.loadMoreQuizzes,
            ),
          ],
        ],
      ),
    );
  }
}

class _QuizCard extends StatelessWidget {
  const _QuizCard({required this.item});
  final PersonalQuizItem item;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('题目审核详情'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailLine('状态', item.statusLabel),
                _DetailLine('题干', item.title.isEmpty ? '未命名题目' : item.title),
                if (item.category.isNotEmpty) _DetailLine('分类', item.category),
                if (item.reviewNote.isNotEmpty)
                  _DetailLine('审核反馈', item.reviewNote),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
      child: ListTile(
        leading: const Icon(Icons.quiz_outlined),
        title: Text(
          item.title.isEmpty ? '未命名题目' : item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          item.category.isEmpty
              ? item.statusLabel
              : '${item.statusLabel} · ${item.category}',
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    ),
  );
}

class _StatusFilters extends StatelessWidget {
  const _StatusFilters({
    required this.value,
    required this.statuses,
    required this.onChanged,
  });
  final String? value;
  final Map<String, String> statuses;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        ChoiceChip(
          label: const Text('全部'),
          selected: value == null,
          onSelected: (_) => onChanged(null),
        ),
        const SizedBox(width: 8),
        ...statuses.entries.expand(
          (entry) => [
            ChoiceChip(
              label: Text(entry.key),
              selected: value == entry.value,
              onSelected: (_) => onChanged(entry.value),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ],
    ),
  );
}

class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({
    required this.visible,
    required this.loading,
    required this.onPressed,
  });
  final bool visible;
  final bool loading;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: loading
            ? const CircularProgressIndicator()
            : OutlinedButton(onPressed: onPressed, child: const Text('加载更多')),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text('$label：$value'),
  );
}

class _QuizStatsCard extends StatelessWidget {
  const _QuizStatsCard({required this.stats});

  final PersonalStats stats;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('我的贡献', style: Theme.of(context).textTheme.titleMedium),
            const Divider(height: 20),
            Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                _StatChip(label: '累计提交', value: stats.mySubmissions),
                _StatChip(label: '审核中', value: stats.myPendingSubmissions),
                _StatChip(label: '已通过', value: stats.myApprovedSubmissions),
                _StatChip(label: '已合并', value: stats.myMergedSubmissions),
                _StatChip(label: '题库已发布', value: stats.publishedQuestions),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(icon, size: 40, color: Theme.of(context).disabledColor),
          const SizedBox(height: 12),
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
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

  @override
  Widget build(BuildContext context) {
    // watch：昵称更新后由控制器 notifyListeners 驱动重建，不依赖本地 setState。
    final session = context.watch<PersonalCenterController>().session;
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
            title: Text(
              user == null
                  ? '未登录'
                  : (user.nickname.isNotEmpty ? user.nickname : user.username),
            ),
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
        // B6：个人中心成为账号主页后，管理员的后台入口必须落在这里。
        // 组件内部按 role 判定可见性，非管理员渲染为空。
        PersonalCenterAdminEntry(
          user: user,
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.accountAdmin),
        ),
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

/// Tab 标签 + 未读红点。
class _TabLabelWithBadge extends StatelessWidget {
  const _TabLabelWithBadge({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return Text(label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(width: 6),
        Semantics(
          label: '$count 条未读公告',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.error,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              count > 99 ? '99+' : '$count',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                height: 1.4,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onError,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 公告 Tab：未读带红点，点开即标记已读，历史公告可回看。
class _AnnouncementsTab extends StatelessWidget {
  const _AnnouncementsTab({required this.controller});

  final PersonalCenterController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.announcements;
    if (controller.announcementsLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final items = state.sorted;
    return RefreshIndicator(
      onRefresh: () => controller.loadAnnouncements(force: true),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (controller.announcementsError != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.cloud_off_outlined),
                title: Text(controller.announcementsError!),
                trailing: TextButton(
                  onPressed: () => controller.loadAnnouncements(force: true),
                  child: const Text('重试'),
                ),
              ),
            )
          else if (state.fromCache && state.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '当前显示缓存内容，下拉可重新获取',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (items.isEmpty)
            const _EmptySection(icon: Icons.campaign_outlined, message: '暂无公告')
          else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    state.hasUnread
                        ? '${state.unreadCount} 条未读 / 共 ${items.length} 条'
                        : '共 ${items.length} 条公告',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (state.hasUnread)
                  TextButton(
                    onPressed: controller.markAllAnnouncementsRead,
                    child: const Text('全部标记已读'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            ...items.map(
              (item) => _AnnouncementCard(
                item: item,
                read: state.isRead(item.id),
                onOpen: () => _open(context, item),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _open(BuildContext context, AnnouncementEntry item) {
    controller.markAnnouncementRead(item.id);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(item.title.isEmpty ? '公告' : item.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatTime(item.publishedAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Text(item.body.isEmpty ? '（无正文）' : item.body),
              if (item.linkUrl.isNotEmpty) ...[
                const SizedBox(height: 12),
                SelectableText(
                  item.linkUrl,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({
    required this.item,
    required this.read,
    required this.onOpen,
  });

  final AnnouncementEntry item;
  final bool read;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (item.level) {
      'warning' => (Icons.warning_amber_outlined, scheme.error),
      'notice' => (Icons.campaign_outlined, scheme.primary),
      _ => (Icons.info_outline, scheme.onSurfaceVariant),
    };
    return Card(
      child: ListTile(
        onTap: onOpen,
        leading: Icon(icon, color: color),
        title: Row(
          children: [
            if (item.pinned)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.push_pin, size: 14, color: scheme.primary),
              ),
            Expanded(
              child: Text(
                item.title.isEmpty ? '未命名公告' : item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: read ? FontWeight.normal : FontWeight.bold,
                ),
              ),
            ),
            if (!read)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(left: 6),
                decoration: BoxDecoration(
                  color: scheme.error,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
        subtitle: Text(
          '${_formatTime(item.publishedAt)}\n${item.body}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
