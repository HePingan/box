import 'package:flutter/material.dart';

import '../../../core/novel_source_capability.dart';
import '../../../core/novel_source_capability_detector.dart';
import '../../../core/source_health_service.dart';
import '../book_source_manager.dart';
import '../book_source_model.dart';

import '../../../../design_system/app_tokens.dart';

Color bookSourceReportColor(NovelSourceCapabilityReport report) {
  if (report.isUsableForRead) return Colors.green;
  if (report.isPartiallySupported) return Colors.orange;
  return Colors.redAccent;
}

class BookSourceSimpleChip extends StatelessWidget {
  const BookSourceSimpleChip({
    super.key,
    required this.text,
    required this.color,
    this.backgroundColor,
  });

  final String text;
  final Color color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor ?? color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class BookSourceStatusChips extends StatelessWidget {
  const BookSourceStatusChips({
    super.key,
    required this.source,
    required this.manager,
  });

  final BookSourceModel source;
  final BookSourceManager manager;

  @override
  Widget build(BuildContext context) {
    final report = NovelSourceCapabilityDetector.detect(source.toJson());
    final chips = <Widget>[];

    if (manager.currentSourceId == source.id) {
      chips.add(
        BookSourceSimpleChip(
          text: '当前使用',
          color: Colors.deepOrange,
          backgroundColor: Colors.orange.withValues(alpha: 0.12),
        ),
      );
    }

    chips.add(
      BookSourceSimpleChip(
        text: source.enabled ? '已启用' : '未启用',
        color: source.enabled ? Colors.green : Colors.grey,
      ),
    );

    if (source.exploreUrl.isNotEmpty) {
      chips.add(
        BookSourceSimpleChip(
          text: '支持发现页',
          color: Colors.blue,
          backgroundColor: Colors.blue.withValues(alpha: 0.10),
        ),
      );
    }

    final reportColor = bookSourceReportColor(report);
    chips.add(
      BookSourceSimpleChip(
        text: report.statusLabel,
        color: reportColor,
        backgroundColor: reportColor.withValues(alpha: 0.10),
      ),
    );

    chips.add(
      BookSourceSimpleChip(
        text: report.adapterLabel,
        color: Colors.indigo,
        backgroundColor: Colors.indigo.withValues(alpha: 0.10),
      ),
    );

    if (report.warnings.isNotEmpty) {
      chips.add(
        BookSourceSimpleChip(
          text: '警告 ${report.warnings.length}',
          color: Colors.orange,
          backgroundColor: Colors.orange.withValues(alpha: 0.10),
        ),
      );
    }

    if (report.blockers.isNotEmpty) {
      chips.add(
        BookSourceSimpleChip(
          text: '阻塞 ${report.blockers.length}',
          color: Colors.redAccent,
          backgroundColor: Colors.redAccent.withValues(alpha: 0.10),
        ),
      );
    }

    // ── 健康状态 ──
    final health = manager.getHealth(source.id);
    switch (health.status) {
      case SourceHealthStatus.healthy:
        chips.add(
          BookSourceSimpleChip(
            text: '🟢 ${health.latencyMs}ms',
            color: Colors.green.shade700,
            backgroundColor: Colors.green.withValues(alpha: 0.10),
          ),
        );
      case SourceHealthStatus.degraded:
        chips.add(
          BookSourceSimpleChip(
            text: '🟡 ${health.latencyMs}ms',
            color: Colors.orange.shade700,
            backgroundColor: Colors.orange.withValues(alpha: 0.10),
          ),
        );
      case SourceHealthStatus.down:
        chips.add(
          BookSourceSimpleChip(
            text: '🔴 不可达',
            color: Colors.red.shade700,
            backgroundColor: Colors.red.withValues(alpha: 0.10),
          ),
        );
      case SourceHealthStatus.unknown:
        break;
    }

    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }
}

class BookSourceCard extends StatelessWidget {
  const BookSourceCard({
    super.key,
    required this.source,
    required this.manager,
    required this.onToggleEnable,
    required this.onApply,
    required this.onDiagnostic,
    required this.onEdit,
    required this.onTest,
    required this.onExport,
    required this.onPreview,
    required this.onDelete,
    this.expanded = false,
    this.onTapExpand,
  });

