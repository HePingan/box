import 'package:flutter/material.dart';
import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_page_scaffold.dart';

import '../application/tool_catalog.dart';
import 'widgets/available_tool_grid.dart';
import 'widgets/custom_site_section.dart';
import 'widgets/planned_tools_section.dart';

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

  /// 已接线能力（平铺置顶）与未接线占位（折叠区），两份都从目录派生。
  late List<ToolEntry> _allAvailable;
  late List<ToolCategory> _allPlanned;
  late List<ToolEntry> _displayAvailable;
  late List<ToolCategory> _displayPlanned;

  /// 折叠区展开态放在页面 State：搜索会重建 ToolCategory，
  /// 放在卡片 State 里会被 didUpdateWidget 冲掉。
  bool _plannedExpanded = false;

  /// 搜索命中占位条目时强制展开，否则「搜到了却看不见」。
  bool _forcePlannedOpen = false;

  @override
  void initState() {
    super.initState();
    _allAvailable = availableToolEntries();
    _allPlanned = plannedToolCategories();
    _displayAvailable = _allAvailable;
    _displayPlanned = _allPlanned;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _runFilter(String enteredKeyword) {
    if (enteredKeyword.isEmpty) {
      setState(() {
        _displayAvailable = _allAvailable;
        _displayPlanned = _allPlanned;
        _forcePlannedOpen = false;
      });
      return;
    }

    final query = enteredKeyword.toLowerCase();

    final availableHits = _allAvailable
        .where(
          (e) =>
              e.name.toLowerCase().contains(query) ||
              e.category.toLowerCase().contains(query),
        )
        .toList();

    final plannedHits = <ToolCategory>[];
    for (final category in _allPlanned) {
      final titleMatch = category.title.toLowerCase().contains(query);
      final matchedTools = category.tools
          .where((tool) => tool.toLowerCase().contains(query))
          .toList();
      if (titleMatch || matchedTools.isNotEmpty) {
        plannedHits.add(
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

    setState(() {
      _displayAvailable = availableHits;
      _displayPlanned = plannedHits;
      // 命中占位条目就把折叠区顶开，不然搜到了也看不见。
      _forcePlannedOpen = plannedHits.isNotEmpty;
    });
  }

  int get _totalTools =>
      _allAvailable.length +
      _allPlanned.fold<int>(0, (s, c) => s + c.tools.length);

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return AppPageScaffold(
      maxContentWidth: AppTokens.shellMaxContentWidth,
      shellInset: true,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── 合并 Hero + 搜索栏（一个 sliver） ──
          SliverToBoxAdapter(child: _buildHeroWithSearch()),

          // ── 我的收藏（用户自己添加的网站）──
          // 放在内置分类之前：这是用户自己攒的东西，比内置目录更该先看到。
          const SliverPadding(
            padding: EdgeInsets.symmetric(
              horizontal: AppTokens.shellPageGutter,
            ),
            sliver: SliverToBoxAdapter(child: CustomSiteSection()),
          ),

          // ── 现在可用：已接线能力平铺置顶 ──
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.shellPageGutter,
              4,
              AppTokens.shellPageGutter,
              8,
            ),
            sliver: SliverToBoxAdapter(
              child: AvailableToolGrid(entries: _displayAvailable),
            ),
          ),

          // ── 计划中：未接线条目默认折叠 ──
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.shellPageGutter,
            ),
            sliver: SliverToBoxAdapter(
              child: PlannedToolsSection(
                categories: _displayPlanned,
                expanded: _plannedExpanded || _forcePlannedOpen,
                onToggle: () => setState(() {
                  // 搜索强制展开时，点标题等于「关掉强制」，回到用户自己的折叠态。
                  if (_forcePlannedOpen) {
                    _forcePlannedOpen = false;
                    _plannedExpanded = false;
                  } else {
                    _plannedExpanded = !_plannedExpanded;
                  }
                }),
              ),
            ),
          ),
          // 底部避让由 AppPageScaffold(shellInset: true) 统一下发。
          // 原为 pageBottomPadding + 20 常量，不跟随机型手势区。
          SliverToBoxAdapter(
            child: SizedBox(
              height: AppPageScaffold.bottomInsetOf(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 紧凑工具条：标题 + 指标 + 搜索，优先露出可用网格
  Widget _buildHeroWithSearch() {
    final querying = _searchController.text.isNotEmpty;
    final availableCount = _displayAvailable.length;
    final plannedCount = _displayPlanned.fold<int>(
      0,
      (s, c) => s + c.tools.length,
    );
    final metricText = querying
        ? '匹配 $availableCount 可用 · $plannedCount 计划'
        : '$availableCount 可用 · ${_totalTools - _allAvailable.length} 计划';

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppTokens.shellPageGutter,
        8,
        AppTokens.shellPageGutter,
        6,
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: AppTokens.cardBorder),
        boxShadow: AppTokens.shadowSm(color: AppTokens.violet),
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
                  gradient: AppTokens.violetGradient,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.handyman_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '工具台',
                  style: TextStyle(
                    color: AppTokens.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  metricText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: AppTokens.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 38,
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _runFilter,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: '搜索：天气、JSON、二维码',
                hintStyle: const TextStyle(
                  color: AppTokens.textSecondary,
                  fontSize: 12,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: Color(0xFF6D28D9),
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.clear_rounded,
                          size: 18,
                          color: AppTokens.textSecondary,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          _runFilter('');
                          FocusScope.of(context).unfocus();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: Color(0xFFE7ECF5)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: Color(0xFFE7ECF5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(
                    color: Color(0xFF6D28D9),
                    width: 1.4,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                filled: true,
                fillColor: const Color(0xFFF8F9FE),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


