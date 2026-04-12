import 'package:flutter/material.dart';

import '../../controller/video_controller.dart';
import '../../models/video_category.dart';
import 'home_utils.dart';

class HomeCategoryBar extends StatelessWidget {
  const HomeCategoryBar({
    super.key,
    required this.controller,
  });

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.categories.isEmpty) return const SizedBox.shrink();

    final safeCategories = controller.categories
        .where((cat) => isSafeContent(cat.typeName))
        .toList(growable: false);

    if (safeCategories.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                '分类筛选',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '如果上方快捷入口无影片，请在此选择精确子分类',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.redAccent.shade200,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 38,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: safeCategories.length + 1,
            itemBuilder: (context, index) {
              final isAll = index == 0;
              final String label =
                  isAll ? '全部' : safeCategories[index - 1].typeName;
              final int? typeId = isAll ? null : safeCategories[index - 1].typeId;
              final bool isSelected = controller.currentTypeId == typeId;

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => controller.setCategory(typeId),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade300,
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
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
    );
  }
}