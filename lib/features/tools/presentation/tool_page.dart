import 'package:flutter/material.dart';
import 'package:box/design_system/app_tokens.dart';
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
      final query = enteredKeyword.toLowerCase();
      List<ToolCategory> results = [];
      for (final category in _allCategories) {
        final titleMatch = category.title.toLowerCase().contains(query);
        final matchedTools = category.tools
            .where((tool) => tool.toLowerCase().contains(query))
            .toList();
        if (titleMatch || matchedTools.isNotEmpty) {
          results.add(ToolCategory(
            title: category.title,
            subtitle: category.subtitle,
            icon: category.icon,
            iconBgColor: category.iconBgColor,
            tools: titleMatch ? category.tools : matchedTools,
            isExpanded: true,
          ));
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

  int get _totalTools =>
      _allCategories.fold(0, (s, c) => s + c.tools.length);

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return AppPageScaffold(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── 合并 Hero + 搜索栏（一个 sliver） ──
          SliverToBoxAdapter(child: _buildHeroWithSearch()),

          // ── 紧凑 API Hub 快捷入口（行内 Chip） ──
          SliverToBoxAdapter(child: _buildCompactApiHub()),

          // ── 分类列表 ──
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
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
            child: SizedBox(height: AppTokens.pageBottomPadding + 20),
          ),
        ],
      ),
    );
  }

  /// 紧凑工具条：标题 + 指标 + 搜索，优先露出分类列表
  Widget _buildHeroWithSearch() {
    final hasFilter = _displayCategories.length < _allCategories.length;
    final matchTools =
        _displayCategories.fold<int>(0, (s, c) => s + c.tools.length);
    final metricText = hasFilter
        ? '匹配 ${_displayCategories.length} 类 · $matchTools 入口'
        : '${_allCategories.length} 类 · $_totalTools 入口';

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7ECF5)),
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

  /// 紧凑 API Hub 快捷入口（行内 Chip 排列）
  Widget _buildCompactApiHub() {
    final shortcuts = [
      ('二维码', Icons.qr_code_2_rounded, 'qr'),
      ('Mock用户', Icons.badge_rounded, 'mock'),
      ('头像', Icons.account_circle_rounded, 'avatar'),
      ('占位图', Icons.image_rounded, 'dummy_image'),
      ('API清单', Icons.travel_explore_rounded, 'directory'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE7ECF5)),
          boxShadow: AppTokens.shadowSm(color: AppTokens.violet),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: AppTokens.violetGradient,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.bolt_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'API',
              style: TextStyle(
                color: AppTokens.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: shortcuts
                      .map(
                        (s) => Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: ActionChip(
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(s.$2, size: 13, color: AppTokens.violet),
                                const SizedBox(width: 3),
                                Text(
                                  s.$1,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            onPressed: () => _openApiHub(s.$3),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 玻璃质感按钮
class ToolGlassButton extends StatelessWidget {
  const ToolGlassButton({super.key, required this.icon, required this.onTap});

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
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE0E8F6)),
        ),
        child: Icon(icon, color: AppTokens.primaryBlue, size: 20),
      ),
    );
  }
}
