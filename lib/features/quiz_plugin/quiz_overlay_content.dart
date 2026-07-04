import 'package:flutter/material.dart';

import '../../design_system/app_tokens.dart';
import 'quiz_config.dart';
import 'quiz_engine.dart';

/// 悬浮窗内容组件
///
/// 显示捕获的题目和搜题结果，既可嵌入 Flutter 页面预览，
/// 也可通过 MethodChannel 渲染到原生悬浮窗中。
class QuizOverlayContent extends StatelessWidget {
  const QuizOverlayContent({
    super.key,
    this.question = '',
    this.result,
    this.isSearching = false,
    this.isAccessible = false,
    this.onToggleAccessibility,
    this.onSearch,
    this.onDismiss,
    this.onPin,
    this.compactMode = false,
    this.themeColor = const Color(0xFF4F46E5),
  });

  final String question;
  final QuizResult? result;
  final bool isSearching;
  final bool isAccessible;
  final VoidCallback? onToggleAccessibility;
  final VoidCallback? onSearch;
  final VoidCallback? onDismiss;
  final VoidCallback? onPin;
  final bool compactMode;
  final Color themeColor;

  @override
  Widget build(BuildContext context) {
    if (compactMode) return _buildCompact(context);
    return _buildFull(context);
  }

  // ── 完整模式（悬浮窗默认） ──

  Widget _buildFull(BuildContext context) {
    final themeColor = QuizConfig.themeColors[0];

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppTokens.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: themeColor,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.quiz_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      '答题助手',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  _iconButton(Icons.push_pin_rounded, '固定', onPin),
                  const SizedBox(width: 2),
                  _iconButton(Icons.close_rounded, '关闭', onDismiss),
                ],
              ),
            ),
            // 题目区域
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppTokens.divider),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📝 捕获的题目',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTokens.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    question.isNotEmpty ? question : '等待捕获题目…',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: question.isNotEmpty
                          ? AppTokens.textPrimary
                          : AppTokens.textTertiary,
                      height: 1.4,
                    ),
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // 答案区域
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '🔍 搜题结果',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTokens.textTertiary,
                        ),
                      ),
                      const Spacer(),
                      if (isSearching)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      if (result != null && result!.elapsedMs > 0)
                        Text(
                          '${result!.elapsedMs}ms',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppTokens.textTertiary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (!isAccessible) ...[
                    // 无障碍未启用提示
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTokens.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppTokens.amber.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              size: 16, color: AppTokens.amber),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '需开启无障碍权限才能自动捕获题目',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTokens.amber.withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onToggleAccessibility,
                        icon: const Icon(Icons.accessibility_new_rounded,
                            size: 16),
                        label: const Text('开启无障碍权限'),
                      ),
                    ),
                  ] else if (result == null && !isSearching) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTokens.surfaceMuted,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.touch_app_rounded,
                              size: 16, color: AppTokens.textTertiary),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '打开题目所在 App，题目会自动捕获',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTokens.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (result != null && result!.isSuccess) ...[
                    ...result!.answers.asMap().entries.map((entry) {
                      final i = entry.key;
                      final answer = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: i == 0
                                ? themeColor.withValues(alpha: 0.08)
                                : AppTokens.surfaceMuted,
                            borderRadius: BorderRadius.circular(8),
                            border: i == 0
                                ? Border.all(
                                    color: themeColor.withValues(alpha: 0.3))
                                : null,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: i == 0
                                      ? themeColor
                                      : AppTokens.textTertiary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${i + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  answer.text,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: i == 0
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: AppTokens.textPrimary,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                              if (answer.source.isNotEmpty)
                                Text(
                                  answer.source,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppTokens.textTertiary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ] else if (result != null && !result!.isSuccess) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTokens.rose.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              size: 16, color: AppTokens.rose),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              result!.error ?? '未找到答案',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTokens.rose,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (question.isNotEmpty && onSearch != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: isSearching ? null : onSearch,
                        icon: Icon(
                          isSearching
                              ? Icons.hourglass_top_rounded
                              : Icons.search_rounded,
                          size: 16,
                        ),
                        label: Text(isSearching ? '搜题中…' : '手动搜题'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 紧凑模式（用于预览/调试） ──

  Widget _buildCompact(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTokens.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            question.isNotEmpty ? question : '等待题目…',
            style: TextStyle(
              fontSize: 13,
              color: question.isNotEmpty
                  ? AppTokens.textPrimary
                  : AppTokens.textTertiary,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          if (result != null) ...[
            const SizedBox(height: 6),
            const Divider(height: 1),
            const SizedBox(height: 6),
            if (result!.isSuccess)
              ...result!.answers.take(3).map(
                    (a) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: [
                          Container(
                            width: 16, height: 16,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: themeColor,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              '${result!.answers.indexOf(a) + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              a.text,
                              style: const TextStyle(fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
            else
              Text(
                result!.error ?? '搜题失败',
                style: TextStyle(fontSize: 12, color: AppTokens.rose),
              ),
          ],
          if (isSearching)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _iconButton(IconData icon, String tooltip, VoidCallback? onTap) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        icon: Icon(icon, size: 16, color: Colors.white70),
        onPressed: onTap,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
