import 'dart:math';

import 'package:flutter/material.dart';

import '../../controller/video_controller.dart';
import 'home_utils.dart';

class HomeQuickAccessGrid extends StatelessWidget {
  const HomeQuickAccessGrid({
    super.key,
    required this.controller,
    required this.screenWidth,
  });

  final VideoController controller;
  final double screenWidth;

  @override
  Widget build(BuildContext context) {
    final safeCategories = controller.categories
        .where((cat) => isSafeContent(cat.typeName))
        .toList(growable: false);

    int? getMappedTypeId(
      List<String> exactMatch,
      List<String> fuzzyMatch,
    ) {
      for (final word in exactMatch) {
        for (final cat in safeCategories) {
          if (cat.typeName == word) return cat.typeId;
        }
      }

      for (final word in fuzzyMatch) {
        for (final cat in safeCategories) {
          if (cat.typeName.contains(word)) return cat.typeId;
        }
      }

      return null;
    }

    final List<_QuickAccessItem> items = [
      _QuickAccessItem(
        title: '全部影片',
        icon: Icons.auto_awesome,
        typeId: null,
        colors: const [
          Color(0xFF90A4AE),
          Color(0xFF607D8B),
        ],
      ),
      _QuickAccessItem(
        title: '电影找片',
        icon: Icons.movie_creation_outlined,
        typeId: getMappedTypeId(['电影'], ['电影', '片']),
        colors: const [
          Color(0xFFFFB74D),
          Color(0xFFFF9800),
        ],
      ),
      _QuickAccessItem(
        title: '热播追剧',
        icon: Icons.live_tv_rounded,
        typeId: getMappedTypeId(
          ['连续剧', '国产剧', '电视剧'],
          ['剧', '剧集'],
        ),
        colors: const [
          Color(0xFF64B5F6),
          Color(0xFF2196F3),
        ],
      ),
      _QuickAccessItem(
        title: '动漫次元',
        icon: Icons.animation_rounded,
        typeId: getMappedTypeId(
          ['动漫', '动画片'],
          ['漫', '动画'],
        ),
        colors: const [
          Color(0xFF81C784),
          Color(0xFF4CAF50),
        ],
      ),
      _QuickAccessItem(
        title: '综艺大观',
        icon: Icons.mic_external_on_rounded,
        typeId: getMappedTypeId(['综艺'], ['综艺']),
        colors: const [
          Color(0xFFF06292),
          Color(0xFFE91E63),
        ],
      ),
      _QuickAccessItem(
        title: '爽文短剧',
        icon: Icons.video_library_rounded,
        typeId: getMappedTypeId(
          ['短剧', '微网剧'],
          ['短剧'],
        ),
        colors: const [
          Color(0xFF7986CB),
          Color(0xFF3F51B5),
        ],
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? constraints.maxWidth
                : screenWidth;

        final horizontalPadding = availableWidth < 600 ? 12.0 : 16.0;
        final spacing = 10.0;
        final columns = availableWidth >= 960
            ? 6
            : availableWidth >= 720
                ? 4
                : availableWidth >= 420
                    ? 3
                    : 2;

        final itemWidth = max(
          96.0,
          (availableWidth - horizontalPadding * 2 - spacing * (columns - 1)) /
              columns,
        );

        final compact = availableWidth < 600;

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: RepaintBoundary(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '快捷入口',
                      style: TextStyle(
                        fontSize: compact ? 15.5 : 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '系统猜测的常用大类',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final item in items)
                      SizedBox(
                        width: itemWidth,
                        child: _buildQuickAccessCard(
                          context: context,
                          controller: controller,
                          item: item,
                          compact: compact,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickAccessCard({
    required BuildContext context,
    required VideoController controller,
    required _QuickAccessItem item,
    required bool compact,
  }) {
    final bool isSelected = item.title == '全部影片'
        ? controller.currentTypeId == null
        : controller.currentTypeId == item.typeId && item.typeId != null;

    final radius = compact ? 22.0 : 12.0;
    final height = compact ? 58.0 : 64.0;
    final iconSize = compact ? 18.0 : 20.0;
    final iconBoxSize = compact ? 30.0 : 34.0;
    final fontSize = compact ? 14.5 : 15.0;

    return GestureDetector(
      onTap: () {
        if (item.title != '全部影片' && item.typeId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('当前片源未映射「${item.title}」分类'),
            ),
          );
          return;
        }

        controller.setCategory(item.typeId);
      },
      child: RepaintBoundary(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              colors: item.colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: isSelected
                ? Border.all(color: Colors.black87, width: 2)
                : Border.all(color: Colors.transparent, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: item.colors.last.withOpacity(isSelected ? 0.28 : 0.16),
                blurRadius: isSelected ? 12 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: iconBoxSize,
                height: iconBoxSize,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  item.icon,
                  color: Colors.white,
                  size: iconSize,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: fontSize,
                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAccessItem {
  final String title;
  final IconData icon;
  final int? typeId;
  final List<Color> colors;

  const _QuickAccessItem({
    required this.title,
    required this.icon,
    required this.typeId,
    required this.colors,
  });
}