  final BookSourceModel source;
  final BookSourceManager manager;
  final ValueChanged<bool> onToggleEnable;
  final VoidCallback onApply;
  final VoidCallback onDiagnostic;
  final VoidCallback onEdit;
  final VoidCallback onTest;
  final VoidCallback onExport;
  final VoidCallback onPreview;
  final VoidCallback onDelete;
  final bool expanded;
  final VoidCallback? onTapExpand;

  @override
  Widget build(BuildContext context) {
    if (expanded) return _buildExpandedCard(context);
    return _buildCompactRow(context);
  }

  // ── 折叠态：一行显示关键信息 ──
  Widget _buildCompactRow(BuildContext context) {
    final report = NovelSourceCapabilityDetector.detect(source.toJson());
    final reportColor = bookSourceReportColor(report);
    final isCurrent = manager.currentSourceId == source.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: reportColor.withValues(alpha: 0.15)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTapExpand,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：名称 + 开关 + 状态标签
              Row(
                children: [
                  Expanded(
                    child: Text(
                      source.bookSourceName.isNotEmpty
                          ? source.bookSourceName
                          : '未命名书源',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Switch(
                    value: source.enabled,
                    onChanged: (v) => onToggleEnable(v),
                    activeColor: AppTokens.emerald,
                  ),
                  const SizedBox(width: 8),
                  if (isCurrent)
                    const BookSourceSimpleChip(
                      text: '●',
                      color: Colors.deepOrange,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              // 第二行：URL + 状态
              Row(
                children: [
                  Expanded(
                    child: Text(
                      source.bookSourceUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  BookSourceSimpleChip(
                    text: source.enabled ? '已启用' : '未启用',
                    color: source.enabled ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  BookSourceSimpleChip(
                    text: report.statusLabel,
                    color: reportColor,
                    backgroundColor: reportColor.withValues(alpha: 0.10),
                  ),
                ],
              ),
              // 第三行：分组 + 搜索 URL（如果有）
              if (source.bookSourceGroup.isNotEmpty || source.searchUrl.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (source.bookSourceGroup.isNotEmpty)
                      Text(
                        '分组：${source.bookSourceGroup}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppTokens.textTertiary,
                        ),
                      ),
                    if (source.searchUrl.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '搜索：${source.searchUrl}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppTokens.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── 展开态：显示详细信息和操作按钮 ──
  Widget _buildExpandedCard(BuildContext context) {
    final report = NovelSourceCapabilityDetector.detect(source.toJson());
    final reportColor = bookSourceReportColor(report);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: reportColor.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 折叠按钮
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.expand_less, size: 20),
                  onPressed: onTapExpand,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                Text(
                  source.bookSourceName.isNotEmpty
                      ? source.bookSourceName
                      : '未命名书源',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: source.enabled,
                  onChanged: (v) => onToggleEnable(v),
                  activeColor: AppTokens.emerald,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 详细信息
            if (source.bookSourceGroup.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '分组：${source.bookSourceGroup}',
                  style: const TextStyle(
                    color: AppTokens.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ),
            Text(
              source.bookSourceUrl,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 12.5,
                fontFamily: 'monospace',
              ),
            ),
            if (source.searchUrl.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '搜索：${source.searchUrl}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ],
            if (source.exploreUrl.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '发现：${source.exploreUrl}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ],
            const SizedBox(height: 6),
            // 能力报告
            BookSourceStatusChips(source: source, manager: manager),
            if (report.primaryBlocker.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                report.primaryBlocker,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 12.2,
                ),
              ),
            ] else if (report.warnings.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                report.warnings.first,
                style: const TextStyle(
                  color: Colors.orange,
                  fontSize: 12.2,
                ),
              ),
            ],
            const SizedBox(height: 12),
            // 操作按钮 — 分两行显示
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _actionBtn('启用并使用', onApply, color: AppTokens.violet),
                _actionBtn('诊断', onDiagnostic),
                _actionBtn('编辑', onEdit),
                _actionBtn('测试', onTest),
                _actionBtn('导出', onExport),
                _actionBtn('查看', onPreview),
                _actionBtn('删除', onDelete, color: Colors.red),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(String label, VoidCallback onPressed, {Color? color}) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: const Size(0, 32),
      ),
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}
