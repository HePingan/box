import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:box/daily_news_page.dart';
import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_page_scaffold.dart';
import 'package:box/globals.dart';
import 'package:box/novel/novel_module.dart';
import 'package:box/plugin_manager.dart';
import 'package:box/video_module.dart';
import 'package:box/features/image_generator/presentation/image_generator_page.dart';

import 'widgets/home_widgets.dart';

/// 新闻条目（标题 + 详情链接）
class _NewsItem {
  const _NewsItem({required this.title, this.url});
  final String title;
  final String? url;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.onSwitchTab});

  final ValueChanged<int>? onSwitchTab;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String _todayDateStr = '';
  bool _isLoadingNews = true;
  List<_NewsItem> _newsItems = [];

  @override
  void initState() {
    super.initState();
    _initDate();
    _fetchDailyNews();
    // 确保插件主机初始化，这样插件卡片才能拿到数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      HomePluginHost.instance.bootstrap();
    });
  }

  void _initDate() {
    final now = DateTime.now();
    final hour = now.hour;
    String greeting;
    if (hour < 6) {
      greeting = '夜深了，注意休息';
    } else if (hour < 12) {
      greeting = '早上好，新的一天';
    } else if (hour < 14) {
      greeting = '中午好，吃午饭了吗';
    } else if (hour < 18) {
      greeting = '下午好，继续加油';
    } else {
      greeting = '晚上好，欢迎回来';
    }
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    _todayDateStr = '$month月$day日 · $greeting';
  }

  Future<void> _fetchDailyNews() async {
    setState(() => _isLoadingNews = true);

    try {
      // 同时拉取今日和昨日热点，混合后随机选4条。
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final yesterdayStr =
          '${yesterday.year}${yesterday.month.toString().padLeft(2, '0')}${yesterday.day.toString().padLeft(2, '0')}';
      const newsTimeout = Duration(seconds: 10);

      final results = await Future.wait([
        http
            .get(Uri.parse('https://news-at.zhihu.com/api/4/news/latest'))
            .timeout(newsTimeout),
        http
            .get(
              Uri.parse(
                'https://news-at.zhihu.com/api/4/news/before/$yesterdayStr',
              ),
            )
            .timeout(newsTimeout),
      ]);

      final allItems = <_NewsItem>[];

      for (final resp in results) {
        if (resp.statusCode != 200) continue;
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final stories = data['stories'] as List<dynamic>? ?? [];
        for (final s in stories) {
          final item = s as Map<String, dynamic>;
          final title = item['title'] as String?;
          if (title != null && title.isNotEmpty) {
            allItems.add(_NewsItem(
              title: title,
              url: item['url'] as String?,
            ));
          }
        }
      }

      if (allItems.isEmpty) {
        _newsItems = [const _NewsItem(title: '暂无热点新闻，下拉刷新重试')];
      } else {
        allItems.shuffle();
        _newsItems = allItems.take(4).toList();
      }
    } catch (e) {
      _newsItems = [const _NewsItem(title: '网络异常，请稍后重试')];
    } finally {
      if (mounted) {
        setState(() => _isLoadingNews = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return AppPageScaffold(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildGreetingBar()),
          SliverToBoxAdapter(child: _buildQuickActions()),
          SliverToBoxAdapter(child: _buildPluginSection()),
          SliverToBoxAdapter(child: _buildContinueRail()),
          SliverToBoxAdapter(child: _buildDailyNewsCard()),
          const SliverToBoxAdapter(
            child: SizedBox(height: AppTokens.pageBottomPadding + 24),
          ),
        ],
      ),
    );
  }

  // ── 顶部问候栏（单行紧凑） ─────────────────
  Widget _buildGreetingBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 14, 6),
      child: Row(
        children: [
          IconButton(
            tooltip: '菜单',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            icon: const Icon(
              Icons.menu_rounded,
              color: AppTokens.textSecondary,
              size: 22,
            ),
            onPressed: () => appScaffoldKey.currentState?.openDrawer(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              _todayDateStr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTokens.textPrimary,
                fontSize: 15.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 快捷入口 2×2 网格 ─────────────────────
  Widget _buildQuickActions() {
    final actions = [
      _QuickAction(
        title: '工具',
        subtitle: '效率',
        icon: Icons.handyman_rounded,
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF06B6D4)],
        ),
        onTap: () => _switchToTab(1, '工具'),
      ),
      _QuickAction(
        title: '内容',
        subtitle: '书影',
        icon: Icons.collections_bookmark_rounded,
        gradient: const LinearGradient(
          colors: [Color(0xFF10B981), Color(0xFF06B6D4)],
        ),
        onTap: () => _switchToTab(2, '内容'),
      ),
      _QuickAction(
        title: 'AI 生图',
        subtitle: '多模型生成',
        icon: Icons.auto_awesome_rounded,
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ImageGeneratorPage()),
          );
        },
      ),
      _QuickAction(
        title: '扩展',
        subtitle: '插件市场',
        icon: Icons.tune_rounded,
        gradient: const LinearGradient(
          colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
        ),
        onTap: () => _switchToTab(3, '扩展'),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 2.35,
        children: actions.map((a) => _QuickActionCard(action: a)).toList(),
      ),
    );
  }

  // ── 插件横向滚动卡片 ─────────────────────
  Widget _buildPluginSection() {
    return SafeValueListenableBuilder<List<HomePlugin>>(
      valueListenable: HomePluginHost.instance.listenable,
      builder: (context, plugins, child) {
        final customPlugins = plugins
            .where((p) => !p.builtIn && p.enabled)
            .toList();

        if (customPlugins.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '已安装插件',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                  color: AppTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: customPlugins.length,
                  separatorBuilder: (_, sep) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final plugin = customPlugins[index];
                    return _PluginCard(plugin: plugin);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── 继续上次 ───────────────────────────────
  Widget _buildContinueRail() {
    final items = <HomeContinueItem>[
      HomeContinueItem(
        eyebrow: '继续阅读',
        title: '小说书架',
        subtitle: '查看收藏与最近阅读',
        icon: Icons.menu_book_rounded,
        color: const Color(0xFFF59E0B),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NovelListPageWithProvider()),
          );
        },
      ),
      HomeContinueItem(
        eyebrow: '继续观看',
        title: '影视搜索',
        subtitle: '聚合影片、剧集与播放源',
        icon: Icons.play_circle_fill_rounded,
        color: const Color(0xFF10B981),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const VideoListPage()),
          );
        },
      ),
    ];

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 0, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 14),
            child: Text(
              '继续使用',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w900,
                color: AppTokens.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(right: 14),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) =>
                  HomeContinueCard(item: items[index]),
            ),
          ),
        ],
      ),
    );
  }

  // ── 每日新闻 ───────────────────────────────
  Widget _buildDailyNewsCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE9EEF7)),
          boxShadow: [
            BoxShadow(
              color: AppTokens.ink.withValues(alpha: 0.035),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF8A3D), Color(0xFFFFC857)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.newspaper_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '今日热闻',
                    style: TextStyle(
                      color: AppTokens.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '刷新',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: _fetchDailyNews,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const DailyNewsPage()),
                    );
                  },
                  child: const Text('更多', style: TextStyle(fontSize: 12.5)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_isLoadingNews)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              ..._newsItems.take(3).map(
                    (item) => GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DailyNewsPage(
                              initialUrl: item.url,
                            ),
                          ),
                        );
                      },
                      child: HomeNewsLine(text: item.title),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  void _switchToTab(int index, String label) {
    if (widget.onSwitchTab != null) {
      widget.onSwitchTab!(index);
      return;
    }
    showSnack(context, '请在底部进入「$label』');
  }
}

