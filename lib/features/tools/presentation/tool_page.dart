// lib/tool_page.dart
import 'package:flutter/material.dart';
import 'package:box/globals.dart';
import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_cards.dart';
import 'package:box/design_system/widgets/app_page_scaffold.dart';
import 'package:box/features/api_hub/presentation/api_hub_page.dart';

import '../application/tool_catalog.dart';
import 'widgets/tool_widgets.dart';

class ToolPage extends StatefulWidget {
  const ToolPage({super.key});

  @override
  State<ToolPage> createState() => _ToolPageState();
}

class _ToolPageState extends State<ToolPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late List<ToolCategory> _allCategories;
  late List<ToolCategory> _displayCategories;

  @override
  void initState() {
    super.initState();
    _allCategories = createDefaultToolCategories();

    _displayCategories = List.from(_allCategories);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _runFilter(String enteredKeyword) {
    if (enteredKeyword.isEmpty) {
      setState(() => _displayCategories = _allCategories);
    } else {
      List<ToolCategory> results = [];
      for (var category in _allCategories) {
        bool titleMatch = category.title.contains(enteredKeyword);
        List<String> matchedTools = category.tools
            .where(
              (tool) =>
                  tool.toLowerCase().contains(enteredKeyword.toLowerCase()),
            )
            .toList();
        if (titleMatch || matchedTools.isNotEmpty) {
          results.add(
            ToolCategory(
              title: category.title,
              subtitle: category.subtitle,
              icon: category.icon,
              iconBgColor: category.iconBgColor,
              tools: titleMatch ? category.tools : matchedTools,
              isExpanded: true,
            ),
          );
        }
      }
      setState(() => _displayCategories = results);
    }
  }

  void _openApiHub([String? initialTool]) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ApiHubPage(initialTool: initialTool)),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return AppPageScaffold(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildToolHero()),
          SliverToBoxAdapter(child: _buildSearchBar()),
          SliverToBoxAdapter(child: _buildApiHubFeatureCard()),
          SliverToBoxAdapter(child: _buildQuickGradientCards()),
          SliverToBoxAdapter(child: _buildToolStats()),
          SliverToBoxAdapter(child: _buildSectionTitle()),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    ExpandableCategoryCard(category: _displayCategories[index]),
                childCount: _displayCategories.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: SizedBox(height: AppTokens.pageBottomPadding + 28),
          ),
        ],
      ),
    );
  }

  Widget _buildToolHero() {
    final totalTools = _allCategories.fold<int>(
      0,
      (sum, category) => sum + category.tools.length,
    );
    return AppLightHeroCard(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      eyebrow: '效率工具集合',
      title: '工具台',
      subtitle: '搜索优先 · 常用前置 · $totalTools 个入口',
      badge: 'TOOLS',
      accentGradient: AppTokens.violetGradient,
      leading: ToolGlassButton(
        icon: Icons.menu_rounded,
        onTap: () => appScaffoldKey.currentState?.openDrawer(),
      ),
      actions: const [
        AppStatusPill(
          label: '搜索 / 热门 / 分类首屏直达',
          icon: Icons.search_rounded,
          color: AppTokens.violet,
        ),
      ],
      metrics: [
        Expanded(
          child: ToolMetric(value: '${_allCategories.length}', label: '工具分类'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ToolMetric(value: '$totalTools', label: '功能入口'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ToolMetric(
            value: '${_displayCategories.length}',
            label: '分类匹配',
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0xFFE7ECF5)),
          boxShadow: AppTokens.shadowLg(color: AppTokens.primaryBlue),
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          onChanged: _runFilter,
          decoration: InputDecoration(
            hintText: '搜索：天气、JSON、二维码',
            hintStyle: const TextStyle(
              color: AppTokens.textSecondary,
              fontSize: 13,
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: Color(0xFF6D28D9),
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(
                      Icons.clear_rounded,
                      color: AppTokens.textSecondary,
                    ),
                    onPressed: () {
                      _searchController.clear();
                      _runFilter('');
                      FocusScope.of(context).unfocus();
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildApiHubFeatureCard() {
    final shortcuts = [
      ('二维码', Icons.qr_code_2_rounded, 'qr'),
      ('Mock用户', Icons.badge_rounded, 'mock'),
      ('头像', Icons.account_circle_rounded, 'avatar'),
      ('占位图', Icons.image_rounded, 'dummy_image'),
      ('API清单', Icons.travel_explore_rounded, 'directory'),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE7ECF5)),
        boxShadow: AppTokens.shadowSm(color: AppTokens.violet),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: AppTokens.violetGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.api_rounded, color: Colors.white),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'API 能力中心',
                      style: TextStyle(
                        color: AppTokens.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '二维码 / Mock 用户 / 头像 / 占位图 / 国内可用清单',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTokens.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: () => _openApiHub(),
                child: const Text('进入'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: shortcuts.map((item) {
              return ActionChip(
                avatar: Icon(item.$2, size: 16),
                label: Text(item.$1),
                onPressed: () => _openApiHub(item.$3),
                side: const BorderSide(color: Color(0xFFE7ECF5)),
                backgroundColor: const Color(0xFFF8FAFC),
                labelStyle: const TextStyle(fontWeight: FontWeight.w900),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickGradientCards() {
    final actions = [
      AppCompactActionCard(
        title: '天气',
        subtitle: 'Open-Meteo',
        icon: Icons.wb_cloudy_rounded,
        color: AppTokens.primaryBlue,
        onTap: () => _openApiHub('weather'),
      ),
      AppCompactActionCard(
        title: 'API目录',
        subtitle: '国内可用',
        icon: Icons.travel_explore_rounded,
        color: AppTokens.emerald,
        onTap: () => _openApiHub('directory'),
      ),
      AppCompactActionCard(
        title: 'API Hub',
        subtitle: '二维码/头像',
        icon: Icons.api_rounded,
        color: AppTokens.violet,
        onTap: () => _openApiHub(),
      ),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE9EEF7)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            Expanded(child: actions[i]),
            if (i != actions.length - 1) const SizedBox(width: 9),
          ],
        ],
      ),
    );
  }

  Widget _buildToolStats() {
    return SizedBox(
      height: 70,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          ToolHighlightCard(
            title: '汇率换算',
            subtitle: 'USD/CNY/EUR/JPY',
            icon: Icons.currency_exchange_rounded,
            gradient: const [Color(0xFFFF7A45), Color(0xFFFFC53D)],
            onTap: () => _openApiHub('currency'),
          ),
          const SizedBox(width: 12),
          ToolHighlightCard(
            title: '节假日查询',
            subtitle: '今年公开假日',
            icon: Icons.event_available_rounded,
            gradient: const [Color(0xFF2563EB), Color(0xFF38BDF8)],
            onTap: () => _openApiHub('holidays'),
          ),
          const SizedBox(width: 12),
          const ToolHighlightCard(
            title: '开发工具',
            subtitle: 'JSON / Base64 / 时间戳',
            icon: Icons.code_rounded,
            gradient: [Color(0xFF7C3AED), Color(0xFFC084FC)],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle() {
    final searching = _searchController.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          Text(
            searching ? '搜索结果' : '工具分类矩阵',
            style: const TextStyle(
              color: AppTokens.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Spacer(),
          Text(
            searching
                ? '${_displayCategories.length} 个分类匹配'
                : '新版卡片 · 状态 · 前 3 项',
            style: const TextStyle(
              color: AppTokens.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
