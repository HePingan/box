import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_cards.dart';

import '../../models/aggregate_result.dart';
import '../../models/video_source.dart';
import 'aggregate_search_video_card.dart';

class AggregateSearchSourceSection extends StatelessWidget {
  const AggregateSearchSourceSection({
    super.key,
    required this.source,
    required this.results,
    required this.coverUrlFor,
    required this.onTapVideo,
  });

  final VideoSource source;
  final List<AggregateResult> results;
  final String? Function(AggregateResult result) coverUrlFor;
  final ValueChanged<AggregateResult> onTapVideo;

  @override
  Widget build(BuildContext context) {
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
              title: source.name,
              subtitle: '横滑查看该来源命中的资源',
              icon: Icons.source_rounded,
              trailing: AppStatusPill(
                label: '${results.length} 条',
                icon: Icons.movie_filter_rounded,
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
