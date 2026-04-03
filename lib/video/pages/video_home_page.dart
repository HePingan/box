import 'package:flutter/material.dart';

import '../core/models.dart';
import '../video_module.dart';
import 'video_list_page.dart';

class VideoHomePage extends StatefulWidget {
  const VideoHomePage({super.key});

  @override
  State<VideoHomePage> createState() => _VideoHomePageState();
}

class _VideoHomePageState extends State<VideoHomePage> {
  final TextEditingController _searchController = TextEditingController();

  List<VideoCategory> _categories = const [];

  @override
  void initState() {
    super.initState();
    _reloadCategories();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reloadCategories() {
    final raw = VideoModule.repository.source.categories;
    setState(() {
      _categories = _dedupeCategories(raw);
    });
  }

  List<VideoCategory> _dedupeCategories(List<VideoCategory> raw) {
    final map = <String, VideoCategory>{};
    for (final item in raw) {
      final key = '${item.title.trim()}|${item.query.trim()}';
      map.putIfAbsent(key, () => item);
    }
    return map.values.toList();
  }

  List<VideoCategory> get _featuredCategories {
    final matched = <VideoCategory>[];
    final used = <String>{};

    void pick(bool Function(VideoCategory c) test) {
      for (final category in _categories) {
        final key = '${category.title}|${category.query}';
        if (used.contains(key)) continue;
        if (test(category)) {
          matched.add(category);
          used.add(key);
          return;
        }
      }
    }

    bool containsAny(VideoCategory c, List<String> words) {
      final text = '${c.title} ${c.description}'.toLowerCase();
      return words.any((e) => text.contains(e.toLowerCase()));
    }

    pick((c) => containsAny(c, ['最新', '推荐', '首页', '最近', '全部']));
    pick((c) => containsAny(c, ['电影', 'movie']));
    pick((c) => containsAny(c, ['电视剧', '剧集', '连续剧', 'tv']));
    pick((c) => containsAny(c, ['动漫', '动画', '番剧', 'anime']));
    pick((c) => containsAny(c, ['综艺', 'variety']));
    pick((c) => containsAny(c, ['短剧', '微短剧', '竖屏', '爽剧']));

    if (matched.length < 6) {
      for (final category in _categories) {
        final key = '${category.title}|${category.query}';
        if (used.add(key)) {
          matched.add(category);
          if (matched.length >= 6) break;
        }
      }
    }

    return matched;
  }

  List<String> get _hotKeywords => const [
        '短剧',
        '热播电视剧',
        '动漫',
        '综艺',
        '动作电影',
        '悬疑',
        '古装',
        '喜剧',
      ];

  void _openSearch([String? keyword]) {
    final text = (keyword ?? _searchController.text).trim();
    if (text.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoListPage(
          initialKeyword: text,
        ),
      ),
    );
  }

  void _openCategory(VideoCategory category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoListPage(category: category),
      ),
    );
  }

  Widget _buildHeroHeader() {
    final sourceName = VideoModule.repository.source.sourceName;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF2D5EA8),
            const Color(0xFF4B7BC8),
            const Color(0xFF6B96D8),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '影视聚合',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '当前片源：$sourceName',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _openSearch(),
              decoration: InputDecoration(
                hintText: '搜电影、电视剧、动漫、综艺、短剧',
                border: InputBorder.none,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: _openSearch,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _hotKeywords.map((word) {
              return InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => _openSearch(word),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.14),
                    ),
                  ),
                  child: Text(
                    word,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(String title) {
    final text = title.toLowerCase();
    if (text.contains('电影')) return Icons.movie_creation_outlined;
    if (text.contains('电视剧') || text.contains('剧')) return Icons.live_tv_outlined;
    if (text.contains('动漫') || text.contains('动画') || text.contains('番')) {
      return Icons.animation_outlined;
    }
    if (text.contains('综艺')) return Icons.theaters_outlined;
    if (text.contains('短剧') || text.contains('微短剧') || text.contains('竖屏')) {
      return Icons.stay_current_portrait_outlined;
    }
    if (text.contains('最新') || text.contains('推荐') || text.contains('首页')) {
      return Icons.auto_awesome_outlined;
    }
    return Icons.grid_view_rounded;
  }

  List<Color> _categoryColors(String title) {
    final text = title.toLowerCase();
    if (text.contains('电影')) return [const Color(0xFFFF8A65), const Color(0xFFFFB74D)];
    if (text.contains('电视剧') || text.contains('剧')) {
      return [const Color(0xFF42A5F5), const Color(0xFF7E57C2)];
    }
    if (text.contains('动漫') || text.contains('动画') || text.contains('番')) {
      return [const Color(0xFF26A69A), const Color(0xFF66BB6A)];
    }
    if (text.contains('综艺')) return [const Color(0xFFEC407A), const Color(0xFFAB47BC)];
    if (text.contains('短剧') || text.contains('微短剧') || text.contains('竖屏')) {
      return [const Color(0xFF5C6BC0), const Color(0xFF29B6F6)];
    }
    return [const Color(0xFF607D8B), const Color(0xFF90A4AE)];
  }

  Widget _buildFeaturedGrid() {
    final items = _featuredCategories;
    if (items.isEmpty) return const SizedBox.shrink();

    return GridView.builder(
      itemCount: items.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.55,
      ),
      itemBuilder: (context, index) {
        final category = items[index];
        final colors = _categoryColors(category.title);

        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openCategory(category),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _categoryIcon(category.title),
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      category.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String title, {String? subtitle}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSourceInfoCard() {
    final source = VideoModule.repository.source;
    final categories = _categories;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4ECF8)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: Color(0xFFEAF2FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.hub_outlined,
              color: Color(0xFF3567B7),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.sourceName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '当前共 ${categories.length} 个可浏览分类，支持多源搜索与自动聚合',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _reloadCategories,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新分类',
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryWrap() {
    if (_categories.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FB),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text('当前没有可用分类'),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _categories.map((category) {
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openCategory(category),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFEEF1F4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _categoryIcon(category.title),
                  size: 16,
                  color: const Color(0xFF5471A8),
                ),
                const SizedBox(width: 8),
                Text(
                  category.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildQuickSearchPanel() {
    const suggestions = <String>[
      '最新短剧',
      '古装',
      '悬疑',
      '喜剧',
      '动作',
      '爱情',
      '动漫新番',
      '热播综艺',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FBFD),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '快速搜索',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: suggestions.map((word) {
              return ActionChip(
                label: Text(word),
                onPressed: () => _openSearch(word),
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                  side: const BorderSide(color: Color(0xFFE6EBF2)),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: const Text('影视'),
        centerTitle: false,
        actions: [
          IconButton(
            onPressed: _reloadCategories,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reloadCategories(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            _buildHeroHeader(),
            const SizedBox(height: 18),
            _buildSourceInfoCard(),
            const SizedBox(height: 24),
            _sectionTitle('快捷入口', subtitle: '常用分类优先展示'),
            const SizedBox(height: 14),
            _buildFeaturedGrid(),
            const SizedBox(height: 24),
            _buildQuickSearchPanel(),
            const SizedBox(height: 24),
            _sectionTitle('全部分类', subtitle: '点击进入聚合列表浏览'),
            const SizedBox(height: 14),
            _buildCategoryWrap(),
          ],
        ),
      ),
    );
  }
}