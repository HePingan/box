// lib/tool_page.dart
import 'package:flutter/material.dart';
import 'globals.dart';
import 'design_system/app_tokens.dart';
import 'design_system/widgets/app_cards.dart';
import 'tool_web_page.dart'; // 👉 引入刚才新建的网页工具容器

class ToolCategory {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconBgColor;
  final List<String> tools;
  bool isExpanded;

  ToolCategory({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconBgColor,
    required this.tools,
    this.isExpanded = false,
  });
}

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
    _allCategories = [
      ToolCategory(
        title: '日常工具',
        subtitle: '每日资讯、实用工具',
        icon: Icons.wb_sunny_outlined,
        iconBgColor: const Color(0xFF5A728D),
        isExpanded: true,
        tools: [
          '每日早报',
          '每日一文',
          '每日英语',
          '央视新闻',
          '步数修改',
          '在线翻译',
          '菜谱大全',
          '全国降水量',
          '历史上的今天',
        ],
      ),
      ToolCategory(
        title: '系统操作',
        subtitle: '涉及系统相关的工具',
        icon: Icons.settings_applications_outlined,
        iconBgColor: const Color(0xFF587A9A),
        tools: [
          'APK提取',
          'APK.1安装器',
          '系统界面调节',
          '系统字体调节',
          '屏幕坏点检测',
          '提取手机壁纸',
          '空文件夹清理',
          '扬声器清灰',
          '动态视频壁纸',
          '查看设备信息',
          '刻度尺',
          '指南针',
          '水平仪',
          '分贝仪',
          '秒表',
          '计时器',
          '时间屏幕',
        ],
      ),

      // 👉 图片工具里第一个加上了 “在线PS”
      ToolCategory(
        title: '图片工具',
        subtitle: '图片处理相关的工具',
        icon: Icons.image_outlined,
        iconBgColor: Colors.teal,
        tools: [
          '在线PS',
          '图片压缩',
          '格式转换',
          '九宫格切图',
          '水印添加',
          '老照片修复',
          '黑白上色',
          '图片拼接',
          '壁纸提取',
        ],
      ),

      ToolCategory(
        title: '查询工具',
        subtitle: 'Query tools · 34个工具',
        icon: Icons.search_outlined,
        iconBgColor: const Color(0xFF4C5B99),
        tools: [
          '快递查询',
          '天气预报',
          'IP地址查询',
          '归属地查询',
          '老黄历',
          '成语词典',
          '近义词查询',
          '垃圾分类',
        ],
      ),
      ToolCategory(
        title: '提取工具',
        subtitle: '各大平台资源提取',
        icon: Icons.file_download_outlined,
        iconBgColor: Colors.blueAccent,
        tools: ['短视频去水印', '图集提取', '网页音频提取', 'B站封面提取', '文案提取', '图片文字识别'],
      ),
      ToolCategory(
        title: '开发工具',
        subtitle: '程序猿专属工具',
        icon: Icons.code,
        iconBgColor: Colors.deepPurple,
        tools: [
          'JSON格式化',
          '正则测试',
          'Base64编解码',
          'MD5加密',
          '时间戳转换',
          '网页源码获取',
          'URL编码',
          '进制转换',
        ],
      ),
      ToolCategory(
        title: '文本工具',
        subtitle: 'Text tools · 39个工具',
        icon: Icons.text_fields,
        iconBgColor: const Color(0xFF7A8CD0),
        tools: [
          '汉字查询',
          '颜文字',
          '文本编辑器',
          '随机密码',
          '随机一言',
          '诗词一言',
          '随机一文',
          '六十秒读世界',
          '史上今日',
          '搜题',
          '翻译',
          '滚动弹幕',
          '历史上的今天',
          '藏头诗生成',
          '随机彩虹屁',
          '舔狗日记',
          '毒鸡汤',
          '笑话语录',
          '渣男语录',
          '随机弱智吧问答',
          '猜成语生成',
          '随机人设',
          '脑筋急转弯',
          '随机沙雕新闻',
        ],
      ),
      ToolCategory(
        title: '计算工具',
        subtitle: '各类计算换算',
        icon: Icons.calculate_outlined,
        iconBgColor: Colors.orange,
        tools: [
          '科学计算器',
          '亲戚称呼计算',
          '汇率换算',
          '房贷计算器',
          'BMI计算',
          '单位换算',
          '大小写转换',
          '日期计算',
        ],
      ),
      ToolCategory(
        title: '其他工具',
        subtitle: '更多好玩的应用',
        icon: Icons.grid_view,
        iconBgColor: Colors.blueGrey,
        tools: ['摩斯密码', '二维码生成', '条形码扫描', 'LED字幕', '随机数生成', '手持弹幕', '全屏时钟'],
      ),
      ToolCategory(
        title: '趣味游戏',
        subtitle: '休闲娱乐小游戏',
        icon: Icons.sports_esports_outlined,
        iconBgColor: Colors.redAccent,
        tools: ['扫雷', '2048', '数字华容道', '五子棋', '贪吃蛇', '迷宫', '数独'],
      ),
    ];
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
              child: SizedBox(height: AppTokens.pageBottomPadding),
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
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.all(16),
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
              _ToolGlassButton(
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
                      'TOOLS STUDIO',
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
              _ToolGlassButton(
                icon: Icons.search_rounded,
                onTap: () => _searchFocusNode.requestFocus(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            '工具工作台',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '新版工具页 · $totalTools 个工具 · 分类聚合',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ToolMetric(
                  value: '${_allCategories.length}',
                  label: '工具分类',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ToolMetric(value: '$totalTools', label: '功能入口'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ToolMetric(
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
            hintText: '搜索：在线PS、天气、JSON、二维码',
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
              title: '热门工具',
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
              title: '常用工具',
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
          _ToolHighlightCard(
            title: '我的收藏',
            subtitle: '高频工具一键直达',
            icon: Icons.star_rounded,
            gradient: const [Color(0xFFFF7A45), Color(0xFFFFC53D)],
          ),
          const SizedBox(width: 12),
          _ToolHighlightCard(
            title: '近期更新',
            subtitle: '新能力与修复记录',
            icon: Icons.new_releases_rounded,
            gradient: const [Color(0xFF2563EB), Color(0xFF38BDF8)],
          ),
          const SizedBox(width: 12),
          _ToolHighlightCard(
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
            searching ? '搜索结果' : '全部分类',
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
                : '分类 · 状态 · 前 3 项',
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

class _ToolGlassButton extends StatelessWidget {
  const _ToolGlassButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }
}

class _ToolMetric extends StatelessWidget {
  const _ToolMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.76),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolHighlightCard extends StatelessWidget {
  const _ToolHighlightCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 176,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: gradient.first.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -14,
            bottom: -16,
            child: Icon(
              icon,
              size: 72,
              color: Colors.white.withValues(alpha: 0.18),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Colors.white, size: 26),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.80),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToolStatusBadge extends StatelessWidget {
  const _ToolStatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class ExpandableCategoryCard extends StatefulWidget {
  final ToolCategory category;
  const ExpandableCategoryCard({super.key, required this.category});

  @override
  State<ExpandableCategoryCard> createState() => _ExpandableCategoryCardState();
}

class _ExpandableCategoryCardState extends State<ExpandableCategoryCard> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.category.isExpanded;
  }

  @override
  void didUpdateWidget(covariant ExpandableCategoryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.category.isExpanded != oldWidget.category.isExpanded) {
      _isExpanded = widget.category.isExpanded;
    }
  }

  bool _isAvailableTool(String toolName) => toolName == '在线PS';

  void _handleToolTap(String toolName) {
    if (_isAvailableTool(toolName)) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ToolWebPage(
            title: '在线PS',
            url: 'https://www.photopea.com/',
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('【$toolName】开发中，稍后开放'),
        duration: const Duration(milliseconds: 1100),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final previewTools = widget.category.tools.take(3).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 14.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26.0),
        border: Border.all(color: const Color(0xFFE7ECF5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(26.0),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: widget.category.iconBgColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.category.icon,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.category.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF333333),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.category.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _ToolStatusBadge(
                              label: '${widget.category.tools.length} 个工具',
                              color: widget.category.iconBgColor,
                            ),
                            if (widget.category.tools.any(_isAvailableTool))
                              _ToolStatusBadge(
                                label: '含可用工具',
                                color: const Color(0xFF059669),
                              )
                            else
                              _ToolStatusBadge(
                                label: '开发中',
                                color: const Color(0xFF64748B),
                              ),
                          ],
                        ),
                        if (!_isExpanded && previewTools.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          Text(
                            previewTools.join(' / '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTokens.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _isExpanded
                      ? const Icon(
                          Icons.arrow_drop_up,
                          size: 30,
                          color: Color(0xFF132D6B),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6B7FA2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${widget.category.tools.length}个功能',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _isExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 12.0,
                        runSpacing: 12.0,
                        children: widget.category.tools.map((toolName) {
                          final available = _isAvailableTool(toolName);
                          return GestureDetector(
                            onTap: () => _handleToolTap(toolName),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14.0,
                                vertical: 10.0,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    (available
                                            ? const Color(0xFF059669)
                                            : widget.category.iconBgColor)
                                        .withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color:
                                      (available
                                              ? const Color(0xFF059669)
                                              : widget.category.iconBgColor)
                                          .withValues(alpha: 0.20),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    toolName,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: available
                                          ? const Color(0xFF059669)
                                          : widget.category.iconBgColor,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    available ? '可用 · 外部网页' : '开发中',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: available
                                          ? const Color(0xFF047857)
                                          : AppTokens.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
