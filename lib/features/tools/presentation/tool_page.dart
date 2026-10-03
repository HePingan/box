import 'package:flutter/material.dart';
import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_page_scaffold.dart';

import '../application/tool_catalog.dart';
import '../application/tool_usage_store.dart';
import 'widgets/custom_site_section.dart';
import 'widgets/tool_sections.dart';

/// 工具页。
///
/// 版式（2026-10-03 重设计）：
///   ① 顶卡：工具台 + 真数 + 搜索
///   ② 常用一行：按使用次数排的那几个工具（一条记录都没有时给一组推荐，并写明是推荐）
///   ③ 分类芯片：全部 / 各分类（带计数）/ 离线可用开关
///   ④ 分区网格：每个分类一个区，折叠态只露第一行，用「还有 N 个」收口
///   ⑤ 我的收藏（网址书签，默认收成一行）
///
/// 改前的两个病（都有实测）：
///   * 66 个可用工具**平铺**成 3 列 22 行 ≈ 2660px ≈ 4~5 屏，分类只剩卡片底部
///     9.5px 的小字，"浏览"这条路等于没有；
///   * 「计划中」区把 56 条**没做的**工具当承诺摆出来，点进去只弹一句
///     「还没做，先别点了」—— 每个条目都是一次失望点击，还把真能用的往下挤一屏。
///     它已彻底移除（名单留在目录里供分类归属与后续接线，不再上界面）。
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

  /// 已接线能力（目录顺序）。搜索/筛选都在它上面做，不改它本身。
  late List<ToolEntry> _allAvailable;

  /// 分类名 → 图标/配色（取自目录，不另抄一份）。
  late Map<String, ToolCategory> _categoryMeta;

  /// 常用行用的名字（按次数排）；空 = 还没有任何记录。
  List<String> _usageNames = const <String>[];

  /// 是否已从存储读过一次。没读之前不拿"推荐"冒充"常用"。
  bool _usageReady = false;

  /// 一条记录都没有时给的推荐集（取得到才显示）。
  static const List<String> _defaultRecentNames = [
    '天气预报',
    '二维码生成',
    'JSON格式化',
    '科学计算器',
    '翻译',
    '时间戳转换',
  ];

  /// 当前选中的分类；null = 全部。
  String? _selectedCategory;

  /// 只看纯本地工具（不联网也能用）。
  bool _offlineOnly = false;

  /// 手动展开过的分类。
  final Set<String> _expandedCategories = <String>{};

  String _query = '';

  @override
  void initState() {
    super.initState();
    _allAvailable = availableToolEntries();
    _categoryMeta = {for (final c in createDefaultToolCategories()) c.title: c};
    ToolUsageStore.instance.addListener(_onUsageChanged);
    // 刻意不在这儿等：首屏不该被一次 prefs 读拖住（读完再补一次 setState）。
    ToolUsageStore.instance.ensureLoaded().then((_) {
      if (!mounted) return;
      _onUsageChanged();
    });
  }

  @override
  void dispose() {
    ToolUsageStore.instance.removeListener(_onUsageChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onUsageChanged() {
    if (!mounted) return;
    setState(() {
      _usageReady = ToolUsageStore.instance.loaded;
      _usageNames = ToolUsageStore.instance.recentNames();
    });
  }

  void _runFilter(String enteredKeyword) {
    setState(() => _query = enteredKeyword.trim().toLowerCase());
  }

  void _toggleOffline() {
    setState(() {
      _offlineOnly = !_offlineOnly;
      // 筛选条件变了，之前手动展开的分类已经不对应同一批条目 —— 收回折叠态。
      _expandedCategories.clear();
    });
  }

  void _selectCategory(String? title) {
    setState(() {
      _selectedCategory = title;
      _expandedCategories.clear();
    });
  }

  void _toggleCategory(String title) {
    setState(() {
      if (!_expandedCategories.remove(title)) _expandedCategories.add(title);
    });
  }

  /// 搜索 / 离线筛选之后的条目（保持目录顺序）。
  List<ToolEntry> get _filtered {
    final query = _query;
    return _allAvailable.where((entry) {
      if (_offlineOnly && entry.target is! LocalToolTarget) return false;
      if (query.isEmpty) return true;
      return entry.name.toLowerCase().contains(query) ||
          entry.category.toLowerCase().contains(query);
    }).toList();
  }

  /// 按目录顺序分组；空分类不出现。
  List<({String title, ToolCategory meta, List<ToolEntry> entries})> _grouped(
    List<ToolEntry> entries,
  ) {
    final groups = <String, List<ToolEntry>>{};
    for (final entry in entries) {
      groups.putIfAbsent(entry.category, () => <ToolEntry>[]).add(entry);
    }
    return [
      for (final e in groups.entries)
        (
          title: e.key,
          meta: _categoryMeta[e.key] ?? _fallbackCategory(e.key),
          entries: e.value,
        ),
    ];
  }

  ToolCategory _fallbackCategory(String title) => ToolCategory(
    title: title,
    subtitle: '',
    icon: Icons.handyman_outlined,
    iconBgColor: AppTokens.violet,
    tools: const [],
  );

  /// 常用行要显示的条目（记录里的名字已经不在目录里的，自动不显示）。
  ///
  /// 也吃「离线可用」这一个开关：开着它却还把要联网的「天气预报」摆在最上面，
  /// 等于让筛选看起来没生效。
  List<ToolEntry> get _recentEntries {
    final byName = {for (final e in _allAvailable) e.name: e};
    final names = _usageNames.isNotEmpty
        ? _usageNames
        : (_usageReady ? _defaultRecentNames : const <String>[]);
    return [
      for (final name in names)
        if (byName[name] != null)
          if (!_offlineOnly || byName[name]!.target is LocalToolTarget)
            byName[name]!,
    ];
  }

  bool get _showingDefaults => _usageNames.isEmpty;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final filtered = _filtered;
    final grouped = _grouped(filtered);
    final searching = _query.isNotEmpty;

    // 选中的分类如果在这一批结果里不存在（比如搜索词换掉了），当没选 ——
    // 否则会出现「芯片全是未选中、内容却是空」这种说不清的状态。
    final selectedCategory = grouped.any((g) => g.title == _selectedCategory)
        ? _selectedCategory
        : null;

    // 选了分类 = **只看这一类**。不这么做的话，点第 5 个分类的芯片还得自己往下滚四次，
    // 「一次点击就到」就成了空话。
    final visibleGroups = selectedCategory == null
        ? grouped
        : grouped.where((g) => g.title == selectedCategory).toList();

    return AppPageScaffold(
      maxContentWidth: AppTokens.shellMaxContentWidth,
      shellInset: true,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildHeaderCard(filtered.length)),

          // ── 常用（搜索时不渲染：此刻用户已经说清他要什么了）──
          if (!searching)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.shellPageGutter,
                2,
                AppTokens.shellPageGutter,
                6,
              ),
              sliver: SliverToBoxAdapter(
                child: RecentToolsRow(
                  entries: _recentEntries,
                  usingDefaults: _showingDefaults,
                ),
              ),
            ),

          // ── 分类芯片 ──
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.shellPageGutter,
              0,
              AppTokens.shellPageGutter,
              10,
            ),
            sliver: SliverToBoxAdapter(
              child: ToolCategoryChips(
                categories: [
                  for (final g in grouped)
                    (title: g.title, count: g.entries.length),
                ],
                selected: selectedCategory,
                totalCount: filtered.length,
                offlineOnly: _offlineOnly,
                onSelect: _selectCategory,
                onToggleOffline: _toggleOffline,
              ),
            ),
          ),

          // ── 分区网格 ──
          if (visibleGroups.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.shellPageGutter,
              ),
              sliver: SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE7ECF5)),
                  ),
                  child: Text(
                    _offlineOnly ? '没有匹配的工具。这些工具要联网，关掉「离线可用」再看看。' : '没有匹配的工具。',
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppTokens.textSecondary,
                    ),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.shellPageGutter,
              ),
              sliver: SliverList.builder(
                itemCount: visibleGroups.length,
                itemBuilder: (context, index) {
                  final group = visibleGroups[index];
                  // 选中某个分类 = 只看它 → 直接展开（都只剩它一个区了，没有折叠的理由）；
                  // 搜索时也展开（命中结果藏在「还有 N 个」后面很烦）。
                  final expanded =
                      searching ||
                      selectedCategory == group.title ||
                      _expandedCategories.contains(group.title);
                  return ToolCategorySection(
                    title: group.title,
                    icon: group.meta.icon,
                    color: group.meta.iconBgColor,
                    entries: group.entries,
                    expanded: expanded,
                    onToggle: () => _toggleCategory(group.title),
                  );
                },
              ),
            ),

          // ── 我的收藏（网址书签）──
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppTokens.shellPageGutter,
              6,
              AppTokens.shellPageGutter,
              0,
            ),
            sliver: SliverToBoxAdapter(child: CustomSiteSection()),
          ),

          // ── 想要什么工具？──
          // 「计划中」撤掉之后，用户"我想要个 X"这条诉求得有个能兑现的出口，
          // 而不是一张点了没反应的假卡片。
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.shellPageGutter,
              10,
              AppTokens.shellPageGutter,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: ToolRequestRow(
                onTap: () => Navigator.pushNamed(context, 'about'),
              ),
            ),
          ),

          // 底部避让由 AppPageScaffold(shellInset: true) 统一下发。
          SliverToBoxAdapter(
            child: SizedBox(height: AppPageScaffold.bottomInsetOf(context)),
          ),
        ],
      ),
    );
  }

  /// 紧凑工具条：标题 + 真数 + 搜索。
  ///
  /// 指标只报**真数**（可用条数 / 命中数）。改前写的是「66 可用 · 56 计划」——
  /// 把内部的未完成项当用户指标报，和扩展页那两个恒 0 的死数字同一族病。
  Widget _buildHeaderCard(int matchCount) {
    final metricText = _query.isEmpty
        ? '${_allAvailable.length} 个工具'
        : '匹配 $matchCount 个';

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppTokens.shellPageGutter,
        8,
        AppTokens.shellPageGutter,
        8,
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
