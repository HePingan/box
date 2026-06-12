import 'dart:math';

import 'package:flutter/material.dart';

import 'package:box/daily_news_page.dart';
import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_cards.dart';
import 'package:box/design_system/widgets/app_page_scaffold.dart';
import 'package:box/features/api_hub/presentation/api_hub_page.dart';
import 'package:box/globals.dart';
import 'package:box/novel/pages/novel_list_page.dart';
import 'package:box/video_module.dart';

import '../application/home_models.dart';
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

    return AppPageScaffold(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildHeroHeader()),
          SliverToBoxAdapter(child: _buildDailyNewsCard()),
          SliverToBoxAdapter(child: _buildContinueRail()),
          SliverToBoxAdapter(child: _buildTodayApiCard()),
          SliverToBoxAdapter(child: _buildCommonEntryStrip()),
          const SliverToBoxAdapter(
            child: SizedBox(height: AppTokens.pageBottomPadding + 24),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroHeader() {
    return AppLightHeroCard(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      eyebrow: '晚上好，欢迎回来',
      title: '今日工作台',
      subtitle: '继续阅读、追剧和管理资源',
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      badge: '4-TAB HUB',
      accentGradient: AppTokens.violetGradient,
      leading: _HomeSoftIconButton(
        icon: Icons.menu_rounded,
        onTap: () => appScaffoldKey.currentState?.openDrawer(),
      ),
      metrics: const [
        Expanded(
          child: _HomeHeroMetric(value: '12', label: '书架'),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _HomeHeroMetric(value: '8', label: '插件'),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _HomeHeroMetric(value: '2', label: '今日'),
        ),
      ],
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
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE9EEF7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF8A3D), Color(0xFFFFC857)],
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.newspaper_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '今天看什么',
                      style: TextStyle(
                        color: AppTokens.textPrimary,
                        fontSize: 17,
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
              IconButton(
                tooltip: '刷新',
                visualDensity: VisualDensity.compact,
                onPressed: _fetchDailyNews,
                icon: const Icon(Icons.refresh_rounded),
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => DailyNewsPage()),
                  );
                },
                child: const Text('查看'),
              ),
            ],
          ),
          const SizedBox(height: 7),
          if (_isLoadingNews)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            )
          else
            ..._newsList
                .take(3)
                .map((newsText) => HomeNewsLine(text: newsText)),
        ],
      ),
    );
  }

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
      HomeContinueItem(
        eyebrow: '最近管理',
        title: '扩展资源',
        subtitle: '插件、书源、片源与备份',
        icon: Icons.extension_rounded,
        color: const Color(0xFF8B5CF6),
        onTap: () => _switchToTab(3, '扩展'),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '继续使用',
                    style: TextStyle(
                      fontSize: 18,
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

  Widget _buildTodayApiCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFF7FBFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE7ECF5)),
        boxShadow: AppTokens.shadowSm(color: AppTokens.primaryBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTokens.primaryBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.api_rounded,
                  color: AppTokens.primaryBlue,
                  size: 18,
                ),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '今日可用能力',
                      style: TextStyle(
                        color: AppTokens.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '公开 API 作为工作台能力，不做主 Tab 堆叠',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTokens.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ApiHubPage()),
                  );
                },
                child: const Text('打开'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppStatusPill(
                label: 'Open-Meteo 天气',
                icon: Icons.wb_cloudy_rounded,
                color: AppTokens.primaryBlue,
              ),
              AppStatusPill(
                label: 'API目录 国内可用',
                icon: Icons.travel_explore_rounded,
                color: AppTokens.orange,
              ),
              AppStatusPill(
                label: '词典 / 测试数据',
                icon: Icons.dataset_rounded,
                color: AppTokens.emerald,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCommonEntryStrip() {
    final actions = <HomeQuickAction>[
      HomeQuickAction(
        title: '工具',
        subtitle: '效率',
        icon: Icons.handyman_rounded,
        color: const Color(0xFF2563EB),
        onTap: () => _switchToTab(1, '工具'),
      ),
      HomeQuickAction(
        title: '内容',
        subtitle: '书影',
        icon: Icons.collections_bookmark_rounded,
        color: const Color(0xFF10B981),
        onTap: () => _switchToTab(2, '内容'),
      ),
      HomeQuickAction(
        title: '扩展',
        subtitle: '插件',
        icon: Icons.tune_rounded,
        color: const Color(0xFF8B5CF6),
        onTap: () => _switchToTab(3, '扩展'),
      ),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE9EEF7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  '常用入口',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppTokens.textPrimary,
                  ),
                ),
              ),
              HomeMiniPill(label: '轻量保留'),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '保留高频跳转，但不再把四个主 Tab 做成 2×2 面板。',
            style: TextStyle(
              color: AppTokens.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                Expanded(
                  child: AppCompactActionCard(
                    title: actions[i].title,
                    subtitle: actions[i].subtitle,
                    icon: actions[i].icon,
                    color: actions[i].color,
                    onTap: actions[i].onTap,
                  ),
                ),
                if (i != actions.length - 1) const SizedBox(width: 9),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeSoftIconButton extends StatelessWidget {
  const _HomeSoftIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFFF2F6FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0E8F6)),
        ),
        child: Icon(icon, color: AppTokens.primaryBlue, size: 21),
      ),
    );
  }
}

class _HomeHeroMetric extends StatelessWidget {
  const _HomeHeroMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FD),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE7ECF5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: AppTokens.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTokens.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
                  const SizedBox(height: 1),
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTokens.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 1),
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

Future<void> _showSnack(BuildContext context, String text) async {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
