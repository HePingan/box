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

/// 首页热闻预览条数。
///
/// 此前抓取写 `take(4)`、渲染写 `take(3)`，第 4 条永远抓到又永远不显示。
/// 收敛成一个常量，避免两处再次漂移。想看全部走「更多」进 DailyNewsPage。
const int _homeNewsPreviewCount = 3;

/// 新闻条目（标题 + 详情链接）
class _NewsItem {
  const _NewsItem({required this.title, this.url, this.isPlaceholder = false});
  final String title;
  final String? url;

  /// true 表示这不是真新闻，而是空态/错误态提示文案，不可点击。
  final bool isPlaceholder;
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

  /// 拉取热闻。
  ///
  /// [showSpinner] 为 false 时不切到 loading 态——下拉刷新场景下
  /// RefreshIndicator 自己有转圈，再把列表换成 spinner 会让已有内容闪一下。
  Future<void> _fetchDailyNews({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() => _isLoadingNews = true);
    }

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
        _newsItems = [
          const _NewsItem(title: '暂无热点新闻，下拉刷新重试', isPlaceholder: true),
        ];
      } else {
        allItems.shuffle();
        _newsItems = allItems.take(_homeNewsPreviewCount).toList();
      }
    } catch (e) {
      _newsItems = [
        const _NewsItem(title: '网络异常，请下拉刷新重试', isPlaceholder: true),
      ];
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
      // 兜底文案一直写着「下拉刷新重试」，但此前页面没挂 RefreshIndicator，
      // 用户下拉不会有任何反应。补上，让那句提示名副其实。
      child: RefreshIndicator(
        onRefresh: () => _fetchDailyNews(showSpinner: false),
        color: AppTokens.primaryBlue,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(child: _buildGreetingBar()),
            SliverToBoxAdapter(child: _buildQuickActions()),
            SliverToBoxAdapter(child: _buildPluginSection()),
            SliverToBoxAdapter(child: _buildContinueRail()),
            SliverToBoxAdapter(child: _buildDailyNewsCard()),
            // 底部留白给悬浮胶囊导航栏避让：用真实导航高度 + 系统手势区，
            // 不写死像素，否则不同机型要么留空要么压住最后一条内容。
            SliverToBoxAdapter(
              child: SizedBox(
                height: AppTokens.shellBottomNavHeight +
                    MediaQuery.viewPaddingOf(context).bottom +
                    28,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 统一的分区标题。
  ///
  /// 改版前三个分区各自手写 `Text(fontSize: 14.5, w900)`，
  /// 且「今日热闻」还额外带渐变图标，视觉重量和另两个分区不一致。
  /// 收敛成一个组件：左侧 3px 色条 + 标题 + 可选尾部操作。
  Widget _buildSectionHeader({
    required String title,
    Color accent = AppTokens.primaryBlue,
    List<Widget> actions = const [],
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: AppTokens.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
          ),
          ...actions,
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
      HomeQuickAction(
        title: '工具',
        subtitle: '效率工具箱',
        icon: Icons.handyman_rounded,
        accent: AppTokens.primaryBlue,
        onTap: () => _switchToTab(1, '工具'),
      ),
      HomeQuickAction(
        title: '内容',
        subtitle: '小说与影视',
        icon: Icons.collections_bookmark_rounded,
        accent: AppTokens.emerald,
        onTap: () => _switchToTab(2, '内容'),
      ),
      HomeQuickAction(
        title: 'AI 生图',
        subtitle: '多模型生成',
        icon: Icons.auto_awesome_rounded,
        accent: AppTokens.violet,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ImageGeneratorPage()),
          );
        },
      ),
      HomeQuickAction(
        title: '扩展',
        subtitle: '插件市场',
        icon: Icons.tune_rounded,
        accent: AppTokens.cyan,
        onTap: () => _switchToTab(3, '扩展'),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(title: '快捷入口'),
          // 不用 GridView + childAspectRatio：任何固定/推算的高度都要跟
          // padding、1px 边框、字体缩放和字形度量赛跑，实测差 3~10px 就
          // 触发 RenderFlex overflow 黄条。改成两行 Row + Expanded，
          // 行高由内容自己决定，彻底不需要算高度。
          for (var row = 0; row < actions.length; row += 2) ...[
            if (row > 0) const SizedBox(height: 10),
            // IntrinsicHeight 让同一行两张卡等高（否则文字长短不同会高矮不齐），
            // 高度仍由内容决定，不是我们算出来的。
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: HomeQuickActionCard(action: actions[row])),
                  const SizedBox(width: 10),
                  if (row + 1 < actions.length)
                    Expanded(
                      child: HomeQuickActionCard(action: actions[row + 1]),
                    )
                  else
                    const Expanded(child: SizedBox()),
                ],
              ),
            ),
          ],
        ],
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

        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(
                title: '已安装插件',
                accent: AppTokens.violet,
              ),
              SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.zero,
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
        color: AppTokens.amber,
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
        color: AppTokens.emerald,
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

    return Padding(
      // 右侧不留 padding：让横向列表能滚到屏幕边缘，
      // 视觉上暗示「还有更多可以划」。
      padding: const EdgeInsets.fromLTRB(14, 0, 0, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: _buildSectionHeader(title: '继续使用', accent: AppTokens.amber),
          ),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(right: 14),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行提到卡片外，和「快捷入口 / 已安装插件 / 继续使用」
          // 保持同一套分区标题样式（此前这里是渐变图标 + 卡内标题，重量不一致）。
          _buildSectionHeader(
            title: '今日热闻',
            accent: AppTokens.orange,
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: AppTokens.primaryBlue,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DailyNewsPage()),
                  );
                },
                child: const Text(
                  '更多',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppTokens.surface,
              borderRadius: BorderRadius.circular(AppTokens.radiusCard),
              border: Border.all(color: AppTokens.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isLoadingNews)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else
                  ..._newsItems.asMap().entries.map((entry) {
                    final item = entry.value;
                    final line = HomeNewsLine(
                      text: item.title,
                      // 最后一条不画分隔线，避免卡片底部出现悬空的线。
                      showDivider: entry.key != _newsItems.length - 1,
                      isPlaceholder: item.isPlaceholder,
                    );
                    // 空态/错误态不挂点击：之前它照样可点，会打开一个
                    // initialUrl 为 null 的详情页（死入口）。
                    if (item.isPlaceholder) return line;
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DailyNewsPage(initialUrl: item.url),
                          ),
                        );
                      },
                      child: line,
                    );
                  }),
              ],
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
    // 原文是「$label』——开合引号不成对（「 配 』），是笔误。
    showSnack(context, '请在底部进入「$label」');
  }
}

