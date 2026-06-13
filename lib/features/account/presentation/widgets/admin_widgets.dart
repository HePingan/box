import 'package:flutter/material.dart';

import '../../../../design_system/app_tokens.dart';
import '../../domain/admin_models.dart';

class AdminUserQuotaCard extends StatelessWidget {
  const AdminUserQuotaCard({
    super.key,
    required this.user,
    required this.loading,
    required this.onEditQuota,
  });

  final BoxAdminUserQuota user;
  final bool loading;
  final VoidCallback onEditQuota;

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
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: loading ? null : onEditQuota,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('调整额度'),
            ),
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
