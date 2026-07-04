import 'package:flutter/material.dart';

import '../../../../design_system/app_tokens.dart';
import '../../../../design_system/widgets/app_back_button.dart';
import '../../../../design_system/widgets/app_cards.dart';
import '../book_source_manager.dart';

/// 书源管理器头部 / 统计卡片
class BookSourceManagerHero extends StatelessWidget {
  const BookSourceManagerHero({
    super.key,
    required this.manager,
    required this.visibleCount,
    required this.keyword,
    this.onBack,
  });

  final BookSourceManager manager;
  final int visibleCount;
  final String keyword;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final total = manager.items.length;
    final enabled = manager.enabledItems.length;
    final currentName = manager.currentSource?.bookSourceName.trim();

    return AppLightHeroCard(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      eyebrow: 'SOURCE RULES',
      title: '书源管理',
      subtitle: currentName != null && currentName.isNotEmpty
          ? '当前默认：$currentName'
          : '导入、预检查并启用小说规则源',
      badge: '小说',
      accentGradient: AppTokens.violetGradient,
      leading: AppBackButton(
        onPressed: onBack ?? () => Navigator.maybePop(context),
        label: '书源管理',
      ),
      actions: [
        AppStatusPill(
          label: '全部 $total',
          icon: Icons.rule_folder_rounded,
          color: AppTokens.violet,
        ),
        AppStatusPill(
          label: '启用 $enabled',
          icon: Icons.check_circle_rounded,
          color: AppTokens.emerald,
        ),
        if (keyword.trim().isNotEmpty)
          AppStatusPill(
            label: '匹配 $visibleCount',
            icon: Icons.search_rounded,
            color: AppTokens.primaryBlue,
          ),
      ],
    );
  }
}

/// 启动消息横幅
class BookSourceStartupBanner extends StatelessWidget {
  const BookSourceStartupBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    if (message.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: AppTokens.warning.withValues(alpha: 0.18)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: AppTokens.warning,
          fontSize: 12.5,
          height: 1.45,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 快速操作卡片
class BookSourceQuickActions extends StatelessWidget {
  const BookSourceQuickActions({
    super.key,
    required this.onImport,
    required this.onAddRule,
    this.onExportCurrent,
    this.onCheckHealth,
  });

  final VoidCallback onImport;
  final VoidCallback onAddRule;
  final VoidCallback? onExportCurrent;
  final VoidCallback? onCheckHealth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          SizedBox(
            width: _cardWidth(context),
            child: AppCompactActionCard(
              title: '导入书源',
              subtitle: 'JSON / 预检查',
              icon: Icons.playlist_add_rounded,
              color: AppTokens.violet,
              onTap: onImport,
            ),
          ),
          SizedBox(
            width: _cardWidth(context),
            child: AppCompactActionCard(
              title: '新增规则',
              subtitle: '手动编辑',
              icon: Icons.add_box_rounded,
              color: AppTokens.primaryBlue,
              onTap: onAddRule,
            ),
          ),
          if (onExportCurrent != null)
            SizedBox(
              width: _cardWidth(context),
              child: AppCompactActionCard(
                title: '导出全部',
                subtitle: 'JSON',
                icon: Icons.file_download_rounded,
                color: AppTokens.emerald,
                onTap: onExportCurrent,
              ),
            ),
          if (onCheckHealth != null)
            SizedBox(
              width: _cardWidth(context),
              child: AppCompactActionCard(
                title: '全部检测',
                subtitle: '连通性与延迟',
                icon: Icons.favorite_border_rounded,
                color: AppTokens.rose,
                onTap: onCheckHealth,
              ),
            ),
        ],
      ),
    );
  }

  double _cardWidth(BuildContext context) {
    // 计算每张卡片宽度，使它们在行内均分
    final screenWidth = MediaQuery.sizeOf(context).width - 32; // 减去 padding
    final count = (onExportCurrent != null ? 1 : 0) +
        (onCheckHealth != null ? 1 : 0) +
        2; // 至少 import + add
    return (screenWidth - count * 10) / count;
  }
}

/// 搜索框
class BookSourceSearchBox extends StatelessWidget {
  const BookSourceSearchBox({
    super.key,
    required this.controller,
    required this.keyword,
    this.onChanged,
    this.onClear,
  });

  final TextEditingController controller;
  final String keyword;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTokens.divider),
        boxShadow: AppTokens.shadowSm(color: AppTokens.violet),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: AppTokens.violet),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: const InputDecoration(
                hintText: '搜索名称 / 分组 / 域名',
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (keyword.isNotEmpty)
            IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.close_rounded),
              onPressed: onClear,
            ),
        ],
      ),
    );
  }
}

/// 空书源 / 无搜索结果占位
class BookSourceEmptySources extends StatelessWidget {
  const BookSourceEmptySources({super.key, required this.keyword});

  final String keyword;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        16,
        44,
        16,
        AppTokens.pageBottomPadding,
      ),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(AppTokens.radiusLg),
            border: Border.all(color: AppTokens.divider),
            boxShadow: AppTokens.shadowSm(),
          ),
          child: Column(
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: AppTokens.surfaceTint,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(
                  keyword.trim().isEmpty
                      ? Icons.rule_folder_outlined
                      : Icons.search_off_rounded,
                  color: AppTokens.violet,
                  size: 32,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                keyword.trim().isEmpty ? '还没有书源' : '没有找到匹配的书源',
                style: const TextStyle(
                  color: AppTokens.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                keyword.trim().isEmpty
                    ? '点击"导入书源"粘贴 JSON，系统会先做可用性预检查。'
                    : '换个关键词，或清空搜索试试。',
                style: const TextStyle(
                  color: AppTokens.textSecondary,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
