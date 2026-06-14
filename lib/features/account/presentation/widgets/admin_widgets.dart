import 'package:flutter/material.dart';

import '../../../../design_system/app_tokens.dart';
import '../../domain/admin_models.dart';
import '../../domain/usage_models.dart';

class AdminProviderCard extends StatelessWidget {
  const AdminProviderCard({
    super.key,
    required this.provider,
    required this.testResult,
    required this.loading,
    required this.testing,
    required this.onConfigure,
    required this.onTest,
  });

  final BoxAdminProviderConfig? provider;
  final BoxAdminProviderTestResult? testResult;
  final bool loading;
  final bool testing;
  final VoidCallback onConfigure;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final item = provider;
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
              const CircleAvatar(
                backgroundColor: Color(0xFFEFF6FF),
                child: Icon(Icons.hub_rounded, color: AppTokens.primaryBlue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '上游 Provider',
                      style: TextStyle(
                        color: AppTokens.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item?.baseUrl.isNotEmpty == true
                          ? item!.baseUrl
                          : '未读取配置',
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
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricPill(
                label: 'API Key',
                value: item?.hasApiKey == true ? item!.apiKeyMask : '未配置',
                icon: Icons.key_rounded,
                color: item?.hasApiKey == true
                    ? AppTokens.success
                    : AppTokens.warning,
              ),
              _MetricPill(
                label: '模型数',
                value: (item?.allowedModels.length ?? 0).toString(),
                icon: Icons.auto_awesome_rounded,
                color: AppTokens.info,
              ),
            ],
          ),
          if (item?.allowedModels.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(
              item!.allowedModels.join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTokens.textSecondary),
            ),
          ],
          if (testResult != null) ...[
            const SizedBox(height: 12),
            _ProviderTestBanner(result: testResult!),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: loading || testing || item == null ? null : onTest,
                  icon: testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check_rounded, size: 18),
                  label: Text(testing ? '测试中' : '测试连接'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: loading || item == null ? null : onConfigure,
                  icon: const Icon(Icons.settings_rounded, size: 18),
                  label: const Text('配置上游'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime value) {
  if (value.millisecondsSinceEpoch == 0) return '--';
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

String _formatShortDate(DateTime value) {
  if (value.millisecondsSinceEpoch == 0) return '--';
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$month-$day';
}

class _ProviderTestBanner extends StatelessWidget {
  const _ProviderTestBanner({required this.result});

  final BoxAdminProviderTestResult result;

  @override
  Widget build(BuildContext context) {
    final color = result.ok ? AppTokens.success : AppTokens.warning;
    final subtitle = result.ok
        ? '${result.modelCount} 个模型${result.modelsPreview.isEmpty ? '' : ' · ${result.modelsPreview.take(3).join(', ')}'}'
        : result.message;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            result.ok ? Icons.check_circle_rounded : Icons.warning_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.ok ? 'Provider 连接正常' : 'Provider 连接异常',
                  style: const TextStyle(
                    color: AppTokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTokens.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AdminUsageSummaryCard extends StatelessWidget {
  const AdminUsageSummaryCard({
    super.key,
    required this.summary,
    required this.loading,
  });

  final BoxUsageSummary? summary;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final item = summary;
    final today = item?.today;
    final hasUsage = today != null && today.requests > 0;
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
              const CircleAvatar(
                backgroundColor: Color(0xFFFFF7ED),
                child: Icon(
                  Icons.query_stats_rounded,
                  color: AppTokens.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '用量概览',
                      style: TextStyle(
                        color: AppTokens.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      today == null
                          ? '读取今日和最近 7 天统计'
                          : '今日 ${_formatDate(today.date)}',
                      style: const TextStyle(
                        color: AppTokens.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (loading && item == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
            )
          else if (item == null || !hasUsage)
            const Text(
              '暂无用量统计。真实上游生图请求会出现在这里。',
              style: TextStyle(color: AppTokens.textSecondary, height: 1.4),
            )
          else ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetricPill(
                  label: '今日请求',
                  value: today.requests.toString(),
                  icon: Icons.send_rounded,
                  color: AppTokens.primaryBlue,
                ),
                _MetricPill(
                  label: '成功',
                  value: today.success.toString(),
                  icon: Icons.check_circle_rounded,
                  color: AppTokens.success,
                ),
                _MetricPill(
                  label: '失败',
                  value: today.failed.toString(),
                  icon: Icons.error_rounded,
                  color: AppTokens.warning,
                ),
                _MetricPill(
                  label: '消耗额度',
                  value: today.cost.toString(),
                  icon: Icons.toll_rounded,
                  color: AppTokens.info,
                ),
                _MetricPill(
                  label: '活跃用户',
                  value: today.activeUsers.toString(),
                  icon: Icons.groups_rounded,
                  color: AppTokens.violet,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '最近 7 天',
              style: TextStyle(
                color: AppTokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            ...item.last7Days.map(
              (day) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 54,
                      child: Text(
                        _formatShortDate(day.date),
                        style: const TextStyle(
                          color: AppTokens.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: today.requests == 0
                            ? 0
                            : (day.requests / today.requests).clamp(0.0, 1.0),
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(999),
                        backgroundColor: AppTokens.divider,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppTokens.primaryBlue,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${day.requests} 次 · ${day.cost} 点',
                      style: const TextStyle(
                        color: AppTokens.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (item.topUsersToday.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                '今日 Top 用户',
                style: TextStyle(
                  color: AppTokens.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              ...item.topUsersToday.map(
                (user) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          user.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppTokens.textPrimary),
                        ),
                      ),
                      Text(
                        '${user.requests} 次 · ${user.cost} 点',
                        style: const TextStyle(
                          color: AppTokens.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class AdminUsageCard extends StatelessWidget {
  const AdminUsageCard({
    super.key,
    required this.records,
    required this.users,
    required this.selectedUserId,
    required this.selectedSuccess,
    required this.loading,
    required this.exporting,
    required this.onFilterChanged,
    required this.onExportCsv,
  });

  final List<BoxAdminUsageRecord> records;
  final List<BoxAdminUserQuota> users;
  final String? selectedUserId;
  final bool? selectedSuccess;
  final bool loading;
  final bool exporting;
  final Future<void> Function(String? userId, bool? success) onFilterChanged;
  final Future<void> Function() onExportCsv;

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
              const CircleAvatar(
                backgroundColor: Color(0xFFF0FDF4),
                child: Icon(
                  Icons.receipt_long_rounded,
                  color: AppTokens.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '最近使用记录',
                      style: TextStyle(
                        color: AppTokens.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      records.isEmpty
                          ? '最近 200 条平台生图请求'
                          : '最近 ${records.length} 条',
                      style: const TextStyle(
                        color: AppTokens.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _UsageFilterBar(
            users: users,
            selectedUserId: selectedUserId,
            selectedSuccess: selectedSuccess,
            enabled: !loading && !exporting,
            exporting: exporting,
            onChanged: onFilterChanged,
            onExportCsv: onExportCsv,
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
            const _UsageEmptyState()
          else
            ...records
                .take(6)
                .map(
                  (record) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _UsageRecordTile(record: record),
                  ),
                ),
        ],
      ),
    );
  }
}

class _UsageFilterBar extends StatelessWidget {
  const _UsageFilterBar({
    required this.users,
    required this.selectedUserId,
    required this.selectedSuccess,
    required this.enabled,
    required this.exporting,
    required this.onChanged,
    required this.onExportCsv,
  });

  final List<BoxAdminUserQuota> users;
  final String? selectedUserId;
  final bool? selectedSuccess;
  final bool enabled;
  final bool exporting;
  final Future<void> Function(String? userId, bool? success) onChanged;
  final Future<void> Function() onExportCsv;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        DropdownMenu<String>(
          enabled: enabled,
          initialSelection: selectedUserId ?? '',
          width: 180,
          label: const Text('用户'),
          dropdownMenuEntries: [
            const DropdownMenuEntry(value: '', label: '全部用户'),
            ...users.map(
              (user) => DropdownMenuEntry(value: user.id, label: user.username),
            ),
          ],
          onSelected: (value) => onChanged(
            value == null || value.isEmpty ? null : value,
            selectedSuccess,
          ),
        ),
        DropdownMenu<String>(
          enabled: enabled,
          initialSelection: selectedSuccess == null
              ? ''
              : selectedSuccess == true
              ? 'true'
              : 'false',
          width: 150,
          label: const Text('状态'),
          dropdownMenuEntries: const [
            DropdownMenuEntry(value: '', label: '全部'),
            DropdownMenuEntry(value: 'true', label: '成功'),
            DropdownMenuEntry(value: 'false', label: '失败'),
          ],
          onSelected: (value) => onChanged(
            selectedUserId,
            value == null || value.isEmpty ? null : value == 'true',
          ),
        ),
        OutlinedButton.icon(
          onPressed: enabled ? onExportCsv : null,
          icon: exporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.copy_all_rounded),
          label: Text(exporting ? '导出中' : '复制 CSV'),
        ),
      ],
    );
  }
}

class _UsageEmptyState extends StatelessWidget {
  const _UsageEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTokens.background,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: const Text(
        '暂无使用记录。成功或失败的真实上游生图请求会显示在这里。',
        style: TextStyle(color: AppTokens.textSecondary, height: 1.4),
      ),
    );
  }
}

class _UsageRecordTile extends StatelessWidget {
  const _UsageRecordTile({required this.record});

  final BoxAdminUsageRecord record;

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
                  '${record.username} · ${record.model.isEmpty ? '未知模型' : record.model}',
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
                  _formatUsageTime(record.createdAt),
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

String _formatUsageTime(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

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

class ProviderConfigSheet extends StatefulWidget {
  const ProviderConfigSheet({
    super.key,
    required this.provider,
    required this.onSave,
  });

  final BoxAdminProviderConfig provider;
  final Future<void> Function(
    String baseUrl,
    String apiKey,
    List<String> allowedModels,
    bool clearApiKey,
  )
  onSave;

  @override
  State<ProviderConfigSheet> createState() => _ProviderConfigSheetState();
}

class _ProviderConfigSheetState extends State<ProviderConfigSheet> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelsController;
  bool _clearApiKey = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(text: widget.provider.baseUrl);
    _apiKeyController = TextEditingController();
    _modelsController = TextEditingController(
      text: widget.provider.allowedModels.join(', '),
    );
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final baseUrl = _baseUrlController.text.trim();
    final uri = Uri.tryParse(baseUrl);
    if (baseUrl.isEmpty ||
        uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      setState(() => _error = 'Base URL 必须是 http/https 地址。');
      return;
    }
    final models =
        _modelsController.text
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        baseUrl,
        _apiKeyController.text.trim(),
        models,
        _clearApiKey,
      );
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
      title: '配置上游 Provider',
      children: [
        TextField(
          controller: _baseUrlController,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Base URL',
            prefixIcon: Icon(Icons.link_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _apiKeyController,
          obscureText: true,
          enabled: !_clearApiKey,
          decoration: InputDecoration(
            labelText: 'API Key（留空则不修改）',
            helperText: widget.provider.hasApiKey
                ? '当前：${widget.provider.apiKeyMask}'
                : '当前未配置',
            prefixIcon: const Icon(Icons.key_rounded),
          ),
        ),
        CheckboxListTile(
          value: _clearApiKey,
          onChanged: (value) => setState(() => _clearApiKey = value ?? false),
          contentPadding: EdgeInsets.zero,
          title: const Text('清空 API Key'),
          subtitle: const Text('勾选后会清除后端保存的上游 Key'),
        ),
        TextField(
          controller: _modelsController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: '允许模型（逗号分隔）',
            helperText: '例如 gpt-image-1, dall-e-3',
            prefixIcon: Icon(Icons.auto_awesome_rounded),
          ),
        ),
        _SheetError(message: _error),
        _SheetSaveButton(saving: _saving, onPressed: _save),
      ],
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
