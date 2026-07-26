import 'package:flutter/material.dart';

import '../../controller/video_controller.dart';
import 'home_utils.dart';
import '../../../design_system/app_tokens.dart';

class HomeCategoryBar extends StatelessWidget {
  const HomeCategoryBar({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.categories.isEmpty) return const SizedBox.shrink();

    final safeCategories = controller.categories
        .where((cat) => isSafeContent(cat.typeName))
        .toList(growable: false);

    if (safeCategories.isEmpty) return const SizedBox.shrink();

    // 轻量横向 chip 条：去掉深色面板、大标题、金徽章与说明文字，
    // 选中态用柔底 + 文字加重，不用发光金渐变，和封面卡风格统一。
    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
        itemCount: safeCategories.length + 1,
        itemBuilder: (context, index) {
          final isAll = index == 0;
          final String label = isAll ? '全部' : safeCategories[index - 1].typeName;
          final int? typeId = isAll ? null : safeCategories[index - 1].typeId;
          final bool isSelected = controller.currentTypeId == typeId;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTokens.radiusPill),
              onTap: () => controller.setCategory(typeId),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 15),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTokens.primaryBlue.withValues(alpha: 0.10)
                      : const Color(0xFFF3F5FA),
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                  border: Border.all(
                    color: isSelected
                        ? AppTokens.primaryBlue.withValues(alpha: 0.45)
                        : Colors.transparent,
                  ),
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected
                        ? AppTokens.primaryBlue
                        : AppTokens.textSecondary,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