// ── 快捷入口卡片 ──────────────────────────────
class _QuickAction {
  const _QuickAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Gradient gradient;
  final VoidCallback onTap;
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({required this.action});
  final _QuickAction action;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: action.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            gradient: action.gradient,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: action.gradient.colors.first.withValues(alpha: 0.20),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(action.icon, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      action.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      action.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 已安装插件卡片 ────────────────────────────
class _PluginCard extends StatelessWidget {
  const _PluginCard({required this.plugin});
  final HomePlugin plugin;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => plugin.onTap(context),
      child: Container(
        width: 124,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [plugin.color, plugin.color.withValues(alpha: 0.65)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: plugin.color.withValues(alpha: 0.18),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(plugin.icon, color: Colors.white, size: 15),
            ),
            const SizedBox(height: 6),
            Text(
              plugin.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              plugin.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showSnack(BuildContext context, String text) async {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

// ── 继续上次 ──────────────────────────────────
class HomeContinueItem {
  const HomeContinueItem({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class HomeContinueCard extends StatelessWidget {
  const HomeContinueCard({super.key, required this.item});

  final HomeContinueItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: item.onTap,
      child: Container(
        width: 176,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE7ECF5)),
          boxShadow: [
            BoxShadow(
              color: item.color.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(item.icon, color: item.color, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.eyebrow,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: item.color,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTokens.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTokens.textSecondary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
