import 'package:flutter/material.dart';

import '../../../../design_system/app_tokens.dart';
import '../../domain/admin_models.dart';

class AdminUserQuotaCard extends StatelessWidget {
  const AdminUserQuotaCard({
    super.key,
    required this.user,
    required this.loading,
    required this.onEditQuota,
    required this.onEditAccount,
  });

  final BoxAdminUserQuota user;
  final bool loading;
  final VoidCallback onEditQuota;
  final VoidCallback onEditAccount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: AppTokens.divider),
        boxShadow: AppTokens.shadowSm(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor:
                    (user.isAdmin ? AppTokens.warning : AppTokens.primaryBlue)
                        .withValues(alpha: 0.12),
                child: Icon(
                  user.isAdmin
                      ? Icons.admin_panel_settings_rounded
                      : Icons.person_rounded,
                  color: user.isAdmin
                      ? AppTokens.warning
                      : AppTokens.primaryBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTokens.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${user.isAdmin ? '管理员' : '普通用户'} · ${user.status} · ${user.id}',
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
              _RoleBadge(isAdmin: user.isAdmin),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricPill(
                label: '剩余额度',
                value: user.remaining.toString(),
                icon: Icons.bolt_rounded,
                color: AppTokens.success,
              ),
              _MetricPill(
                label: '今日已用',
                value: user.usedToday.toString(),
                icon: Icons.today_rounded,
                color: AppTokens.info,
              ),
              _MetricPill(
                label: '每日额度',
                value: user.dailyLimit.toString(),
                icon: Icons.calendar_month_rounded,
                color: AppTokens.primaryBlue,
              ),
              _MetricPill(
                label: '总额度',
                value: user.totalLimit.toString(),
                icon: Icons.all_inclusive_rounded,
                color: AppTokens.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: loading ? null : onEditQuota,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('调整额度'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: loading ? null : onEditAccount,
                  icon: const Icon(Icons.manage_accounts_rounded, size: 18),
                  label: const Text('账号设置'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AdminEmptyCard extends StatelessWidget {
  const AdminEmptyCard({super.key, required this.message, required this.icon});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: AppTokens.divider),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppTokens.textSecondary, size: 34),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTokens.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class AdminErrorBanner extends StatelessWidget {
  const AdminErrorBanner({super.key, required this.message});

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

class QuotaEditSheet extends StatefulWidget {
  const QuotaEditSheet({super.key, required this.user, required this.onSave});

  final BoxAdminUserQuota user;
  final Future<void> Function(int dailyLimit, int remaining) onSave;

  @override
  State<QuotaEditSheet> createState() => _QuotaEditSheetState();
}

class _QuotaEditSheetState extends State<QuotaEditSheet> {
  late final TextEditingController _dailyController;
  late final TextEditingController _remainingController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _dailyController = TextEditingController(
      text: widget.user.dailyLimit.toString(),
    );
    _remainingController = TextEditingController(
      text: widget.user.remaining.toString(),
    );
  }

  @override
  void dispose() {
    _dailyController.dispose();
    _remainingController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final daily = int.tryParse(_dailyController.text.trim());
    final remaining = int.tryParse(_remainingController.text.trim());
    if (daily == null || daily < 0 || remaining == null || remaining < 0) {
      setState(() => _error = '额度必须是大于等于 0 的整数。');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(daily, remaining);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '调整 ${widget.user.username} 额度',
              style: const TextStyle(
                color: AppTokens.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dailyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '每日额度 dailyLimit',
                prefixIcon: Icon(Icons.calendar_month_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _remainingController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '剩余额度 remaining',
                prefixIcon: Icon(Icons.bolt_rounded),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: AppTokens.danger, height: 1.4),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded, size: 18),
                label: Text(_saving ? '保存中' : '保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CreateAccountSheet extends StatefulWidget {
  const CreateAccountSheet({super.key, required this.onSave});

  final Future<void> Function(
    String username,
    String password,
    String role,
    int dailyLimit,
    int remaining,
  )
  onSave;

  @override
  State<CreateAccountSheet> createState() => _CreateAccountSheetState();
}

class _CreateAccountSheetState extends State<CreateAccountSheet> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _dailyController = TextEditingController(text: '20');
  final _remainingController = TextEditingController(text: '20');
  String _role = 'user';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _dailyController.dispose();
    _remainingController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final daily = int.tryParse(_dailyController.text.trim());
    final remaining = int.tryParse(_remainingController.text.trim());
    if (username.isEmpty) {
      setState(() => _error = '用户名不能为空。');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = '初始密码至少 6 位。');
      return;
    }
    if (daily == null || daily < 0 || remaining == null || remaining < 0) {
      setState(() => _error = '额度必须是大于等于 0 的整数。');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(username, password, _role, daily, remaining);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: '创建用户',
      children: [
        TextField(
          controller: _usernameController,
          decoration: const InputDecoration(
            labelText: '用户名',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '初始密码',
            helperText: '至少 6 位，不会明文保存',
            prefixIcon: Icon(Icons.password_rounded),
          ),
        ),
        const SizedBox(height: 12),
        _SegmentedRole(
          value: _role,
          onChanged: (value) => setState(() => _role = value),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _dailyController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '每日额度 dailyLimit'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _remainingController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '剩余额度 remaining'),
        ),
        _SheetError(message: _error),
        _SheetSaveButton(saving: _saving, onPressed: _save),
      ],
    );
  }
}

class AccountEditSheet extends StatefulWidget {
  const AccountEditSheet({super.key, required this.user, required this.onSave});

  final BoxAdminUserQuota user;
  final Future<void> Function(String role, String status, String password)
  onSave;

  @override
  State<AccountEditSheet> createState() => _AccountEditSheetState();
}

class _AccountEditSheetState extends State<AccountEditSheet> {
  final _passwordController = TextEditingController();
  late String _role;
  late String _status;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _role = widget.user.role == 'admin' ? 'admin' : 'user';
    _status = widget.user.status == 'disabled' ? 'disabled' : 'normal';
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final password = _passwordController.text;
    if (password.isNotEmpty && password.length < 6) {
      setState(() => _error = '新密码至少 6 位；留空则不修改密码。');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_role, _status, password);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: '账号设置：${widget.user.username}',
      children: [
        _SegmentedRole(
          value: _role,
          onChanged: (value) => setState(() => _role = value),
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'normal', label: Text('normal')),
            ButtonSegment(value: 'disabled', label: Text('disabled')),
          ],
          selected: {_status},
          onSelectionChanged: (value) => setState(() => _status = value.first),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '重置密码（可选）',
            helperText: '留空则不修改密码',
            prefixIcon: Icon(Icons.password_rounded),
          ),
        ),
        _SheetError(message: _error),
        _SheetSaveButton(saving: _saving, onPressed: _save),
      ],
    );
  }
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppTokens.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentedRole extends StatelessWidget {
  const _SegmentedRole({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'user', label: Text('user')),
        ButtonSegment(value: 'admin', label: Text('admin')),
      ],
      selected: {value},
      onSelectionChanged: (selected) => onChanged(selected.first),
    );
  }
}

class _SheetError extends StatelessWidget {
  const _SheetError({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        message!,
        style: const TextStyle(color: AppTokens.danger, height: 1.4),
      ),
    );
  }
}

class _SheetSaveButton extends StatelessWidget {
  const _SheetSaveButton({required this.saving, required this.onPressed});

  final bool saving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: saving ? null : onPressed,
          icon: saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_rounded, size: 18),
          label: Text(saving ? '保存中' : '保存'),
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (isAdmin ? AppTokens.warning : AppTokens.primaryBlue).withValues(
          alpha: 0.12,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isAdmin ? '管理员' : '用户',
        style: TextStyle(
          color: isAdmin ? AppTokens.warning : AppTokens.primaryBlue,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            '$label：$value',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
