import 'package:flutter/material.dart';

import '../../../../design_system/app_tokens.dart';
import '../../domain/admin_models.dart';
import '../../domain/usage_models.dart';
part 'admin_widgets_sheets.part.dart';

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
    required this.onToggleStatus,
    required this.onDelete,
  });

  final BoxAdminUserQuota user;
  final bool loading;
  final VoidCallback onEditQuota;
  final VoidCallback onEditAccount;
  final VoidCallback onToggleStatus;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final disabled = user.status == 'disabled';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: disabled ? const Color(0xFFF8FAFC) : Colors.white,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(
          color: disabled
              ? AppTokens.warning.withValues(alpha: 0.35)
              : AppTokens.divider,
        ),
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
              if (disabled) ...[const SizedBox(width: 8), const _StatusBadge()],
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
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: loading ? null : onEditQuota,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('调整额度'),
              ),
              OutlinedButton.icon(
                onPressed: loading ? null : onEditAccount,
                icon: const Icon(Icons.manage_accounts_rounded, size: 18),
                label: const Text('账号设置'),
              ),
              OutlinedButton.icon(
                onPressed: loading ? null : onToggleStatus,
                icon: Icon(
                  disabled ? Icons.restart_alt_rounded : Icons.block_rounded,
                  size: 18,
                ),
                label: Text(disabled ? '恢复' : '禁用'),
              ),
              OutlinedButton.icon(
                onPressed: loading ? null : onDelete,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('删除'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTokens.danger,
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
