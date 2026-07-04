import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../account/data/account_store.dart';
import '../../../account/data/admin_client.dart';
import '../../../account/domain/admin_models.dart';
import '../../../account/domain/usage_models.dart';
import '../../../account/presentation/widgets/admin_widgets.dart';
import '../../../../design_system/app_tokens.dart';
import '../../domain/admin_resource.dart';
import '../../domain/admin_resource_provider.dart';

/// AI 生图工坊资源提供者
class ImageProviderResourceProvider implements ResourceProvider<ResourceData> {
  @override
  AdminResourceType get resourceType => AdminResourceType.imageProvider;

  @override
  Future<List<ResourceData>> fetchAll(String? serverUrl, String? token) async {
    // AI 生图不需要列表模式，用自定义页面
    return [];
  }

  @override
  Future<ResourceData> create(
    String? serverUrl,
    String? token,
    Map<String, dynamic> data,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<ResourceData> update(
    String? serverUrl,
    String? token,
    String id,
    Map<String, dynamic> data,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String? serverUrl, String? token, String id) {
    throw UnimplementedError();
  }

  @override
  Widget buildListPage({
    required BuildContext context,
    String? serverUrl,
    String? token,
  }) {
    return _ImageProviderTab(
      serverUrl: serverUrl ?? '',
      token: token ?? '',
    );
  }
}

/// AI 生图工坊管理 Tab
class _ImageProviderTab extends StatefulWidget {
  final String serverUrl;
  final String token;

  const _ImageProviderTab({
    required this.serverUrl,
    required this.token,
  });

  @override
  State<_ImageProviderTab> createState() => _ImageProviderTabState();
}

class _ImageProviderTabState extends State<_ImageProviderTab> {
  final _client = BoxAdminClient();

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
      final results = await Future.wait([
        _client.fetchProvider(
          serverUrl: widget.serverUrl,
          token: widget.token,
        ),
        _client.fetchUsers(
          serverUrl: widget.serverUrl,
          token: widget.token,
        ),
        _client.fetchUsageSummary(
          serverUrl: widget.serverUrl,
          token: widget.token,
        ),
        _client.fetchUsage(
          serverUrl: widget.serverUrl,
          token: widget.token,
          userId: _usageUserId,
          success: _usageSuccess,
          limit: 50,
        ),
      ]);
      setState(() {
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

  Future<void> _testProvider() async {
    setState(() => _testingProvider = true);
    try {
      final result = await _client.testProvider(
        serverUrl: widget.serverUrl,
        token: widget.token,
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
    final updated = await _client.updateProvider(
      serverUrl: widget.serverUrl,
      token: widget.token,
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

  Future<void> _updateQuota(
    BoxAdminUserQuota user,
    int dailyLimit,
    int remaining,
  ) async {
    final updated = await _client.updateQuota(
      serverUrl: widget.serverUrl,
      token: widget.token,
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

  Future<void> _createAccount(
    String username,
    String password,
    String role,
    int dailyLimit,
    int remaining,
  ) async {
    final created = await _client.createAccount(
      serverUrl: widget.serverUrl,
      token: widget.token,
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
    final updated = await _client.updateAccount(
      serverUrl: widget.serverUrl,
      token: widget.token,
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

  Future<void> _setAccountStatus(
    BoxAdminUserQuota user,
    String status,
  ) async {
    final updated = await _client.setAccountStatus(
      serverUrl: widget.serverUrl,
      token: widget.token,
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除 ${user.username}？'),
        content: const Text('删除后该用户账号、额度和登录状态会被移除；历史用量保留。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _client.deleteAccount(
      serverUrl: widget.serverUrl,
      token: widget.token,
      user: user,
    );
    setState(() => _users = _users.where((u) => u.id != user.id).toList(growable: false));
    _showSnack('已删除 ${user.username}');
  }

  Future<void> _reloadUsage() async {
    final usage = await _client.fetchUsage(
      serverUrl: widget.serverUrl,
      token: widget.token,
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
    if (_exportingUsage) return;
    setState(() => _exportingUsage = true);
    try {
      final csv = await _client.exportUsageCsv(
        serverUrl: widget.serverUrl,
        token: widget.token,
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _messageOf(Object error) {
    if (error is BoxAdminException) return error.message;
    return error.toString();
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('加载失败', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(_error!, style: const TextStyle(color: Colors.black54, fontSize: 13)),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final session = globalSessionNotifier.value;
    if (session == null || !session.user.isAdmin) {
      return _emptyCard(Icons.no_accounts_rounded, '需要管理员账号登录');
    }

    final userCount = _users.length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          // ── Provider 配置 ──
          AdminProviderCard(
            provider: _provider,
            testResult: _providerTestResult,
            loading: _loading,
            testing: _testingProvider,
            onConfigure: _openProviderSheet,
            onTest: _testProvider,
          ),
          const SizedBox(height: 16),

          // ── 用量总览 ──
          AdminUsageSummaryCard(
            summary: _usageSummary,
            loading: _loading,
          ),
          const SizedBox(height: 16),

          // ── 用户额度管理 ──
          _buildSectionHeader(
            '用户额度管理（$userCount）',
            trailing: TextButton.icon(
              onPressed: _openCreateSheet,
              icon: const Icon(Icons.person_add_rounded, size: 18),
              label: const Text('创建用户'),
            ),
          ),
          const SizedBox(height: 8),
          if (_users.isEmpty)
            _emptyCard(Icons.people_outline_rounded, '暂无用户')
          else
            ..._users.map(_buildUserCard),
          if (userCount > 5)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: TextButton.icon(
                  onPressed: _openCreateSheet,
                  icon: const Icon(Icons.person_add_rounded, size: 18),
                  label: const Text('创建新用户'),
                ),
              ),
            ),
          const SizedBox(height: 24),

          // ── 用量明细 ──
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
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {Widget? trailing}) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: AppTokens.textPrimary,
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }

  Widget _buildUserCard(BoxAdminUserQuota user) {
    return AdminUserQuotaCard(
      user: user,
      loading: _loading,
      onEditQuota: () => _openQuotaSheet(user),
      onEditAccount: () => _openAccountSheet(user),
      onToggleStatus: () =>
          _setAccountStatus(user, user.status == 'normal' ? 'disabled' : 'normal'),
      onDelete: () => _deleteAccount(user),
    );
  }

  Widget _emptyCard(IconData icon, String message) {
    return AdminEmptyCard(icon: icon, message: message);
  }
}


