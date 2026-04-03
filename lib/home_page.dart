import 'dart:math';

import 'package:flutter/material.dart';

import 'daily_news_page.dart';
import 'globals.dart';
import 'novel_module.dart';
import 'plugin_manager.dart';
import 'video_module.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

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
  List<String> _newsList = [];

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
      await Future.delayed(const Duration(milliseconds: 1200));
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
      body: DefaultTabController(
        length: 4,
        child: SafeArea(
          child: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return <Widget>[
                SliverToBoxAdapter(child: _buildTopHeader()),
                SliverToBoxAdapter(child: _buildDailyNewsCard()),
                SliverToBoxAdapter(child: _buildQuickActions()),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SliverAppBarDelegate(_buildTabBar()),
                ),
              ];
            },
            body: TabBarView(
              children: [
                _buildRecommendGrid(),
                _buildMusicGrid(),
                _buildVideoTab(),
                _buildComicGrid(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TabBar _buildTabBar() {
    return TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      indicatorColor: Colors.blue[700],
      indicatorSize: TabBarIndicatorSize.label,
      indicatorWeight: 3.0,
      labelColor: Colors.blue[700],
      unselectedLabelColor: Colors.black54,
      dividerColor: Colors.grey[300],
      tabs: const [
        Tab(
          child: Row(
            children: [
              Icon(Icons.local_fire_department_outlined, size: 20),
              SizedBox(width: 4),
              Text(
                '推荐',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        Tab(
          child: Row(
            children: [
              Icon(Icons.music_note_outlined, size: 20),
              SizedBox(width: 4),
              Text('音乐', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
        Tab(
          child: Row(
            children: [
              Icon(Icons.play_circle_outline, size: 20),
              SizedBox(width: 4),
              Text('影视', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
        Tab(
          child: Row(
            children: [
              Icon(Icons.image_outlined, size: 20),
              SizedBox(width: 4),
              Text('漫画', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => appScaffoldKey.currentState?.openDrawer(),
            child: const Icon(Icons.menu, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Geek工具箱',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '计划赶不上变化😭',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 24),
            onPressed: _fetchDailyNews,
            tooltip: '刷新日报',
          ),
        ],
      ),
    );
  }

  Widget _buildDailyNewsCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFF2C3228),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '视界日报',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Daily News - $_todayDateStr',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                if (_isLoadingNews)
                  const Padding(
                    padding: EdgeInsets.only(top: 20.0),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white70,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  )
                else
                  ..._newsList.take(3).map(
                        (newsText) => Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.radio_button_checked,
                                color: Colors.white70,
                                size: 14,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Tooltip(
                                  message: newsText,
                                  child: Text(
                                    newsText,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ],
            ),
          ),
          Positioned(
            top: -8,
            right: -8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '刷新',
                  icon: const Icon(
                    Icons.refresh,
                    color: Colors.white70,
                    size: 20,
                  ),
                  onPressed: _fetchDailyNews,
                ),
                IconButton(
                  tooltip: '查看详情',
                  icon: const Icon(
                    Icons.remove_red_eye_outlined,
                    color: Colors.white70,
                    size: 20,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => DailyNewsPage()),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    final actions = <_HomeQuickAction>[
      _HomeQuickAction(
        title: '小说',
        icon: Icons.menu_book_outlined,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => NovelListPage()),
          );
        },
      ),
      _HomeQuickAction(
        title: '仓库',
        icon: Icons.inventory_2_outlined,
        onTap: () => _showSnack(context, '请在底部进入仓库查看收藏'),
      ),
      _HomeQuickAction(
        title: '插件',
        icon: Icons.extension_outlined,
        onTap: () => _showSnack(context, '请在底部进入插件中心'),
      ),
      _HomeQuickAction(
        title: '影视搜索',
        icon: Icons.video_collection_outlined,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => VideoListPage()),
          );
        },
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
      child: Row(
        children: actions.map((action) {
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: action.onTap,
              child: Container(
                height: 68,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(action.icon, size: 20, color: Colors.blueGrey),
                    const SizedBox(height: 6),
                    Text(
                      action.title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRecommendGrid() {
    final items = <_GridCardItem>[
      _GridCardItem(
        id: 'recommend_sniff',
        title: '资源嗅探',
        sub: '嗅探网页中的\n音视图片等资源',
        icon: Icons.travel_explore_outlined,
        color: Colors.amber,
        onTap: (ctx) => _showSnack(ctx, '资源嗅探开发中...'),
      ),
      _GridCardItem(
        id: 'recommend_apps',
        title: '应用中心',
        sub: '海量实用软件\n游戏下载工具集',
        icon: Icons.apps_outlined,
        color: Colors.blue,
        onTap: (ctx) => _showSnack(ctx, '应用中心开发中...'),
      ),
      _GridCardItem(
        id: 'recommend_game',
        title: '怀旧游戏',
        sub: '街机、FC等\n童年怀旧游戏',
        icon: Icons.sports_esports_outlined,
        color: Colors.blue.shade700,
        onTap: (ctx) => _showSnack(ctx, '怀旧游戏开发中...'),
      ),
      _GridCardItem(
        id: 'recommend_video_parse',
        title: '短视频解析',
        sub: '短视频工具\n（需合法使用）',
        icon: Icons.downloading_outlined,
        color: Colors.lightGreen,
        onTap: (ctx) => _showSnack(ctx, '短视频解析开发中...'),
      ),
    ];

    return _buildTabGridWithPlugins(
      area: HomePluginArea.recommend,
      baseItems: items,
      emptyTip: '推荐功能开发中...',
    );
  }

  Widget _buildMusicGrid() {
    final items = <_GridCardItem>[
      _GridCardItem(
        id: 'music_search',
        title: '音乐搜索',
        sub: '搜索公开音乐资源',
        icon: Icons.search,
        color: Colors.purple,
        onTap: (ctx) => _showSnack(ctx, '音乐搜索开发中...'),
      ),
      _GridCardItem(
        id: 'music_playlist',
        title: '歌单管理',
        sub: '收藏、创建、导入歌单',
        icon: Icons.playlist_play,
        color: Colors.pink,
        onTap: (ctx) => _showSnack(ctx, '歌单管理开发中...'),
      ),
    ];

    return _buildTabGridWithPlugins(
      area: HomePluginArea.music,
      baseItems: items,
      emptyTip: '音乐功能区开发中...',
    );
  }

  Widget _buildComicGrid() {
    final items = <_GridCardItem>[
      _GridCardItem(
        id: 'comic_rank',
        title: '漫画排行',
        sub: '热门漫画榜单',
        icon: Icons.emoji_emotions_outlined,
        color: Colors.teal,
        onTap: (ctx) => _showSnack(ctx, '漫画排行开发中...'),
      ),
      _GridCardItem(
        id: 'comic_search',
        title: '漫画搜索',
        sub: '按关键词检索漫画',
        icon: Icons.manage_search_outlined,
        color: Colors.green,
        onTap: (ctx) => _showSnack(ctx, '漫画搜索开发中...'),
      ),
    ];

    return _buildTabGridWithPlugins(
      area: HomePluginArea.comic,
      baseItems: items,
      emptyTip: '漫画功能区开发中...',
    );
  }

  Widget _buildVideoTab() {
    return ValueListenableBuilder<List<HomePlugin>>(
      valueListenable: _pluginHost.listenable,
      builder: (context, _, __) {
        final videoPlugins = _pluginHost.pluginsOf(HomePluginArea.video);

        if (videoPlugins.isEmpty) {
          return VideoHomePage();
        }

        return Column(
          children: [
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                itemCount: videoPlugins.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final plugin = videoPlugins[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () async {
                      try {
                        await plugin.onTap(context);
                      } catch (e) {
                        await _showSnack(context, '插件执行失败: $e');
                      }
                    },
                    child: Container(
                      width: 170,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: plugin.color.withOpacity(0.15),
                            child: Icon(plugin.icon, color: plugin.color),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  plugin.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  plugin.subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Expanded(child: VideoHomePage()),
          ],
        );
      },
    );
  }

  Widget _buildTabGridWithPlugins({
    required HomePluginArea area,
    required List<_GridCardItem> baseItems,
    required String emptyTip,
  }) {
    return ValueListenableBuilder<List<HomePlugin>>(
      valueListenable: _pluginHost.listenable,
      builder: (context, _, __) {
        final pluginItems = _pluginHost
            .pluginsOf(area)
            .map(_GridCardItem.fromPlugin)
            .toList();

        final merged = <String, _GridCardItem>{};
        for (final item in baseItems) {
          merged[item.id] = item;
        }
        for (final item in pluginItems) {
          merged[item.id] = item;
        }

        final all = merged.values.toList();

        if (all.isEmpty) {
          return Center(
            child: Text(
              emptyTip,
              style: TextStyle(color: Colors.grey[600]),
            ),
          );
        }

        return _buildGridView(all);
      },
    );
  }

  Widget _buildGridView(List<_GridCardItem> items) {
    return GridView.builder(
      padding: const EdgeInsets.all(16.0),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12.0,
        mainAxisSpacing: 12.0,
        childAspectRatio: 2.1,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return InkWell(
          borderRadius: BorderRadius.circular(16.0),
          onTap: () async {
            if (item.onTap != null) {
              await item.onTap!(context);
            }
          },
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFEDEEF0),
              borderRadius: BorderRadius.circular(16.0),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 12,
                  top: 12,
                  right: 52,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.sub,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: item.color,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        item.icon,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GridCardItem {
  final String id;
  final String title;
  final String sub;
  final IconData icon;
  final Color color;
  final HomePluginTap? onTap;

  const _GridCardItem({
    required this.id,
    required this.title,
    required this.sub,
    required this.icon,
    required this.color,
    this.onTap,
  });

  factory _GridCardItem.fromPlugin(HomePlugin plugin) {
    return _GridCardItem(
      id: plugin.id,
      title: plugin.title,
      sub: plugin.subtitle,
      icon: plugin.icon,
      color: plugin.color,
      onTap: plugin.onTap,
    );
  }
}

class _HomeQuickAction {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _HomeQuickAction({
    required this.title,
    required this.icon,
    required this.onTap,
  });
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;

  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: const Color(0xFFF7F8FA),
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => false;
}

Future<void> _showSnack(BuildContext context, String text) async {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text)),
  );
}