// ── 快捷入口卡片 ──────────────────────────────
class HomeQuickAction {
  const HomeQuickAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;

  /// 品牌强调色。只用于图标底片和图标本身，不铺满整卡。
  final Color accent;
  final VoidCallback onTap;
}

/// 快捷入口卡片。
///
/// 改版原因：原设计四张卡各自铺满饱和渐变 + 彩色投影，2×2 排在首屏
/// 顶部会盖过下方「已安装插件 / 继续使用 / 今日热闻」的真实内容，
/// 视觉层级是倒挂的。现在改成白底卡 + 描边 + 彩色图标底片，
/// 颜色只做「区分」不做「抢眼」，标题恢复深色文字提升可读性。
class HomeQuickActionCard extends StatelessWidget {
  const HomeQuickActionCard({super.key, required this.action});
  final HomeQuickAction action;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTokens.surface,
      borderRadius: BorderRadius.circular(AppTokens.radiusCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        onTap: action.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusCard),
            border: Border.all(color: AppTokens.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: action.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTokens.radiusChip),
                ),
                child: Icon(action.icon, color: action.accent, size: 18),
              ),
              const SizedBox(width: 10),
              // Flexible 而不是 Expanded：格子宽度已由 GridView 定死，
              // 用 Flexible 让文字列在窄屏时能收缩而不是强撑溢出。
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  // 只占内容所需高度。父级给的高度若略小于两行文字，
                  // 不加这行会直接报 RenderFlex overflow（实测差 4px 就炸）。
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      action.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTokens.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      action.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTokens.textTertiary,
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
      ),
    );
  }
}

// ── 已安装插件卡片 ────────────────────────────
/// 已安装插件卡片。
///
/// 和 HomeQuickActionCard 一起从「铺满渐变」改成白底 + 描边 + 彩色图标底片：
/// 插件颜色是用户/作者定的，铺满整卡时四五张排一行会花掉整个首屏，
/// 而且白字压在浅色插件主题色上对比度不够。
class _PluginCard extends StatelessWidget {
  const _PluginCard({required this.plugin});
  final HomePlugin plugin;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.radiusCard),
      onTap: () => plugin.onTap(context),
      child: Container(
        width: 132,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTokens.surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          border: Border.all(color: AppTokens.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: plugin.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppTokens.radiusChip),
              ),
              child: Icon(plugin.icon, color: plugin.color, size: 17),
            ),
            const SizedBox(height: 8),
            Text(
              plugin.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTokens.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              plugin.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTokens.textTertiary,
                fontSize: 10.5,
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
      borderRadius: BorderRadius.circular(AppTokens.radiusCard),
      onTap: item.onTap,
      // 宽度按内容自适应而不是死钉 176：
      // 176 时「聚合影片、剧集与播放源」这类副标题会被 ellipsis 截成
      // 「聚合影片、剧集与播…」（真机截图证实）。这里给一个区间：
      // 下限保证多张卡时视觉整齐，上限防止单条超长文案把卡拉过屏宽。
      // 仍在横向 ListView 里，卡多了照旧可以滑。
      child: Container(
        constraints: const BoxConstraints(minWidth: 176, maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTokens.surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          border: Border.all(color: AppTokens.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppTokens.radiusChip),
              ),
              child: Icon(item.icon, color: item.color, size: 18),
            ),
            const SizedBox(width: 10),
            // 用 Flexible 而不是 Expanded：Expanded 会强制占满父级最大宽度，
            // 让上面的 maxWidth 变成"总是最宽"，文字照旧按最宽算再截断。
            // Flexible 允许 Row 收缩到内容宽度，同时在超过 maxWidth 时
            // 仍然让文字让位（ellipsis 兜底），不会溢出。
            Flexible(
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
