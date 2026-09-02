import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/app_tokens.dart';
import '../domain/cloud_sync_models.dart';

/// 重要公告弹窗。
///
/// 只给 warning 级公告用（挑选逻辑在 AnnouncementStartupPolicy）。存在的理由是
/// 183/184/185 更新验签事故：公告发出去了，但入口埋在「抽屉 → 账号 → 个人
/// 中心」三层之下，用户根本看不到。
///
/// 链接这里给「复制」按钮而不是可点击超链接：项目没有 url_launcher 依赖，
/// 个人中心里的 linkUrl 也只是不可点的 SelectableText。复制到剪贴板是当前
/// 依赖下最可用的做法，用户粘到浏览器即可。
Future<void> showAnnouncementPopup({
  required BuildContext context,
  required AnnouncementEntry entry,
  required Future<void> Function() onAcknowledged,
}) async {
  await showDialog<void>(
    context: context,
    // 不允许点遮罩糊掉：这类公告要么读要么显式关，避免误触后再也不弹。
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTokens.warning.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppTokens.radiusChip),
              ),
              child: const Icon(
                Icons.campaign_rounded,
                size: 19,
                color: AppTokens.warning,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                entry.title.isEmpty ? '重要公告' : entry.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(
                  entry.body,
                  style: const TextStyle(fontSize: 14, height: 1.6),
                ),
                if (entry.linkUrl.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _LinkRow(url: entry.linkUrl),
                ],
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('稍后再看'),
          ),
          FilledButton(
            onPressed: () async {
              // 先标已读再关：关闭后 context 可能失效。
              await onAcknowledged();
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('知道了'),
          ),
        ],
      );
    },
  );
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(AppTokens.radiusInner),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              url,
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
          IconButton(
            tooltip: '复制链接',
            icon: const Icon(Icons.copy_rounded, size: 17),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('链接已复制，去浏览器粘贴打开'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
