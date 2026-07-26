import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/video/controller/video_controller.dart';
import 'package:box/video/models/douban_ranking_item.dart';
import 'package:box/video/services/douban_ranking_service.dart';
import 'package:box/video/services/video_api_service.dart';
import 'package:box/video/pages/aggregate_search_page.dart';
import 'package:box/video/pages/video_detail_page.dart';

/// 豆瓣榜单条目卡片(横向滚动)。
class _RankingEntry extends StatelessWidget {
  const _RankingEntry({
    required this.item,
    required this.rank,
    required this.onTap,
  });

  final DoubanRankingItem item;
  final int rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: SizedBox(
        width: 130,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 海报封面 + 排名角标
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  child: CachedNetworkImage(
                    imageUrl: item.displayCoverUrl,
                    httpHeaders: const {
                      'Referer': 'https://movie.douban.com/',
                      'User-Agent':
                          'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/122.0.0.0 Mobile Safari/537.36',
                    },
                    width: double.infinity,
                    height: 180,
                    fit: BoxFit.cover,
                    memCacheWidth: 260,
                    memCacheHeight: 360,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    useOldImageOnUrlChange: true,
                    placeholder: (context, url) => Container(
                      width: double.infinity,
                      height: 180,
                      decoration: BoxDecoration(
                        color: AppTokens.inkDark.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: double.infinity,
                      height: 180,
                      decoration: BoxDecoration(
                        color: AppTokens.inkDark.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                      ),
                    ),
                  ),
                ),
                // 排名角标
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: rank <= 3
                          ? const Color(0xFFFFB703)
                          : AppTokens.inkDark.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '#$rank',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: rank <= 3 ? Colors.black : Colors.white,
                      ),
                    ),
                  ),
                ),
                // 评分
                if (item.rate != null)
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB703),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.rate!.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            // 片名
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTokens.textPrimary,
                height: 1.2,
              ),
            ),
            // 导演 · 主演(新接口真实数据);兼容老接口的集数信息
            if (item.subtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTokens.textSecondary,
                  ),
                ),
              )
            else if (item.episodesInfo != null &&
                item.episodesInfo!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  item.episodesInfo!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTokens.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 豆瓣榜单区域(单 Tab: 热门电影 / 热门剧集)。
class DoubanRankingSection extends StatefulWidget {
  const DoubanRankingSection({super.key});

  @override
  State<DoubanRankingSection> createState() => _DoubanRankingSectionState();
}

enum _RankingTab { movies, tv }

/// 类型筛选选项(豆瓣新接口 tags 参数真实支持的值)。
/// null=全部(不传 tags),其余传中文类型标签筛选整个榜单。
const _genres = <MapEntry<String, String?>>[
  MapEntry('全部', null),
  MapEntry('喜剧', '喜剧'),
  MapEntry('爱情', '爱情'),
  MapEntry('科幻', '科幻'),
  MapEntry('动作', '动作'),
  MapEntry('悬疑', '悬疑'),
  MapEntry('动画', '动画'),
  MapEntry('犯罪', '犯罪'),
];

class _DoubanRankingSectionState extends State<DoubanRankingSection>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<DoubanRankingItem> _movies = [];
  List<DoubanRankingItem> _tv = [];
  bool _loading = false;
  String? _error;
  String? _genre; // 当前选中类型(null=全部)

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchAll();
  }

  Future<void> _fetchAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 串行拉取:豆瓣按 IP 限流,并发打 movie+tv 两条会瞬间触发限流
      // (曾导致"切到剧集无数据")。改成一条拉完再拉下一条,规避限流。
      final movies =
          await DoubanRankingService.hotMovies(pageLimit: 10, genre: _genre);
      final tv =
          await DoubanRankingService.hotTvShows(pageLimit: 10, genre: _genre);
      if (!mounted) return;
      setState(() {
        _movies = movies;
        _tv = tv;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '榜单暂不可用';
        _loading = false;
      });
    }
  }

  void _onGenreSelected(String? genre) {
    if (_genre == genre) return;
    setState(() => _genre = genre);
    _fetchAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: const Color(0xFFEDF1F8)),
        boxShadow: AppTokens.shadowSm(),
      ),
      child: Column(
        children: [
          // Tab 头
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded,
                    size: 16, color: AppTokens.primaryBlue),
                const SizedBox(width: 6),
                const Text(
                  '豆瓣热榜',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppTokens.textPrimary,
                  ),
                ),
                const Spacer(),
                _buildTab(_RankingTab.movies, '电影'),
                const SizedBox(width: 2),
                _buildTab(_RankingTab.tv, '剧集'),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // 类型筛选 chips(豆瓣新接口真实支持的 tags 值)
          SizedBox(
            height: 30,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              physics: const BouncingScrollPhysics(),
              itemCount: _genres.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final entry = _genres[index];
                final isActive = _genre == entry.value;
                return InkWell(
                  onTap: () => _onGenreSelected(entry.value),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppTokens.primaryBlue
                          : const Color(0xFFF0F3F8),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight:
                            isActive ? FontWeight.w800 : FontWeight.w600,
                        color: isActive
                            ? Colors.white
                            : AppTokens.textSecondary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          // 内容区
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: AppTokens.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 220,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildListView(_movies),
                  _buildListView(_tv),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  Widget _buildTab(_RankingTab tab, String label) {
    final isActive = tab ==
        (_tabController.index == 0 ? _RankingTab.movies : _RankingTab.tv);
    return InkWell(
      onTap: () => _tabController.animateTo(tab == _RankingTab.movies ? 0 : 1),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
            color: isActive ? AppTokens.primaryBlue : AppTokens.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildListView(List<DoubanRankingItem> items) {
    if (items.isEmpty) {
      return const Center(
        child: Text(
          '暂无数据',
          style: TextStyle(color: AppTokens.textSecondary, fontSize: 12),
        ),
      );
    }
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      physics: const BouncingScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        return _RankingEntry(
          item: item,
          rank: index + 1,
          onTap: () => _onRankingTap(context, item),
        );
      },
    );
  }

  /// 点击榜单条目 → 当前源优先搜索,聚合兜底。
  Future<void> _onRankingTap(BuildContext context, DoubanRankingItem item) async {
    if (!context.mounted) return;
    final controller = Provider.of<VideoController>(context, listen: false);
    final source = controller.currentSource;

    // 1. 当前源优先搜
    if (source != null && source.isAvailable) {
      try {
        final results = await VideoApiService.searchVideo(source.url, item.title);
        if (results.isNotEmpty) {
          if (!context.mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VideoDetailPage(
                source: source,
                vodId: results.first.vodId,
              ),
            ),
          );
          return;
        }
      } catch (_) {
        // 搜不到就继续走兜底
      }
    }

    // 2. 聚合搜索兜底
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AggregateSearchPage(
          prefillKeyword: item.title,
        ),
      ),
    );
  }
}
