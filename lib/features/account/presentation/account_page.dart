import 'package:flutter/material.dart';

import '../../../design_system/app_tokens.dart';
import '../../../design_system/widgets/app_cards.dart';
import '../../../design_system/widgets/app_page_scaffold.dart';
import '../../../app/app_routes.dart';
import '../data/account_client.dart';
import '../data/account_store.dart';
import '../domain/account_models.dart';
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
  final _usernameController = TextEditingController(text: 'admin');
  final _passwordController = TextEditingController();

  BoxAccountSession? _session;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSession() async {
    setState(() => _loading = true);
    try {
      final saved = await _store.loadSession();
      final savedServer = saved?.serverUrl ?? await _store.loadServerUrl();
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
      final refreshed = BoxAccountSession(
        serverUrl: saved.serverUrl,
        token: saved.token,
        user: user,
      );
      await _store.saveSession(refreshed);
      setState(() {
        _session = refreshed;
        _error = null;
      });
    } catch (error) {
      await _store.clearSession();
      setState(() {
        _session = null;
        _error = _messageOf(error);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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
      await _store.saveSession(session);
      _passwordController.clear();
      setState(() => _session = session);
      _showSnack('登录成功：${session.user.username}');
    } catch (error) {
      setState(() => _error = _messageOf(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
          _loading = false;
          _error = null;
        });
        _showSnack('已退出登录');
      }
    }
  }

  void _openAdmin() {
    Navigator.of(context).pushNamed(AppRoutes.accountAdmin);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _messageOf(Object error) {
    if (error is BoxAccountException) return error.message;
    return error.toString();
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
                    serverController: _serverController,
                    usernameController: _usernameController,
                    passwordController: _passwordController,
                    loading: _loading,
                    onLogin: _login,
                  )
                else
                  AccountStatusCard(
                    session: session,
                    loading: _loading,
                    onRefresh: _loadSession,
                    onLogout: _logout,
                    onAdminTap: _openAdmin,
                  ),
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
