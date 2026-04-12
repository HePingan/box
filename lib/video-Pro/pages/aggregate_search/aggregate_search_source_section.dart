import 'package:flutter/material.dart';

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
  // 🚀 优化：类型从 Future<String?> 变为极速同步的 String?
  final String? Function(AggregateResult result) coverUrlFor; 
  final ValueChanged<AggregateResult> onTapVideo;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                const Icon(Icons.source_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    source.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '共 ${results.length} 个结果',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 210,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              scrollDirection: Axis.horizontal,
              itemCount: results.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final result = results[index];

                return AggregateSearchVideoCard(
                  result: result,
                  // 🚀 优化：直接传入同步字符串，不再触发 Future 构建回调
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