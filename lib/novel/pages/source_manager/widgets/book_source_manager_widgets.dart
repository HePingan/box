import 'package:flutter/material.dart';

import '../../../core/novel_source_capability.dart';
import '../../../core/novel_source_capability_detector.dart';
import '../book_source_manager.dart';
import '../book_source_model.dart';

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

  @override
  Widget build(BuildContext context) {
    final report = NovelSourceCapabilityDetector.detect(source.toJson());
    final reportColor = bookSourceReportColor(report);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: reportColor.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  source.bookSourceName.isNotEmpty
                      ? source.bookSourceName
                      : '未命名书源',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Switch(value: source.enabled, onChanged: onToggleEnable),
            ],
          ),
          BookSourceStatusChips(source: source, manager: manager),
          const SizedBox(height: 10),
          if (source.bookSourceGroup.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '分组：${source.bookSourceGroup}',
                style: const TextStyle(color: Colors.black54, fontSize: 12.5),
              ),
            ),
          Text(
            source.bookSourceUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.black54, fontSize: 12.5),
          ),
          if (source.searchUrl.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '搜索：${source.searchUrl}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.black45, fontSize: 12),
            ),
          ],
          if (report.primaryBlocker.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              report.primaryBlocker,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12.2),
            ),
          ] else if (report.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              report.warnings.first,
              style: const TextStyle(color: Colors.orange, fontSize: 12.2),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton(
                onPressed: onApply,
                child: Text(
                  manager.currentSourceId == source.id ? '重新使用' : '启用并使用',
                ),
              ),
              OutlinedButton(onPressed: onDiagnostic, child: const Text('诊断')),
              OutlinedButton(onPressed: onEdit, child: const Text('编辑')),
              OutlinedButton(onPressed: onTest, child: const Text('测试')),
              OutlinedButton(onPressed: onExport, child: const Text('导出')),
              OutlinedButton(onPressed: onPreview, child: const Text('查看')),
              OutlinedButton(onPressed: onDelete, child: const Text('删除')),
            ],
          ),
        ],
      ),
    );
  }
}
