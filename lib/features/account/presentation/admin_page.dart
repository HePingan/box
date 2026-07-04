import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/app_tokens.dart';
import '../../../design_system/widgets/app_back_button.dart';
import '../../../design_system/widgets/app_cards.dart';
import '../../../design_system/widgets/app_page_scaffold.dart';
import '../data/account_store.dart';
import '../data/admin_client.dart';
import '../domain/account_models.dart';
import '../domain/admin_models.dart';
import '../domain/usage_models.dart';
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
  BoxAdminProviderConfig? _provider;
  BoxAdminProviderTestResult? _providerTestResult;
  BoxUsageSummary? _usageSummary;
  List<BoxAdminUserQuota> _users = const [];
  List<BoxAdminUsageRecord> _usage = const [];
  bool _loading = false;
  bool _testingProvider = false;
  bool _exportingUsage = false;
  String? _usageUserId;
  bool? _usageSuccess;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await _store.loadSession();
      if (session == null || !session.user.isAdmin) {
        _setEmptyState(session);
        return;
      }
      final results = await Future.wait([
        _client.fetchProvider(
          serverUrl: session.serverUrl,
          token: session.token,
        ),
        _client.fetchUsers(serverUrl: session.serverUrl, token: session.token),
        _client.fetchUsageSummary(
          serverUrl: session.serverUrl,
          token: session.token,
        ),
        _client.fetchUsage(
          serverUrl: session.serverUrl,
          token: session.token,
          userId: _usageUserId,
          success: _usageSuccess,
          limit: 50,
        ),
      ]);
      setState(() {
        _session = session;
        _provider = results[0] as BoxAdminProviderConfig;
        _providerTestResult = null;
        _users = results[1] as List<BoxAdminUserQuota>;
        _usageSummary = results[2] as BoxUsageSummary;
        _usage = results[3] as List<BoxAdminUsageRecord>;
      });
    } catch (error) {
      setState(() => _error = _messageOf(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setEmptyState(BoxAccountSession? session) {
    setState(() {
      _session = session;
      _users = const [];
      _usage = const [];
      _usageSummary = null;
    });
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

  Future<void> _testProvider() async {
    final session = _session;
    if (session == null) return;
    setState(() => _testingProvider = true);
    try {
      final result = await _client.testProvider(
        serverUrl: session.serverUrl,
        token: session.token,
      );
      setState(() => _providerTestResult = result);
      _showSnack(result.ok ? 'Provider 连接正常' : result.message);
    } catch (error) {
      setState(
        () => _providerTestResult = BoxAdminProviderTestResult(
          ok: false,
          statusCode: null,
          baseUrl: _provider?.baseUrl ?? '',
          hasApiKey: _provider?.hasApiKey ?? false,
          modelCount: 0,
          modelsPreview: const [],
          message: _messageOf(error),
        ),
      );
    } finally {
      if (mounted) setState(() => _testingProvider = false);
    }
  }

  Future<void> _updateProvider(
    String baseUrl,
    String apiKey,
    List<String> allowedModels,
    bool clearApiKey,
  ) async {
    final session = _session;
    if (session == null) return;
    final updated = await _client.updateProvider(
      serverUrl: session.serverUrl,
      token: session.token,
      baseUrl: baseUrl,
      apiKey: apiKey,
      allowedModels: allowedModels,
      clearApiKey: clearApiKey,
    );
    setState(() {
      _provider = updated;
      _providerTestResult = null;
    });
    _showSnack('已保存上游 Provider 配置');
  }

  Future<void> _createAccount(
    String username,
    String password,
    String role,
    int dailyLimit,
    int remaining,
  ) async {
    final session = _session;
    if (session == null) return;
    final created = await _client.createAccount(
      serverUrl: session.serverUrl,
      token: session.token,
      username: username,
      password: password,
      role: role,
      dailyLimit: dailyLimit,
      remaining: remaining,
    );
    setState(() {
      _users = [..._users, created]
        ..sort((a, b) => a.username.compareTo(b.username));
    });
    _showSnack('已创建用户 ${created.username}');
  }

  Future<void> _updateAccount(
    BoxAdminUserQuota user,
    String role,
    String status,
    String password,
  ) async {
    final session = _session;
    if (session == null) return;
    final updated = await _client.updateAccount(
      serverUrl: session.serverUrl,
      token: session.token,
      user: user,
      role: role,
      status: status,
      password: password.trim().isEmpty ? null : password.trim(),
    );
    setState(() {
      _users = _users
          .map((item) => item.id == updated.id ? updated : item)
          .toList(growable: false);
    });
    _showSnack('已更新 ${updated.username} 的账号设置');
  }

  Future<void> _setAccountStatus(BoxAdminUserQuota user, String status) async {
    final session = _session;
    if (session == null) return;
    final updated = await _client.setAccountStatus(
      serverUrl: session.serverUrl,
      token: session.token,
      user: user,
      status: status,
    );
    setState(() {
      _users = _users
          .map((item) => item.id == updated.id ? updated : item)
          .toList(growable: false);
    });
    _showSnack(
      status == 'normal'
          ? '已恢复 ${updated.username}'
          : '已禁用 ${updated.username}',
    );
  }

  Future<void> _deleteAccount(BoxAdminUserQuota user) async {
    final session = _session;
    if (session == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除 ${user.username}？'),
        content: const Text('删除后该用户账号、额度和登录状态会被移除；历史用量记录会保留用于审计。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _client.deleteAccount(
      serverUrl: session.serverUrl,
      token: session.token,
      user: user,
    );
    setState(() {
      _users = _users
          .where((item) => item.id != user.id)
          .toList(growable: false);
    });
    _showSnack('已删除 ${user.username}');
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

  void _openProviderSheet() {
    final provider = _provider;
    if (provider == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          ProviderConfigSheet(provider: provider, onSave: _updateProvider),
    );
  }

  void _openCreateSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CreateAccountSheet(onSave: _createAccount),
    );
  }

  void _openAccountSheet(BoxAdminUserQuota user) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AccountEditSheet(
        user: user,
        onSave: (role, status, password) =>
            _updateAccount(user, role, status, password),
      ),
    );
  }

  Future<void> _reloadUsage() async {
    final session = _session;
    if (session == null || !session.user.isAdmin) return;
    final usage = await _client.fetchUsage(
      serverUrl: session.serverUrl,
      token: session.token,
      userId: _usageUserId,
      success: _usageSuccess,
      limit: 50,
    );
    if (mounted) setState(() => _usage = usage);
  }

  Future<void> _setUsageFilters(String? userId, bool? success) async {
    setState(() {
      _usageUserId = userId;
      _usageSuccess = success;
    });
    await _reloadUsage();
  }

  Future<void> _exportUsageCsv() async {
    final session = _session;
    if (session == null || !session.user.isAdmin || _exportingUsage) return;
    setState(() => _exportingUsage = true);
    try {
      final csv = await _client.exportUsageCsv(
        serverUrl: session.serverUrl,
        token: session.token,
        userId: _usageUserId,
        success: _usageSuccess,
        limit: 200,
      );
      await Clipboard.setData(ClipboardData(text: csv));
      _showSnack('已复制 CSV，可粘贴到表格或文档');
    } catch (error) {
      _showSnack(_messageOf(error));
    } finally {
      if (mounted) setState(() => _exportingUsage = false);
    }
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

  Widget _emptyCard(IconData icon, String message) {
    return AdminEmptyCard(icon: icon, message: message);
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
            leading: AppBackButton(onPressed: () => Navigator.pop(context)),
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
                if (session?.user.isAdmin == true) ...[
                  AdminProviderCard(
                    provider: _provider,
                    testResult: _providerTestResult,
                    loading: _loading,
                    testing: _testingProvider,
                    onConfigure: _openProviderSheet,
                    onTest: _testProvider,
                  ),
                  const SizedBox(height: 12),
                  AdminUsageSummaryCard(
                    summary: _usageSummary,
                    loading: _loading,
                  ),
                  const SizedBox(height: 12),
                  AdminUsageCard(
                    records: _usage,
                    users: _users,
                    selectedUserId: _usageUserId,
                    selectedSuccess: _usageSuccess,
                    loading: _loading,
                    exporting: _exportingUsage,
                    onFilterChanged: _setUsageFilters,
                    onExportCsv: _exportUsageCsv,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _openCreateSheet,
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('创建用户'),
                    ),
                  ),
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
                  _emptyCard(Icons.login_rounded, '请先回到账号中心，登录 Box 管理员账号。')
                else if (!session.user.isAdmin)
                  _emptyCard(Icons.lock_outline_rounded, '当前账号不是管理员，无法查看用户额度。')
                else if (_users.isEmpty)
                  _emptyCard(Icons.inbox_rounded, '暂无用户数据。')
                else
                  ..._users.expand(
                    (user) => [
                      AdminUserQuotaCard(
                        user: user,
                        loading: _loading,
                        onEditQuota: () => _openQuotaSheet(user),
                        onEditAccount: () => _openAccountSheet(user),
                        onToggleStatus: () => _setAccountStatus(
                          user,
                          user.status == 'disabled' ? 'normal' : 'disabled',
                        ),
                        onDelete: user.isAdmin
                            ? null
                            : () => _deleteAccount(user),
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
