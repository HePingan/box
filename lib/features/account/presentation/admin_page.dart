import 'package:flutter/material.dart';

import '../../../design_system/app_tokens.dart';
import '../../../design_system/widgets/app_cards.dart';
import '../../../design_system/widgets/app_page_scaffold.dart';
import '../data/account_store.dart';
import '../data/admin_client.dart';
import '../domain/account_models.dart';
import '../domain/admin_models.dart';
import 'widgets/admin_widgets.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final _store = BoxAccountStore();
  final _client = BoxAdminClient();

  BoxAccountSession? _session;
  List<BoxAdminUserQuota> _users = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await _store.loadSession();
      if (session == null) {
        setState(() {
          _session = null;
          _users = const [];
        });
        return;
      }
      if (!session.user.isAdmin) {
        setState(() {
          _session = session;
          _users = const [];
        });
        return;
      }
      final users = await _client.fetchUsers(
        serverUrl: session.serverUrl,
        token: session.token,
      );
      setState(() {
        _session = session;
        _users = users;
      });
    } catch (error) {
      setState(() => _error = _messageOf(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateQuota(
    BoxAdminUserQuota user,
    int dailyLimit,
    int remaining,
  ) async {
    final session = _session;
    if (session == null) return;
    final updated = await _client.updateQuota(
      serverUrl: session.serverUrl,
      token: session.token,
      user: user,
      dailyLimit: dailyLimit,
      remaining: remaining,
    );
    setState(() {
      _users = _users
          .map((item) => item.id == updated.id ? updated : item)
          .toList(growable: false);
    });
    _showSnack('已更新 ${updated.username} 的额度');
  }

  void _openQuotaSheet(BoxAdminUserQuota user) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => QuotaEditSheet(
        user: user,
        onSave: (dailyLimit, remaining) =>
            _updateQuota(user, dailyLimit, remaining),
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _messageOf(Object error) {
    if (error is BoxAdminException) return error.message;
    return error.toString();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final userCount = _users.length;
    final totalRemaining = _users.fold<int>(
      0,
      (sum, item) => sum + item.remaining,
    );
    return AppPageScaffold(
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppTokens.background,
            surfaceTintColor: Colors.transparent,
            title: const Text('Box 管理后台'),
            actions: [
              IconButton(
                tooltip: '刷新',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            sliver: SliverList.list(
              children: [
                AppHeroCard(
                  title: '用户额度管理',
                  subtitle: session == null
                      ? '请先登录 Box 管理员账号。'
                      : session.user.isAdmin
                      ? '当前服务器 ${session.serverUrl}，可查看并调整用户平台额度。'
                      : '当前账号 ${session.user.username} 不是管理员，无法进入后台。',
                  icon: Icons.admin_panel_settings_rounded,
                  badge: session?.user.isAdmin == true ? '管理员后台' : '需要管理员',
                  metrics: [
                    Expanded(
                      child: AppMetricTile(
                        value: userCount.toString(),
                        label: '用户',
                        icon: Icons.group_rounded,
                        glass: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppMetricTile(
                        value: totalRemaining.toString(),
                        label: '总剩余',
                        icon: Icons.bolt_rounded,
                        glass: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (_error != null) ...[
                  AdminErrorBanner(message: _error!),
                  const SizedBox(height: 12),
                ],
                if (_loading && _users.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (session == null)
                  const AdminEmptyCard(
                    icon: Icons.login_rounded,
                    message: '请先回到账号中心，登录 Box 管理员账号。',
                  )
                else if (!session.user.isAdmin)
                  const AdminEmptyCard(
                    icon: Icons.lock_outline_rounded,
                    message: '当前账号不是管理员，无法查看用户额度。',
                  )
                else if (_users.isEmpty)
                  const AdminEmptyCard(
                    icon: Icons.inbox_rounded,
                    message: '暂无用户数据。',
                  )
                else
                  ..._users.expand(
                    (user) => [
                      AdminUserQuotaCard(
                        user: user,
                        loading: _loading,
                        onEditQuota: () => _openQuotaSheet(user),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
