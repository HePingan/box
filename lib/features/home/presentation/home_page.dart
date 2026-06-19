import 'dart:math';

import 'package:flutter/material.dart';

import 'package:box/daily_news_page.dart';
import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_page_scaffold.dart';
import 'package:box/globals.dart';
import 'package:box/novel/pages/novel_list_page.dart';
import 'package:box/plugin_manager.dart';
import 'package:box/video_module.dart';
import 'package:box/features/image_generator/presentation/image_generator_page.dart';

import 'widgets/home_widgets.dart';

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
  List<String> _newsList = [];

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
      await Future.delayed(const Duration(milliseconds: 500));
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

  // ── 顶部问候栏 ─────────────────────────────
  Widget _buildGreetingBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: AppTokens.violetGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.home_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _todayDateStr,
                  style: const TextStyle(
                    color: AppTokens.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Geek工具箱 · 今日工作台',
                  style: TextStyle(
                    color: AppTokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '菜单',
            icon: const Icon(
              Icons.menu_rounded,
              color: AppTokens.textSecondary,
            ),
            onPressed: () => appScaffoldKey.currentState?.openDrawer(),
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.6,
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
            .where(
              (p) =>
                  !p.builtIn && p.area == HomePluginArea.recommend && p.enabled,
            )
            .toList();

        if (customPlugins.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '已安装插件',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 110,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: customPlugins.length,
                  separatorBuilder: (_, sep) => const SizedBox(width: 10),
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
            MaterialPageRoute(builder: (_) => NovelListPageWithProvider()),
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
            MaterialPageRoute(builder: (_) => VideoListPage()),
          );
        },
      ),
    ];

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 0, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '继续使用',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppTokens.textPrimary,
                    ),
                  ),
                ),
                HomeMiniPill(label: '继续上次'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(right: 16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE9EEF7)),
          boxShadow: [
            BoxShadow(
              color: AppTokens.ink.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF8A3D), Color(0xFFFFC857)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.newspaper_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '今日热闻',
                    style: TextStyle(
                      color: AppTokens.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '刷新',
                  visualDensity: VisualDensity.compact,
                  onPressed: _fetchDailyNews,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => DailyNewsPage()),
                    );
                  },
                  child: const Text('更多'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (_isLoadingNews)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              ..._newsList.take(3).map((t) => HomeNewsLine(text: t)),
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
        borderRadius: BorderRadius.circular(18),
        onTap: action.onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: action.gradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: action.gradient.colors.first.withValues(alpha: 0.25),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(action.icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      action.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      action.subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white,
                size: 20,
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
      borderRadius: BorderRadius.circular(16),
      onTap: () => plugin.onTap(context),
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [plugin.color, plugin.color.withValues(alpha: 0.65)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: plugin.color.withValues(alpha: 0.20),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(plugin.icon, color: Colors.white, size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              plugin.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              plugin.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 10,
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
      borderRadius: BorderRadius.circular(24),
      onTap: item.onTap,
      child: Container(
        width: 196,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE7ECF5)),
          boxShadow: [
            BoxShadow(
              color: item.color.withValues(alpha: 0.10),
              blurRadius: 14,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(item.icon, color: item.color, size: 22),
            ),
            const SizedBox(width: 10),
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
                      fontSize: 10.5,
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
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    item.subtitle,
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
          ],
        ),
      ),
    );
  }
}
