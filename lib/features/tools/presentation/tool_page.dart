// lib/tool_page.dart
import 'package:flutter/material.dart';
import 'package:box/globals.dart';
import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_cards.dart';

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

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildToolHero()),
            SliverToBoxAdapter(child: _buildSearchBar()),
            SliverToBoxAdapter(child: _buildQuickGradientCards()),
            SliverToBoxAdapter(child: _buildToolStats()),
            SliverToBoxAdapter(child: _buildSectionTitle()),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => ExpandableCategoryCard(
                    category: _displayCategories[index],
                  ),
                  childCount: _displayCategories.length,
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: AppTokens.pageBottomPadding + 28),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolHero() {
    final totalTools = _allCategories.fold<int>(
      0,
      (sum, category) => sum + category.tools.length,
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF111827), Color(0xFF6D28D9), Color(0xFF22D3EE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6D28D9).withValues(alpha: 0.22),
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
              ToolGlassButton(
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
                      Icons.auto_fix_high_rounded,
                      size: 15,
                      color: Color(0xFFFFE08A),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'TOOLS STUDIO 2.0',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ToolGlassButton(
                icon: Icons.search_rounded,
                onTap: () => _searchFocusNode.requestFocus(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '工具台',
            style: TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '搜索优先 · 常用前置 · $totalTools 个入口',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 9),
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
                Icon(Icons.search_rounded, size: 18, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '搜索 / 热门 / 分类首屏直达',
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
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ToolMetric(
                  value: '${_allCategories.length}',
                  label: '工具分类',
                ),
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
          ),
        ],
      ),
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

  Widget _buildQuickGradientCards() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: AppGradientActionCard(
              title: '首屏热门',
              subtitle: '天气 / 翻译 / 二维码',
              icon: Icons.local_fire_department_rounded,
              gradient: AppTokens.blueGradient,
              onTap: () {
                _searchController.text = '天气';
                _runFilter('天气');
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AppGradientActionCard(
              title: '一键直达',
              subtitle: 'PS / JSON / 二维码',
              icon: Icons.rocket_launch_rounded,
              gradient: AppTokens.neonVioletGradient,
              onTap: () {
                _searchController.text = '在线PS';
                _runFilter('在线PS');
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolStats() {
    return SizedBox(
      height: 112,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          ToolHighlightCard(
            title: '我的收藏',
            subtitle: '高频工具一键直达',
            icon: Icons.star_rounded,
            gradient: const [Color(0xFFFF7A45), Color(0xFFFFC53D)],
          ),
          const SizedBox(width: 12),
          ToolHighlightCard(
            title: '近期更新',
            subtitle: '新能力与修复记录',
            icon: Icons.new_releases_rounded,
            gradient: const [Color(0xFF2563EB), Color(0xFF38BDF8)],
          ),
          const SizedBox(width: 12),
          ToolHighlightCard(
            title: '开发工具',
            subtitle: 'JSON / Base64 / 时间戳',
            icon: Icons.code_rounded,
            gradient: const [Color(0xFF7C3AED), Color(0xFFC084FC)],
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
            style: TextStyle(
              color: AppTokens.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          Spacer(),
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
