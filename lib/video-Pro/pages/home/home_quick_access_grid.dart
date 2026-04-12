import 'package:flutter/material.dart';

import '../../controller/video_controller.dart';
import '../../models/video_category.dart';
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

    int crossAxisCount;
    double aspectRatio;

    if (screenWidth > 1000) {
      crossAxisCount = 6;
      aspectRatio = 2.5;
    } else if (screenWidth > 600) {
      crossAxisCount = 3;
      aspectRatio = 2.8;
    } else {
      crossAxisCount = 2;
      aspectRatio = 2.4;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                '快捷入口',
                style: TextStyle(
                  fontSize: 16,
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
          GridView.builder(
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: aspectRatio,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemBuilder: (context, index) {
              final item = items[index];
              final bool isSelected = item.title == '全部影片'
                  ? controller.currentTypeId == null
                  : controller.currentTypeId == item.typeId && item.typeId != null;

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
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: item.colors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: isSelected
                        ? Border.all(color: Colors.black87, width: 2)
                        : Border.all(color: Colors.transparent, width: 2),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: item.colors.last.withOpacity(0.5),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : [],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          item.icon,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        item.title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
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