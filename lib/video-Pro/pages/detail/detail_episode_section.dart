import 'package:flutter/material.dart';

import 'detail_models.dart';

class DetailEpisodeSection extends StatefulWidget {
  const DetailEpisodeSection({
    super.key,
    required this.episodes,
    required this.currentIndex,
    required this.onEpisodeTap,
  });

  final List<DetailPlayEpisode> episodes;
  final int currentIndex;
  final ValueChanged<int> onEpisodeTap;

  @override
  State<DetailEpisodeSection> createState() => _DetailEpisodeSectionState();
}

class _DetailEpisodeSectionState extends State<DetailEpisodeSection> {
  bool _isExpanded = false;
  bool _isReversed = false;

  @override
  void didUpdateWidget(covariant DetailEpisodeSection oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.episodes != widget.episodes) {
      _isExpanded = false;
      _isReversed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.episodes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('当前线路暂无可播放集数')),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final crossAxisCount = width >= 960
            ? 6
            : width >= 720
                ? 5
                : width >= 420
                    ? 4
                    : 3;

        final childAspectRatio = width >= 960
            ? 2.8
            : width >= 720
                ? 2.5
                : width >= 420
                    ? 2.25
                    : 2.0;

        final total = widget.episodes.length;
        final collapsedCount = crossAxisCount * 3;
        final displayCount =
            _isExpanded ? total : (total > collapsedCount ? collapsedCount : total);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '选集',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                if (total > 1)
                  TextButton.icon(
                    onPressed: () => setState(() => _isReversed = !_isReversed),
                    icon: const Icon(
                      Icons.sort_rounded,
                      size: 16,
                      color: Colors.blueAccent,
                    ),
                    label: Text(
                      _isReversed ? '切为正序' : '切为倒序',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.blueAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.builder(
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: displayCount,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: childAspectRatio,
              ),
              itemBuilder: (context, index) {
                final realIndex = _isReversed ? total - 1 - index : index;
                final episode = widget.episodes[realIndex];
                final isSelected = realIndex == widget.currentIndex;

                return InkWell(
                  onTap: () => widget.onEpisodeTap(realIndex),
                  borderRadius: BorderRadius.circular(6),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blueAccent : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      episode.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
            if (!_isExpanded && total > displayCount)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 16),
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _isExpanded = true),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                  label: const Text('展开全部集数'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}