import 'package:flutter/material.dart';

import '../../../../design_system/app_tokens.dart';
import '../../domain/account_models.dart';

class AccountStatusCard extends StatelessWidget {
  const AccountStatusCard({
    super.key,
    required this.session,
    required this.loading,
    required this.onRefresh,
    required this.onLogout,
    required this.onAdminTap,
  });

  final BoxAccountSession session;
  final bool loading;
  final VoidCallback onRefresh;
  final VoidCallback onLogout;
  final VoidCallback onAdminTap;

  @override
  Widget build(BuildContext context) {
    final user = session.user;
    return _AccountCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppTokens.primaryBlue.withValues(alpha: 0.12),
                child: Icon(
                  user.isAdmin
                      ? Icons.admin_panel_settings_rounded
                      : Icons.person_rounded,
                  color: AppTokens.primaryBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.username,
                      style: const TextStyle(
                        color: AppTokens.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      session.serverUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTokens.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _RoleBadge(role: user.role),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _InfoChip(label: '账号 ID', value: user.id),
              _InfoChip(label: '状态', value: user.status),
              if (user.lastLoginAt != null)
                _InfoChip(label: '最近登录', value: _formatTime(user.lastLoginAt!)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: loading ? null : onRefresh,
                  icon: loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('刷新状态'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: loading ? null : onLogout,
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('退出登录'),
                ),
              ),
            ],
          ),
          if (user.isAdmin) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onAdminTap,
                icon: const Icon(Icons.dashboard_customize_rounded, size: 18),
                label: const Text('进入管理后台'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class AccountLoginCard extends StatelessWidget {
  const AccountLoginCard({
    super.key,
    required this.serverController,
    required this.usernameController,
    required this.passwordController,
    required this.loading,
    required this.onLogin,
  });

  final TextEditingController serverController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool loading;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return _AccountCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '登录 Box 后端',
            style: TextStyle(
              color: AppTokens.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '登录后可使用平台额度；管理员账号后续可进入统一管理后台。',
            style: TextStyle(color: AppTokens.textSecondary, height: 1.45),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: serverController,
            decoration: const InputDecoration(
              labelText: '服务器地址',
              hintText: 'https://your-domain.com 或 http://127.0.0.1:8788',
              prefixIcon: Icon(Icons.dns_rounded),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: usernameController,
            decoration: const InputDecoration(
              labelText: '用户名',
              prefixIcon: Icon(Icons.account_circle_rounded),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: passwordController,
            decoration: const InputDecoration(
              labelText: '密码',
              prefixIcon: Icon(Icons.lock_rounded),
            ),
            obscureText: true,
            onSubmitted: (_) => loading ? null : onLogin(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: loading ? null : onLogin,
              icon: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login_rounded, size: 18),
              label: Text(loading ? '登录中' : '登录'),
            ),
          ),
        ],
      ),
    );
  }
}

class AccountNoticeCard extends StatelessWidget {
  const AccountNoticeCard({super.key});

  @override
  Widget build(BuildContext context) {
    return _AccountCard(
      color: AppTokens.info.withValues(alpha: 0.08),
      borderColor: AppTokens.info.withValues(alpha: 0.20),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, color: AppTokens.info),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '账号中心只保存服务器地址、登录 token 和用户公开信息，不保存密码。管理员 API Key 只应保存在后端环境变量中。',
              style: TextStyle(color: AppTokens.textPrimary, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.child, this.color, this.borderColor});

  final Widget child;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: borderColor ?? AppTokens.divider),
        boxShadow: AppTokens.shadowSm(),
      ),
      child: child,
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final isAdmin = role == 'admin';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (isAdmin ? AppTokens.warning : AppTokens.primaryBlue).withValues(
          alpha: 0.12,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isAdmin ? '管理员' : '普通用户',
        style: TextStyle(
          color: isAdmin ? AppTokens.warning : AppTokens.primaryBlue,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Text(
        '$label：$value',
        style: const TextStyle(color: AppTokens.textSecondary, fontSize: 12),
      ),
    );
  }
}

String _formatTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}
