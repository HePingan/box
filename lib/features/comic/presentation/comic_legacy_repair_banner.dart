// 旧版本导入的漫画丢了页图：给一条能自己说清楚、能一键重来的提示条。
//
// 为什么是提示条而不是弹窗：丢页图**不影响打开书架、也不影响看别的书**，弹窗会拦住
// 用户做别的事；而这个状态会一直在（直到他重导或删书）——弹一次不够，每次启动都弹
// 又变成骚扰。放在书架顶部：看得到、能关掉、关掉后这次运行里不再出现。
//
// 为什么由外部注入「哪些书坏了」：判定要读文件系统（页图还在不在），属于 domain 侧
// 的事（另一个 agent 在 `comic_page_health.dart` 里做）。本组件只负责**呈现**，
// 这样判定逻辑没落地时这里也能编译、能测。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:box/features/comic/domain/comic_book.dart';
import '../../../design_system/app_tokens.dart';

/// 旧漫画「页图丢失」提示条。
///
/// 不持有状态：显示与否由调用方（书架页）用 `affectedBooks` + 自己的关闭标记决定。
class ComicLegacyRepairBanner extends StatelessWidget {
  const ComicLegacyRepairBanner({
    super.key,
    required this.affectedBooks,
    required this.onReimportRequested,
    this.onDismiss,
  });

  /// 页图已经不在的旧书（判定由 domain 侧给出，本组件不做 IO）。
  final List<ComicBook> affectedBooks;

  /// 点「重新导入」：由页面走既有的文件选择 / 导入流程（一次一本）。
  final VoidCallback onReimportRequested;

  /// 点「暂不处理」：把"这次别提醒了"交给页面去落盘。
  ///
  /// 为 null 时**不画**这个按钮：没有回调就没有"关掉"这回事。画一个按了没反应、
  /// 下次启动又出现的按钮，比不画更让人恼火。
  final Future<void> Function()? onDismiss;

  @override
  Widget build(BuildContext context) {
    // 没坏书就完全不占位：调用方可以无条件把它放在书架顶部，不必自己包一层 if。
    if (affectedBooks.isEmpty) return const SizedBox.shrink();

    final count = affectedBooks.length;
    final dismiss = onDismiss;

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppTokens.spaceMd,
        AppTokens.spaceMd,
        AppTokens.spaceMd,
        0,
      ),
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      decoration: BoxDecoration(
        // 淡黄底 + 同色描边：这是"需要你动手、但不紧急"的提示，不是错误红。
        color: AppTokens.softPanel(AppTokens.warning),
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(color: AppTokens.warning.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.broken_image_outlined,
                size: 18,
                color: AppTokens.warning,
              ),
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(
                child: Text(
                  '有 $count 本旧漫画的图片丢了',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                    color: AppTokens.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceSm),
          // 点名是哪几本：只说"有 3 本坏了"的话，用户还得自己一本本点开试。
          // 最多列三本（再长就挤掉真正的说明），其余的用"等 N 本"收尾。
          Text(
            _bookNames(affectedBooks),
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: AppTokens.textPrimary,
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            '这些书是早期版本导入的：当时图片解压到系统临时目录，被系统清理后就成了白页。'
            '压缩包还在的话，重新选一次就能恢复阅读。',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppTokens.textSecondary,
            ),
          ),
          const SizedBox(height: AppTokens.spaceXs),
          // 这句是**诚实**的部分：我们没有可靠的"文件 ↔ 旧书"对应关系（用户可能重命名、
          // 换过压缩包），所以不能假装点了就自动修好。说清楚"会多一本"，比事后让人疑惑强。
          Text(
            '一次导入一本：重新导入后会多出一本新书，确认内容一样，就长按删掉旧的那本。',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppTokens.textTertiary,
            ),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          // 用 Wrap 而不是 Row：窄屏（分屏/小屏机）上两个按钮横排会挤到溢出一像素，
          // 换行比裁边安全。
          Wrap(
            spacing: AppTokens.spaceSm,
            runSpacing: AppTokens.spaceXs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                onPressed: onReimportRequested,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceLg,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('重新导入'),
              ),
              if (dismiss != null)
                TextButton(
                  onPressed: () {
                    // 落盘交给页面：本组件不持有状态，也不该去碰存储。
                    unawaited(dismiss());
                  },
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(0, 36),
                    foregroundColor: AppTokens.textSecondary,
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  child: const Text('暂不处理'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 坏书点名文案：`《甲》《乙》《丙》等 5 本`。
  ///
  /// 最多列三本：提示条是"顺带告诉你一声"，列一长串书名会把真正要看的说明挤出屏幕。
  static String _bookNames(List<ComicBook> books) {
    const shown = 3;
    final head = books
        .take(shown)
        .map((b) => '《${b.title}》')
        .join('');
    return books.length <= shown ? head : '$head 等 ${books.length} 本';
  }
}
