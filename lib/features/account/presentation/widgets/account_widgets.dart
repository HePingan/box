import 'package:flutter/material.dart';

import '../../../../design_system/app_tokens.dart';
import '../../domain/account_models.dart';
import '../../domain/usage_models.dart';

class AccountStatusCard extends StatelessWidget {
  const AccountStatusCard({
    super.key,
    required this.session,
    required this.loading,
    required this.onRefresh,
    required this.onLogout,
    required this.onAdminTap,
    required this.onPersonalCenterTap,
  });

  final BoxAccountSession session;
  final bool loading;
  final VoidCallback onRefresh;
  final VoidCallback onLogout;
  final VoidCallback onAdminTap;
  final VoidCallback onPersonalCenterTap;

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
              const _InfoChip(label: '版本', value: 'HTTPS 域名版'),
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
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onPersonalCenterTap,
              icon: const Icon(Icons.person_outline_rounded, size: 18),
              label: const Text('进入个人中心'),
            ),
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
    required this.onRegisterTap,
    required this.onResetServerUrl,
  });

  final TextEditingController serverController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool loading;
  final VoidCallback onLogin;
  final VoidCallback onRegisterTap;
  final VoidCallback onResetServerUrl;

  @override
  Widget build(BuildContext context) {
    return _AccountCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '登录 Box 平台账号',
            style: TextStyle(
              color: AppTokens.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'HTTPS 域名版 · background.hpa888.top',
            style: TextStyle(
              color: AppTokens.primaryBlue,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '默认连接 HTTPS 官方服务器。注册、管理后台和图片代理预览已启用；没有账号可直接注册。',
            style: TextStyle(color: AppTokens.textSecondary, height: 1.45),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: serverController,
            decoration: const InputDecoration(
              labelText: '服务器地址',
              hintText: 'https://background.hpa888.top',
              prefixIcon: Icon(Icons.dns_rounded),
            ),
            keyboardType: TextInputType.url,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: loading ? null : onResetServerUrl,
              icon: const Icon(Icons.restore_rounded, size: 16),
              label: const Text('恢复默认 HTTPS 域名'),
            ),
          ),
          const SizedBox(height: 8),
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
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: loading ? null : onRegisterTap,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text('没有账号？立即注册'),
            ),
          ),
        ],
      ),
    );
  }
}

class AccountRegisterSheet extends StatelessWidget {
  const AccountRegisterSheet({
    super.key,
    required this.serverUrl,
    required this.usernameController,
    required this.passwordController,
    required this.confirmController,
    required this.loading,
    required this.onRegister,
  });

  final String serverUrl;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final TextEditingController confirmController;
  final bool loading;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.person_add_alt_1_rounded,
                color: AppTokens.primaryBlue,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '注册 Box 账号',
                  style: TextStyle(
                    color: AppTokens.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '服务器：$serverUrl',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTokens.textSecondary),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: usernameController,
            decoration: const InputDecoration(
              labelText: '用户名',
              hintText: '3-20 位字母、数字或下划线',
              prefixIcon: Icon(Icons.account_circle_rounded),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: passwordController,
            decoration: const InputDecoration(
              labelText: '密码',
              hintText: '至少 6 位',
              prefixIcon: Icon(Icons.lock_rounded),
            ),
            obscureText: true,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: confirmController,
            decoration: const InputDecoration(
              labelText: '确认密码',
              prefixIcon: Icon(Icons.lock_reset_rounded),
            ),
            obscureText: true,
            onSubmitted: (_) => loading ? null : onRegister(),
          ),
          const SizedBox(height: 14),
          const Text(
            '注册成功后会自动登录，并获得 5 点平台图片额度。管理员可在后台调整额度或禁用账号。',
            style: TextStyle(color: AppTokens.textSecondary, height: 1.45),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: loading ? null : onRegister,
              icon: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: Text(loading ? '注册中' : '注册并登录'),
            ),
          ),
        ],
      ),
    );
  }
}

class AccountUsageCard extends StatelessWidget {
  const AccountUsageCard({
    super.key,
    required this.records,
    required this.loading,
  });

  final List<BoxUsageRecord> records;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return _AccountCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_long_rounded,
                color: AppTokens.primaryBlue,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '我的最近生图记录',
                  style: TextStyle(
                    color: AppTokens.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                records.isEmpty ? '最近 20 条' : '${records.length} 条',
                style: const TextStyle(
                  color: AppTokens.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (loading && records.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
            )
          else if (records.isEmpty)
            const Text(
              '暂无使用记录。使用平台额度生图后会显示成功或失败记录。',
              style: TextStyle(color: AppTokens.textSecondary, height: 1.4),
            )
          else
            ...records
                .take(5)
                .map(
                  (record) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AccountUsageTile(record: record),
                  ),
                ),
        ],
      ),
    );
  }
}

class _AccountUsageTile extends StatelessWidget {
  const _AccountUsageTile({required this.record});

  final BoxUsageRecord record;

  @override
  Widget build(BuildContext context) {
    final color = record.success ? AppTokens.success : AppTokens.warning;
    final statusText = record.statusCode == null
        ? 'HTTP -'
        : 'HTTP ${record.statusCode}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            record.success
                ? Icons.check_circle_rounded
                : Icons.error_outline_rounded,
            color: color,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.model.isEmpty ? '未知模型' : record.model,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${record.cost} 点 · ${record.success ? '成功' : '失败'} · $statusText',
                  style: const TextStyle(
                    color: AppTokens.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _formatTime(record.createdAt),
                  style: const TextStyle(
                    color: AppTokens.textTertiary,
                    fontSize: 12,
                  ),
                ),
                if (!record.success && record.errorPreview.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    record.errorPreview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTokens.textSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
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
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
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
