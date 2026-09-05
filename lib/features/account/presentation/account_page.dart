import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../design_system/app_tokens.dart';
import '../../../design_system/widgets/app_back_button.dart';
import '../../../design_system/widgets/app_cards.dart';
import '../../../design_system/widgets/app_page_scaffold.dart';
import '../../../app/app_routes.dart';
import '../data/account_client.dart';
import '../data/account_store.dart';
import '../domain/account_models.dart';
import '../domain/personal_center_models.dart';
import '../domain/usage_models.dart';
import 'widgets/account_widgets.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _client = BoxAccountClient();
  final _store = BoxAccountStore();
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _registerUsernameController = TextEditingController();
  final _registerPasswordController = TextEditingController();
  final _registerConfirmController = TextEditingController();

  BoxAccountSession? _session;
  bool _loading = false;
  List<BoxUsageRecord> _usage = const [];
  String? _error;

  /// 侧数据各自的错误，与会话级 `_error` 分开：它们失败不影响登录态。
  String? _usageError;
  PersonalQuota? _quota;
  String? _quotaError;

  @override
  void initState() {
    super.initState();
    _serverController.text = BoxAccountDefaults.serverUrl;
    _serverController.addListener(_handleServerInputChanged);
    _loadSession();
  }

  @override
  void dispose() {
    _serverController.removeListener(_handleServerInputChanged);
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _registerUsernameController.dispose();
    _registerPasswordController.dispose();
    _registerConfirmController.dispose();
    super.dispose();
  }

  void _handleServerInputChanged() {
    if (!mounted || _error != '请先填写服务器地址。') return;
    if (_serverController.text.trim().isEmpty) return;
    setState(() => _error = null);
  }

  Future<void> _loadSession() async {
    setState(() => _loading = true);
    try {
      final saved = await _store.loadSession();
      if (!mounted) return;
      final savedServer = saved?.serverUrl ?? await _store.loadServerUrl();
      if (!mounted) return;
      _serverController.text = savedServer;
      if (saved == null) {
        setState(() {
          _session = null;
          _error = null;
        });
        return;
      }
      final user = await _client.me(
        serverUrl: saved.serverUrl,
        token: saved.token,
      );
      if (!mounted) return;
      final refreshed = BoxAccountSession(
        serverUrl: saved.serverUrl,
        token: saved.token,
        user: user,
      );
      await _store.saveSession(refreshed);
      if (!mounted) return;
      setState(() {
        _session = refreshed;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      // 只有会话本身失效（401/403）才清登录态。网络抖动、后端 5xx、超时
      // 都不该把用户踢下线——否则用户得重新输一遍密码。
      if (_isSessionInvalid(error)) {
        await _store.clearSession();
        if (!mounted) return;
        setState(() {
          _session = null;
          _error = _messageOf(error);
        });
      } else {
        setState(() => _error = _messageOf(error));
      }
      return;
    } finally {
      if (mounted) setState(() => _loading = false);
    }

    // 额度与生图记录都是侧数据：任一挂了只影响自己那块，不影响登录态。
    // 并行发出，互不阻塞。
    await Future.wait([_loadQuota(), _loadUsage()]);
  }

  /// 我的额度。失败只记 `_quotaError`，绝不动 `_session`。
  Future<void> _loadQuota() async {
    final session = _session;
    if (session == null) return;
    try {
      final quota = await _client.fetchMyQuota(
        serverUrl: session.serverUrl,
        token: session.token,
      );
      if (!mounted) return;
      setState(() {
        _quota = quota;
        _quotaError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _quota = null;
        _quotaError = _messageOf(error);
      });
    }
  }

  /// 侧数据加载。失败只记 `_usageError`，绝不动 `_session`。
  Future<void> _loadUsage() async {
    final session = _session;
    if (session == null) return;
    try {
      final usage = await _client.fetchMyUsage(
        serverUrl: session.serverUrl,
        token: session.token,
        limit: 20,
      );
      if (!mounted) return;
      setState(() {
        _usage = usage;
        _usageError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _usage = const [];
        _usageError = _messageOf(error);
      });
    }
  }

  /// 会话是否已失效。只认 401/403，其余一律视为「暂时取不到」。
  static bool _isSessionInvalid(Object error) =>
      error is BoxAccountException &&
      (error.statusCode == 401 || error.statusCode == 403);

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await _client.login(
        serverUrl: _serverController.text,
        username: _usernameController.text,
        password: _passwordController.text,
      );
      await _completeAuth(
        session,
        successMessage: '登录成功：${session.user.username}',
      );
    } catch (error) {
      // 用户可能在请求在途时就退出页面，此处不守 mounted 会抛
      // "setState called after dispose"。
      if (!mounted) return;
      setState(() => _error = _messageOf(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    final password = _registerPasswordController.text;
    final confirm = _registerConfirmController.text;
    if (password != confirm) {
      setState(() => _error = '两次输入的密码不一致。');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _client.register(
        serverUrl: _serverController.text,
        username: _registerUsernameController.text,
        password: password,
      );
      final session = result.session;
      _usernameController.text = session.user.username;
      _registerPasswordController.clear();
      _registerConfirmController.clear();
      await _completeAuth(
        session,
        successMessage: '注册成功，已自动登录：${session.user.username}',
        registerResult: result,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _messageOf(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _completeAuth(
    BoxAccountSession session, {
    required String successMessage,
    BoxRegisterResult? registerResult,
  }) async {
    await _store.saveSession(session);
    _passwordController.clear();
    if (!mounted) return;
    // 先把登录态落地并提示成功：侧数据还没拉，但用户**已经**登录成功了。
    // 过去把 fetchMyUsage 放在这里 await，它一失败就抛回 _login 的 catch，
    // 用户会看到「登录失败」——而其实已经登上了。
    setState(() {
      _session = session;
      _usage = const [];
      _usageError = null;
      // 注册响应自带 quota，省一次请求。
      _quota = registerResult?.quota;
      _quotaError = null;
    });
    _showSnack(successMessage);
    await Future.wait([
      if (registerResult?.quota == null) _loadQuota(),
      _loadUsage(),
    ]);
  }

  Future<void> _logout() async {
    final session = _session;
    setState(() => _loading = true);
    try {
      if (session != null) {
        await _client.logout(
          serverUrl: session.serverUrl,
          token: session.token,
        );
      }
    } catch (_) {
      // 本地清理优先，服务端登出失败不阻塞退出。
    } finally {
      await _store.clearSession();
      if (mounted) {
        setState(() {
          _session = null;
          _usage = const [];
          _usageError = null;
          _quota = null;
          _quotaError = null;
          _loading = false;
          _error = null;
        });
        _showSnack('已退出登录');
      }
    }
  }

  Future<void> _resetServerUrl() async {
    _serverController.text = BoxAccountDefaults.serverUrl;
    await _store.saveServerUrl(BoxAccountDefaults.serverUrl);
    if (mounted) {
      setState(() => _error = null);
      _showSnack('已恢复默认服务器：${BoxAccountDefaults.serverUrl}');
    }
  }

  void _openAdmin() {
    Navigator.of(context).pushNamed(AppRoutes.accountAdmin);
  }

  Future<void> _openRegisterSheet() async {
    _registerUsernameController.text = _usernameController.text;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: AccountRegisterSheet(
            serverUrl: _serverController.text.trim().isEmpty
                ? BoxAccountDefaults.serverUrl
                : _serverController.text.trim(),
            usernameController: _registerUsernameController,
            passwordController: _registerPasswordController,
            confirmController: _registerConfirmController,
            loading: _loading,
            onRegister: () async {
              Navigator.of(sheetContext).pop();
              await _register();
            },
          ),
        );
      },
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _messageOf(Object error) {
    if (error is BoxAccountException) return error.message;
    // 非预期异常（SocketException / HandshakeException / TimeoutException 等）
    // 的 toString() 是给开发者看的，直接糊到界面上用户读不懂也不知道该干什么。
    if (error is SocketException) {
      return '连不上服务器，请检查网络或服务器地址。';
    }
    if (error is HandshakeException || error is TlsException) {
      return '与服务器建立安全连接失败，请确认服务器证书有效。';
    }
    if (error is TimeoutException) {
      return '服务器响应超时，请稍后重试。';
    }
    if (error is FormatException) {
      return '服务器返回内容无法解析，请确认服务器地址指向 Box 后端。';
    }
    return '操作失败，请稍后重试。';
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return AppPageScaffold(
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppTokens.background,
            surfaceTintColor: Colors.transparent,
            leading: AppBackButton(onPressed: () => Navigator.pop(context)),
            title: const Text('账号中心'),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            sliver: SliverList.list(
              children: [
                AppHeroCard(
                  title: 'Box 账号',
                  subtitle: session == null
                      ? '登录你的 Box 后端，后续平台额度和管理员后台都会使用同一个账号。'
                      : '已连接 ${session.serverUrl}，当前账号 ${session.user.username}。',
                  icon: Icons.account_circle_rounded,
                  badge: session?.user.isAdmin == true ? '管理员' : '账号中心',
                  metrics: [
                    Expanded(
                      child: AppMetricTile(
                        value: session?.user.role ?? '未登录',
                        label: '角色',
                        icon: Icons.verified_user_rounded,
                        glass: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppMetricTile(
                        value: session?.user.status ?? '离线',
                        label: '状态',
                        icon: Icons.cloud_done_rounded,
                        glass: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (_error != null) ...[
                  _ErrorBanner(message: _error!),
                  const SizedBox(height: 12),
                ],
                if (session == null)
                  AccountLoginCard(
                    key: const ValueKey('login_card'),
                    serverController: _serverController,
                    usernameController: _usernameController,
                    passwordController: _passwordController,
                    loading: _loading,
                    onLogin: _login,
                    onRegisterTap: _openRegisterSheet,
                    onResetServerUrl: _resetServerUrl,
                  )
                else
                  AccountStatusCard(
                    key: const ValueKey('status_card'),
                    session: session,
                    loading: _loading,
                    onRefresh: _loadSession,
                    onLogout: _logout,
                    onAdminTap: _openAdmin,
                    onPersonalCenterTap: () => Navigator.of(
                      context,
                    ).pushNamed(AppRoutes.personalCenter),
                  ),
                if (session != null) ...[
                  const SizedBox(height: 12),
                  AccountQuotaCard(
                    quota: _quota,
                    error: _quotaError,
                    onRetry: _loadQuota,
                  ),
                  const SizedBox(height: 12),
                  AccountUsageCard(
                    records: _usage,
                    loading: _loading,
                    error: _usageError,
                    onRetry: _loadUsage,
                  ),
                ],
                const SizedBox(height: 12),
                const AccountNoticeCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: AppTokens.danger.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppTokens.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppTokens.textPrimary,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
