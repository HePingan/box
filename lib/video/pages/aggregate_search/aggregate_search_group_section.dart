import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_cards.dart';

import '../../models/aggregate_grouped_result.dart';
import '../../models/aggregate_result.dart';
import 'aggregate_search_video_card.dart';

/// 按片名归并后的结果组卡片：标题 + 命中源数 + 横滑多源结果。
class AggregateSearchGroupSection extends StatelessWidget {
  const AggregateSearchGroupSection({
    super.key,
    required this.group,
    required this.coverUrlFor,
    required this.onTapVideo,
  });

  final AggregateGroupedResult group;
  final String? Function(AggregateResult result) coverUrlFor;
  final ValueChanged<AggregateResult> onTapVideo;

  @override
  Widget build(BuildContext context) {
    final results = group.results;
    if (results.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: AppTokens.divider),
        boxShadow: AppTokens.shadowSm(color: AppTokens.primaryBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: AppSectionHeader(
              title: group.title,
              subtitle: '横滑对比不同来源的同名资源',
              icon: Icons.movie_rounded,
              trailing: AppStatusPill(
                label: '命中 ${group.hitCount} 源',
                icon: Icons.hub_rounded,
                color: AppTokens.violet,
              ),
            ),
          ),
          SizedBox(
            height: 216,
            child: ListView.separated(
              padding: const EdgeInsets.all(14),
              scrollDirection: Axis.horizontal,
              itemCount: results.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final result = results[index];
                return AggregateSearchVideoCard(
                  result: result,
                  coverUrl: coverUrlFor(result),
                  sourceLabel: result.source.name,
                  onTap: () => onTapVideo(result),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
