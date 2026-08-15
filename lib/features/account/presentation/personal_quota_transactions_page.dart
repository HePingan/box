import 'package:flutter/material.dart';

import '../domain/personal_center_models.dart';
import 'controllers/personal_center_controller.dart';

/// 额度流水详情页。
///
/// 按服务端 usage 记录的真实字段渲染（时间 / 模型 / 消耗 / 成功状态），
/// 并使用服务端已支持的 `?success=` 过滤参数做筛选。
class PersonalQuotaTransactionsPage extends StatefulWidget {
  const PersonalQuotaTransactionsPage({
    super.key,
    required this.controller,
    this.initialSummary,
  });

  final PersonalCenterController controller;
  final PersonalQuotaSummary? initialSummary;

  @override
  State<PersonalQuotaTransactionsPage> createState() =>
      _PersonalQuotaTransactionsPageState();
}

class _PersonalQuotaTransactionsPageState
    extends State<PersonalQuotaTransactionsPage> {
  /// null = 全部，true = 仅成功，false = 仅失败。
  bool? _successFilter;
  PersonalQuotaSummary? _summary;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _summary = widget.initialSummary;
    if (_summary == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.controller.fetchTransactions(
        success: _successFilter,
      );
      if (!mounted) return;
      setState(() => _summary = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '加载流水失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _applyFilter(bool? value) async {
    if (_successFilter == value) return;
    setState(() => _successFilter = value);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return Scaffold(
      appBar: AppBar(title: const Text('额度流水')),
      body: Column(
        children: [
          _buildFilterBar(),
          if (summary != null) _buildSummaryStrip(context, summary),
          const Divider(height: 1),
          Expanded(child: _buildList(summary)),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('全部'),
            selected: _successFilter == null,
            onSelected: _loading ? null : (_) => _applyFilter(null),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('成功'),
            selected: _successFilter == true,
            onSelected: _loading ? null : (_) => _applyFilter(true),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('失败'),
            selected: _successFilter == false,
            onSelected: _loading ? null : (_) => _applyFilter(false),
          ),
          const Spacer(),
          if (_loading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryStrip(
    BuildContext context,
    PersonalQuotaSummary summary,
  ) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('共 ${summary.total} 条', style: style),
          Text('消耗 ${summary.totalCost} 点', style: style),
          Text(
            '成功 ${summary.totalSuccess} · 失败 ${summary.totalFailed}',
            style: style,
          ),
        ],
      ),
    );
  }

  Widget _buildList(PersonalQuotaSummary? summary) {
    if (_error != null) {
      return _CenteredMessage(
        icon: Icons.error_outline,
        color: Colors.red,
        message: _error!,
        actionLabel: '重试',
        onAction: _reload,
      );
    }
    if (summary == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (summary.transactions.isEmpty) {
      return const _CenteredMessage(
        icon: Icons.receipt_long_outlined,
        message: '暂无流水记录',
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: summary.transactions.length + (summary.truncated ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index >= summary.transactions.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  '仅显示最近 ${summary.returned} 条，共 ${summary.total} 条',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            );
          }
          return _TransactionTile(record: summary.transactions[index]);
        },
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.record});

  final PersonalUsageRecord record;

  @override
  Widget build(BuildContext context) {
    final success = record.success;
    final color = success ? Colors.green : Colors.red;
    final subtitleParts = <String>[record.timeLabel];
    if (record.statusCode != null) {
      subtitleParts.add('HTTP ${record.statusCode}');
    }
    if (!success && record.errorPreview.isNotEmpty) {
      subtitleParts.add(record.errorPreview);
    }
    return Card(
      child: ListTile(
        leading: Icon(
          success ? Icons.check_circle_outline : Icons.error_outline,
          color: color,
        ),
        title: Text(record.modelLabel),
        subtitle: Text(subtitleParts.join(' · ')),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '-${record.cost}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text('点', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.message,
    this.color,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final Color? color;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 44, color: color ?? Theme.of(context).disabledColor),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: color),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
