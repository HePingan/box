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
            padding: const EdgeInsets.symmetric(horizontal: 16),
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

  /// 合并 Hero + 搜索栏 + 统计，紧凑展示
  Widget _buildHeroWithSearch() {
    final hasFilter = _displayCategories.length < _allCategories.length;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(AppTokens.radiusXl),
        border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
        boxShadow: AppTokens.shadowLg(color: AppTokens.primaryBlue),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        child: Stack(
          children: [
            // 装饰圆点
            Positioned(
              right: -18,
              top: -20,
              child: Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppTokens.violetGradient,
                ),
                foregroundDecoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.72),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 顶栏：眉标 + 搜索按钮 + Badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTokens.violet.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                      ),
                      child: const Text(
                        '效率工具集合',
                        style: TextStyle(
                          color: AppTokens.violet,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (hasFilter)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTokens.violet.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                        ),
                        child: Text(
                          '${_displayCategories.length}',
                          style: const TextStyle(
                            color: AppTokens.violet,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    const SizedBox(width: 6),
                    ToolGlassButton(
                      icon: Icons.search_rounded,
                      onTap: () => _searchFocusNode.requestFocus(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // 标题 + 副标题
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Expanded(
                      child: Text(
                        '工具台',
                        style: TextStyle(
                          color: AppTokens.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: AppTokens.violetGradient,
                        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                      ),
                      child: const Text(
                        'TOOLS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  hasFilter
                      ? '找到 ${_displayCategories.length} 个分类 · ${_displayCategories.fold<int>(0, (s, c) => s + c.tools.length)} 个工具'
                      : '${_allCategories.length} 个分类 · $_totalTools 个入口 · 搜索优先',
                  style: const TextStyle(
                    color: AppTokens.textSecondary,
                    fontSize: 12.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                // 内嵌搜索栏
                SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onChanged: _runFilter,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '搜索：天气、JSON、二维码',
                      hintStyle: const TextStyle(
                        color: AppTokens.textSecondary,
                        fontSize: 12.5,
                      ),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF6D28D9)),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18, color: AppTokens.textSecondary),
                              onPressed: () {
                                _searchController.clear();
                                _runFilter('');
                                FocusScope.of(context).unfocus();
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(26),
                        borderSide: const BorderSide(color: Color(0xFFE7ECF5)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(26),
                        borderSide: const BorderSide(color: Color(0xFFE7ECF5)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(26),
                        borderSide: const BorderSide(color: Color(0xFF6D28D9), width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      filled: true,
                      fillColor: const Color(0xFFF8F9FE),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // 指标行
                Row(
                  children: [
                    Expanded(child: _buildMetric('${_allCategories.length}', '工具分类')),
                    const SizedBox(width: 10),
                    Expanded(child: _buildMetric('$_totalTools', '功能入口')),
                    const SizedBox(width: 10),
                    Expanded(child: _buildMetric('${_displayCategories.length}', '分类匹配')),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FD),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border: Border.all(color: const Color(0xFFE7ECF5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value,
              style: const TextStyle(
                  color: AppTokens.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w900)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppTokens.textSecondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700)),
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0xFFE7ECF5)),
          boxShadow: AppTokens.shadowSm(color: AppTokens.violet),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: AppTokens.violetGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 8),
            const Text('API Hub',
                style: TextStyle(
                    color: AppTokens.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800)),
            const SizedBox(width: 10),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: shortcuts
                      .map((s) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(s.$2, size: 14, color: AppTokens.violet),
                                  const SizedBox(width: 4),
                                  Text(s.$1,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                              onPressed: () => _openApiHub(s.$3),
                            ),
                          ))
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
