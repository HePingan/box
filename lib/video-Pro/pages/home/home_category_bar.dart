import 'package:flutter/material.dart';

import '../../controller/video_controller.dart';
import 'home_utils.dart';

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

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFF273449)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF111827).withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE08A).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: Color(0xFFFFE08A),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '分类筛选',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  '胶囊导航',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFFFFE08A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '左右滑动切换频道，首页海报墙会同步刷新',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.60),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: safeCategories.length + 1,
              itemBuilder: (context, index) {
                final isAll = index == 0;
                final String label = isAll
                    ? '全部'
                    : safeCategories[index - 1].typeName;
                final int? typeId = isAll
                    ? null
                    : safeCategories[index - 1].typeId;
                final bool isSelected = controller.currentTypeId == typeId;

                return Padding(
                  padding: const EdgeInsets.only(right: 9),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => controller.setCategory(typeId),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(horizontal: 17),
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? const LinearGradient(
                                colors: [Color(0xFFFFE08A), Color(0xFFFB923C)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: isSelected
                            ? null
                            : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: isSelected
                              ? Colors.transparent
                              : Colors.white.withValues(alpha: 0.10),
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: const Color(
                                    0xFFFB923C,
                                  ).withValues(alpha: 0.20),
                                  blurRadius: 16,
                                  offset: const Offset(0, 8),
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0xFF111827)
                                : Colors.white.withValues(alpha: 0.82),
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
