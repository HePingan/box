import 'package:flutter/material.dart';

import 'detail_models.dart';

import '../../../design_system/app_tokens.dart';

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
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE7ECF5)),
        ),
        child: Text(
          '当前线路暂无可播放集数',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: const Color(0xFF64748B),
            fontWeight: FontWeight.w700,
          ),
        ),
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
        final displayCount = _isExpanded
            ? total
            : (total > collapsedCount ? collapsedCount : total);

        return Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE7ECF5)),
            boxShadow: [
              BoxShadow(
                color: AppTokens.inkDark.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF6D28D9,
                          ).withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.grid_view_rounded,
                          size: 18,
                          color: Color(0xFF6D28D9),
                        ),
                      ),
                      const SizedBox(width: 9),
                      const Text(
                        '剧集选择',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: AppTokens.inkDark,
                        ),
                      ),
                    ],
                  ),
                  if (total > 1)
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _isReversed = !_isReversed),
                      icon: const Icon(
                        Icons.sort_rounded,
                        size: 16,
                        color: Color(0xFF6D28D9),
                      ),
                      label: Text(
                        _isReversed ? '切为正序' : '切为倒序',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6D28D9),
                          fontWeight: FontWeight.w900,
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
                    borderRadius: BorderRadius.circular(14),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? const LinearGradient(
                                colors: [Color(0xFFFFE08A), Color(0xFFFB923C)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: isSelected ? null : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? Colors.transparent
                              : const Color(0xFFE7ECF5),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        episode.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected
                              ? AppTokens.inkDark
                              : const Color(0xFF475569),
                          fontWeight: FontWeight.w900,
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
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                    ),
                    label: const Text('展开全部集数'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFFE08A),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(
                        color: const Color(0xFF6D28D9).withValues(alpha: 0.24),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
