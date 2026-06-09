import 'dart:math';

import 'package:flutter/material.dart';

import 'package:box/daily_news_page.dart';
import 'package:box/design_system/app_tokens.dart';
import 'package:box/globals.dart';
import 'package:box/novel/pages/novel_list_page.dart';
import 'package:box/plugin_manager.dart';
import 'package:box/video_module.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.onSwitchTab});

  final ValueChanged<int>? onSwitchTab;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin {
  final HomePluginHost _pluginHost = HomePluginHost.instance;

  @override
  bool get wantKeepAlive => true;

  String _todayDateStr = '';
  bool _isLoadingNews = true;
  int _selectedCategory = 0;
  List<String> _newsList = [];

  static const List<_CategoryTab> _categories = [
    _CategoryTab('推荐', Icons.auto_awesome_rounded, HomePluginArea.recommend),
    _CategoryTab('音乐', Icons.graphic_eq_rounded, HomePluginArea.music),
    _CategoryTab('影视', Icons.movie_filter_rounded, HomePluginArea.video),
    _CategoryTab('漫画', Icons.palette_rounded, HomePluginArea.comic),
  ];

  @override
  void initState() {
    super.initState();
    _pluginHost.bootstrap();
    _initDate();
    _fetchDailyNews();
  }

  void _initDate() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    _todayDateStr = '$month月$day日';
  }

  Future<void> _fetchDailyNews() async {
    setState(() => _isLoadingNews = true);

    try {
      await Future.delayed(const Duration(milliseconds: 700));
      final random = Random().nextInt(100);
      _newsList = [
        '漂白鸡爪掀行业震荡 多品牌回应',
        '商务部回应美方对华发起301调查',
        '又被曝！曼玲粥铺被扒“糊弄式”堂食',
        '编号：$random 备用内容',
      ];
    } catch (_) {
      _newsList = ['网络加载失败，请稍后重试'];
    } finally {
      if (mounted) {
        setState(() => _isLoadingNews = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildHeroHeader()),
            SliverToBoxAdapter(child: _buildQuickDock()),
            SliverToBoxAdapter(child: _buildDailyNewsCard()),
            SliverToBoxAdapter(child: _buildCategorySwitcher()),
            ValueListenableBuilder<List<HomePlugin>>(
              valueListenable: _pluginHost.listenable,
              builder: (context, _, _) => _buildFeatureSliver(),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: AppTokens.pageBottomPadding + 28),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1455D9), Color(0xFF36C2FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1455D9).withValues(alpha: 0.28),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _GlassIconButton(
                icon: Icons.menu_rounded,
                onTap: () => appScaffoldKey.currentState?.openDrawer(),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      size: 15,
                      color: Color(0xFFFFE08A),
                    ),
                    SizedBox(width: 4),
                    Text(
                      '4-TAB HUB 2.0',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _GlassIconButton(
                icon: Icons.refresh_rounded,
                onTap: _fetchDailyNews,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.view_carousel_rounded,
                  size: 18,
                  color: Colors.white,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'B2-A：四页导航 · 手机首屏压缩版',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 11),
          const Text(
            '四页工作台',
            style: TextStyle(
              color: Colors.white,
              fontSize: 25,
              height: 1.05,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '首页 / 工具 / 内容 / 扩展，首屏更短。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.84),
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _switchToTab(int index, String label) {
    if (widget.onSwitchTab != null) {
      widget.onSwitchTab!(index);
      return;
    }
    _showSnack(context, '请在底部进入「$label」');
  }

  Widget _buildDailyNewsCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE7ECF5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.055),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF7A45), Color(0xFFFFC53D)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.newspaper_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '视界日报',
                      style: TextStyle(
                        color: AppTokens.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'Daily News · $_todayDateStr',
                      style: const TextStyle(
                        color: AppTokens.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: '刷新',
                onPressed: _fetchDailyNews,
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton.filledTonal(
                tooltip: '查看详情',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => DailyNewsPage()),
                  );
                },
                icon: const Icon(Icons.visibility_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoadingNews)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            )
          else
            ..._newsList.take(2).map((newsText) => _NewsLine(text: newsText)),
        ],
      ),
    );
  }

  Widget _buildQuickDock() {
    final actions = <_HomeQuickAction>[
      _HomeQuickAction(
        title: '工具工作台',
        subtitle: 'TOOLS STUDIO',
        icon: Icons.manage_search_rounded,
        color: const Color(0xFF2563EB),
        onTap: () => _switchToTab(1, '工具'),
      ),
      _HomeQuickAction(
        title: '内容入口',
        subtitle: '影视 / 小说 / 收藏',
        icon: Icons.smart_display_rounded,
        color: const Color(0xFF10B981),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => VideoListPage()),
          );
        },
      ),
      _HomeQuickAction(
        title: '小说书架',
        subtitle: '阅读 / 书源 / 收藏',
        icon: Icons.menu_book_rounded,
        color: const Color(0xFFF59E0B),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => NovelListPageWithProvider()),
          );
        },
      ),
      _HomeQuickAction(
        title: '扩展控制台',
        subtitle: '插件 / 规则 / 备份',
        icon: Icons.extension_rounded,
        color: const Color(0xFF8B5CF6),
        onTap: () => _switchToTab(3, '扩展'),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  '快捷入口',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppTokens.textPrimary,
                  ),
                ),
              ),
              _MiniPill(label: '4 个主入口'),
            ],
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: actions.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.72,
            ),
            itemBuilder: (context, index) =>
                _QuickDockCard(action: actions[index]),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySwitcher() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text(
                '探索更多',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppTokens.textPrimary,
                ),
              ),
              Spacer(),
              Text(
                '第二屏功能区',
                style: TextStyle(
                  color: AppTokens.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final tab = _categories[index];
                final selected = index == _selectedCategory;
                return ChoiceChip(
                  selected: selected,
                  showCheckmark: false,
                  avatar: Icon(
                    tab.icon,
                    size: 18,
                    color: selected ? Colors.white : AppTokens.textSecondary,
                  ),
                  label: Text(tab.label),
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : AppTokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                  selectedColor: AppTokens.seed,
                  backgroundColor: Colors.white,
                  side: BorderSide(
                    color: selected ? AppTokens.seed : const Color(0xFFE3E8F2),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  onSelected: (_) => setState(() => _selectedCategory = index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureSliver() {
    final tab = _categories[_selectedCategory];
    final items = _featureItemsFor(tab.area);
    final pluginItems = _pluginHost
        .pluginsOf(tab.area)
        .map(_FeatureCardItem.fromPlugin)
        .toList();
    final merged = <String, _FeatureCardItem>{};
    for (final item in items) {
      merged[item.id] = item;
    }
    for (final item in pluginItems) {
      merged[item.id] = item;
    }
    final all = merged.values.toList();

    if (tab.area == HomePluginArea.video && pluginItems.isEmpty) {
      return SliverToBoxAdapter(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          height: 420,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFE7ECF5)),
          ),
          child: VideoHomePage(),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid.builder(
        itemCount: all.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.08,
        ),
        itemBuilder: (context, index) => _FeatureCard(item: all[index]),
      ),
    );
  }

  List<_FeatureCardItem> _featureItemsFor(HomePluginArea area) {
    switch (area) {
      case HomePluginArea.recommend:
        return [
          _FeatureCardItem(
            id: 'recommend_sniff',
            title: '资源嗅探',
            subtitle: '自动识别网页里的音视频与图片资源',
            icon: Icons.travel_explore_rounded,
            gradient: const [Color(0xFF2563EB), Color(0xFF38BDF8)],
            status: '开发中',
            onTap: (ctx) => _showSnack(ctx, '资源嗅探开发中...'),
          ),
          _FeatureCardItem(
            id: 'recommend_apps',
            title: '应用中心',
            subtitle: '实用软件、游戏工具与常用下载合集',
            icon: Icons.apps_rounded,
            gradient: const [Color(0xFF7C3AED), Color(0xFFC084FC)],
            status: '开发中',
            onTap: (ctx) => _showSnack(ctx, '应用中心开发中...'),
          ),
          _FeatureCardItem(
            id: 'recommend_game',
            title: '怀旧游戏',
            subtitle: '街机、FC 与童年经典入口',
            icon: Icons.sports_esports_rounded,
            gradient: const [Color(0xFFF97316), Color(0xFFFACC15)],
            status: '开发中',
            onTap: (ctx) => _showSnack(ctx, '怀旧游戏开发中...'),
          ),
          _FeatureCardItem(
            id: 'recommend_video_parse',
            title: '短视频解析',
            subtitle: '短视频工具箱，需合法合规使用',
            icon: Icons.downloading_rounded,
            gradient: const [Color(0xFF059669), Color(0xFF34D399)],
            status: '开发中',
            onTap: (ctx) => _showSnack(ctx, '短视频解析开发中...'),
          ),
        ];
      case HomePluginArea.music:
        return [
          _FeatureCardItem(
            id: 'music_search',
            title: '音乐搜索',
            subtitle: '搜索公开音乐资源与灵感歌单',
            icon: Icons.search_rounded,
            gradient: const [Color(0xFFDB2777), Color(0xFFF9A8D4)],
            status: '开发中',
            onTap: (ctx) => _showSnack(ctx, '音乐搜索开发中...'),
          ),
          _FeatureCardItem(
            id: 'music_playlist',
            title: '歌单管理',
            subtitle: '收藏、创建、导入歌单',
            icon: Icons.playlist_play_rounded,
            gradient: const [Color(0xFF9333EA), Color(0xFFA5B4FC)],
            status: '开发中',
            onTap: (ctx) => _showSnack(ctx, '歌单管理开发中...'),
          ),
        ];
      case HomePluginArea.video:
        return [
          _FeatureCardItem(
            id: 'video_search',
            title: '影视搜索',
            subtitle: '聚合搜索影片、剧集与播放源',
            icon: Icons.movie_filter_rounded,
            gradient: const [Color(0xFF0F766E), Color(0xFF22D3EE)],
            status: '可用',
            onTap: (ctx) async {
              Navigator.push(
                ctx,
                MaterialPageRoute(builder: (_) => VideoListPage()),
              );
            },
          ),
        ];
      case HomePluginArea.comic:
        return [
          _FeatureCardItem(
            id: 'comic_rank',
            title: '漫画排行',
            subtitle: '热门漫画榜单与推荐',
            icon: Icons.emoji_emotions_rounded,
            gradient: const [Color(0xFFEA580C), Color(0xFFFDBA74)],
            status: '开发中',
            onTap: (ctx) => _showSnack(ctx, '漫画排行开发中...'),
          ),
          _FeatureCardItem(
            id: 'comic_search',
            title: '漫画搜索',
            subtitle: '按关键词检索漫画内容',
            icon: Icons.manage_search_rounded,
            gradient: const [Color(0xFF16A34A), Color(0xFF86EFAC)],
            status: '开发中',
            onTap: (ctx) => _showSnack(ctx, '漫画搜索开发中...'),
          ),
        ];
      case HomePluginArea.novel:
      case HomePluginArea.center:
        return const [];
    }
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }
}

class _NewsLine extends StatelessWidget {
  const _NewsLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FD),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.fiber_manual_record_rounded,
            color: Color(0xFF3D7CFF),
            size: 10,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  const _MiniPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppTokens.primaryBlue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppTokens.primaryBlue.withValues(alpha: 0.16),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppTokens.primaryBlue,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _QuickDockCard extends StatelessWidget {
  const _QuickDockCard({required this.action});

  final _HomeQuickAction action;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: action.onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE7ECF5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.045),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: action.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(action.icon, color: action.color, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              action.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTokens.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              action.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTokens.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.item});

  final _FeatureCardItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: () async {
        if (item.onTap != null) {
          await item.onTap!(context);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: item.gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: item.gradient.first.withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -16,
              bottom: -18,
              child: Icon(
                item.icon,
                color: Colors.white.withValues(alpha: 0.18),
                size: 92,
              ),
            ),
            if (item.status != null)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Text(
                    item.status!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Icon(item.icon, color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 11,
                    height: 1.18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureCardItem {
  const _FeatureCardItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    this.status,
    this.onTap,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final String? status;
  final HomePluginTap? onTap;

  factory _FeatureCardItem.fromPlugin(HomePlugin plugin) {
    return _FeatureCardItem(
      id: plugin.id,
      title: plugin.title,
      subtitle: plugin.subtitle,
      icon: plugin.icon,
      gradient: [plugin.color, plugin.color.withValues(alpha: 0.68)],
      status: '插件',
      onTap: plugin.onTap,
    );
  }
}

class _HomeQuickAction {
  const _HomeQuickAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _CategoryTab {
  const _CategoryTab(this.label, this.icon, this.area);

  final String label;
  final IconData icon;
  final HomePluginArea area;
}

Future<void> _showSnack(BuildContext context, String text) async {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
