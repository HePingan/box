import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../design_system/app_tokens.dart';
import '../domain/announcement_center.dart';
import '../domain/cloud_sync_models.dart';

/// 独立的公告页。
///
/// 为什么不复用个人中心里那段：公告原先只能从「抽屉 → 账号 → 个人中心」三层
/// 点进去，出故障时等于没有触达手段。这里给一个抽屉直达的一级入口，读的是
/// app 作用域的 [AnnouncementCenter]，和红点/弹窗共享同一份状态。
class AnnouncementPage extends StatefulWidget {
  const AnnouncementPage({super.key});

  @override
  State<AnnouncementPage> createState() => _AnnouncementPageState();
}

class _AnnouncementPageState extends State<AnnouncementPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 已 bootstrap 过则是空操作（幂等），首次进入会补拉。
      context.read<AnnouncementCenter>().bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    final center = context.watch<AnnouncementCenter>();
    final items = center.state.sorted;

    return Scaffold(
      appBar: AppBar(
        title: const Text('公告'),
        actions: [
          if (center.hasUnread)
            TextButton(
              onPressed: () async {
                for (final item in items) {
                  if (item.id.isEmpty) continue;
                  await center.acknowledge(item.id);
                }
              },
              child: const Text('全部已读'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: center.refresh,
        child: items.isEmpty
            ? ListView(
                children: [
                  const SizedBox(height: 120),
                  Icon(
                    Icons.campaign_outlined,
                    size: 46,
                    color: AppTokens.textSecondary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      center.lastError == null ? '暂无公告' : '公告加载失败，下拉重试',
                      style: const TextStyle(
                        color: AppTokens.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final item = items[index];
                  return _AnnouncementCard(
                    entry: item,
                    unread: !center.state.readIds.contains(item.id),
                    onRead: () => center.acknowledge(item.id),
                  );
                },
              ),
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({
    required this.entry,
    required this.unread,
    required this.onRead,
  });

  final AnnouncementEntry entry;
  final bool unread;
  final VoidCallback onRead;

  Color get _levelColor => switch (entry.level) {
    'warning' => AppTokens.warning,
    'notice' => AppTokens.primaryBlue,
    _ => AppTokens.textSecondary,
  };

  String get _levelLabel => switch (entry.level) {
    'warning' => '重要',
    'notice' => '通知',
    _ => '资讯',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(
          color: unread
              ? _levelColor.withValues(alpha: 0.4)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _levelColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTokens.radiusXs),
                ),
                child: Text(
                  _levelLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _levelColor,
                  ),
                ),
              ),
              if (entry.pinned) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.push_pin_rounded,
                  size: 13,
                  color: AppTokens.textSecondary,
                ),
              ],
              const Spacer(),
              if (unread)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppTokens.danger,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            entry.title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          SelectableText(
            entry.body,
            style: const TextStyle(fontSize: 13, height: 1.6),
          ),
          if (entry.linkUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    entry.linkUrl,
                    style: const TextStyle(fontSize: 12, height: 1.5),
                  ),
                ),
                IconButton(
                  tooltip: '复制链接',
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: entry.linkUrl),
                    );
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
          ],
          if (unread)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onRead, child: const Text('标为已读')),
            ),
        ],
      ),
    );
  }
}
