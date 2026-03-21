// lib/tool_page.dart
import 'package:flutter/material.dart';
import 'globals.dart'; 
import 'tool_web_page.dart'; // 👉 引入刚才新建的网页工具容器

class ToolCategory {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconBgColor;
  final List<String> tools;
  bool isExpanded;

  ToolCategory({
    required this.title, required this.subtitle, required this.icon, required this.iconBgColor, required this.tools, this.isExpanded = false,
  });
}

class ToolPage extends StatefulWidget {
  const ToolPage({super.key});

  @override
  State<ToolPage> createState() => _ToolPageState();
}

class _ToolPageState extends State<ToolPage> with AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => true; 

  final TextEditingController _searchController = TextEditingController();
  late List<ToolCategory> _allCategories;
  late List<ToolCategory> _displayCategories;

  @override
  void initState() {
    super.initState();
    _allCategories = [
      ToolCategory(title: '日常工具', subtitle: '每日资讯、实用工具', icon: Icons.wb_sunny_outlined, iconBgColor: const Color(0xFF5A728D), isExpanded: true, tools: ['每日早报', '每日一文', '每日英语', '央视新闻', '步数修改', '在线翻译', '菜谱大全', '全国降水量', '历史上的今天']),
      ToolCategory(title: '系统操作', subtitle: '涉及系统相关的工具', icon: Icons.settings_applications_outlined, iconBgColor: const Color(0xFF587A9A), tools: ['APK提取', 'APK.1安装器', '系统界面调节', '系统字体调节', '屏幕坏点检测', '提取手机壁纸', '空文件夹清理', '扬声器清灰', '动态视频壁纸', '查看设备信息', '刻度尺', '指南针', '水平仪', '分贝仪', '秒表', '计时器', '时间屏幕']),
      
      // 👉 图片工具里第一个加上了 “在线PS”
      ToolCategory(title: '图片工具', subtitle: '图片处理相关的工具', icon: Icons.image_outlined, iconBgColor: Colors.teal, tools: ['在线PS', '图片压缩', '格式转换', '九宫格切图', '水印添加', '老照片修复', '黑白上色', '图片拼接', '壁纸提取']),
      
      ToolCategory(title: '查询工具', subtitle: 'Query tools · 34个工具', icon: Icons.search_outlined, iconBgColor: const Color(0xFF4C5B99), tools: ['快递查询', '天气预报', 'IP地址查询', '归属地查询', '老黄历', '成语词典', '近义词查询', '垃圾分类']),
      ToolCategory(title: '提取工具', subtitle: '各大平台资源提取', icon: Icons.file_download_outlined, iconBgColor: Colors.blueAccent, tools: ['短视频去水印', '图集提取', '网页音频提取', 'B站封面提取', '文案提取', '图片文字识别']),
      ToolCategory(title: '开发工具', subtitle: '程序猿专属工具', icon: Icons.code, iconBgColor: Colors.deepPurple, tools: ['JSON格式化', '正则测试', 'Base64编解码', 'MD5加密', '时间戳转换', '网页源码获取', 'URL编码', '进制转换']),
      ToolCategory(title: '文本工具', subtitle: 'Text tools · 39个工具', icon: Icons.text_fields, iconBgColor: const Color(0xFF7A8CD0), tools: ['汉字查询', '颜文字', '文本编辑器', '随机密码', '随机一言', '诗词一言', '随机一文', '六十秒读世界', '史上今日', '搜题', '翻译', '滚动弹幕', '历史上的今天', '藏头诗生成', '随机彩虹屁', '舔狗日记', '毒鸡汤', '笑话语录', '渣男语录', '随机弱智吧问答', '猜成语生成', '随机人设', '脑筋急转弯', '随机沙雕新闻']),
      ToolCategory(title: '计算工具', subtitle: '各类计算换算', icon: Icons.calculate_outlined, iconBgColor: Colors.orange, tools: ['科学计算器', '亲戚称呼计算', '汇率换算', '房贷计算器', 'BMI计算', '单位换算', '大小写转换', '日期计算']),
      ToolCategory(title: '其他工具', subtitle: '更多好玩的应用', icon: Icons.grid_view, iconBgColor: Colors.blueGrey, tools: ['摩斯密码', '二维码生成', '条形码扫描', 'LED字幕', '随机数生成', '手持弹幕', '全屏时钟']),
      ToolCategory(title: '趣味游戏', subtitle: '休闲娱乐小游戏', icon: Icons.sports_esports_outlined, iconBgColor: Colors.redAccent, tools: ['扫雷', '2048', '数字华容道', '五子棋', '贪吃蛇', '迷宫', '数独']),
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
        List<String> matchedTools = category.tools.where((tool) => tool.toLowerCase().contains(enteredKeyword.toLowerCase())).toList();
        if (titleMatch || matchedTools.isNotEmpty) {
          results.add(ToolCategory(
            title: category.title, subtitle: category.subtitle, icon: category.icon, iconBgColor: category.iconBgColor,
            tools: titleMatch ? category.tools : matchedTools, isExpanded: true, 
          ));
        }
      }
      setState(() => _displayCategories = results);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); 

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeaderView()),
            SliverToBoxAdapter(child: _buildSearchBar()),
            SliverToBoxAdapter(child: _buildTopCards()),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => ExpandableCategoryCard(category: _displayCategories[index]),
                  childCount: _displayCategories.length,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderView() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () {
              appScaffoldKey.currentState?.openDrawer();
            },
            child: const Icon(Icons.menu, size: 28),
          ),
          const Icon(Icons.download_outlined, size: 28),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: TextField(
        controller: _searchController,
        onChanged: _runFilter,
        decoration: InputDecoration(
          hintText: '搜索你需要使用的功能或工具',
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          suffixIcon: _searchController.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, color: Colors.grey), onPressed: () {
            _searchController.clear(); _runFilter(''); FocusScope.of(context).unfocus();
          }) : null,
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildTopCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: [
          Expanded(child: _gradientCard('我的收藏', '收藏你喜欢\n或经常用的工具', [const Color(0xFFB55D6F), const Color(0xFF6C3D5A)], Icons.shopping_bag)),
          const SizedBox(width: 12),
          Expanded(child: _gradientCard('近期更新', '近期更新\n或修复的工具', [const Color(0xFF6A68A6), const Color(0xFF454B78)], Icons.outbox_rounded)),
        ],
      ),
    );
  }

  Widget _gradientCard(String title, String sub, List<Color> colors, IconData icon) {
    return Container(
      height: 90,
      decoration: BoxDecoration(gradient: LinearGradient(colors: colors), borderRadius: BorderRadius.circular(20)),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4), Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
          Positioned(right: 0, bottom: -10, child: Icon(icon, size: 60, color: Colors.white24))
        ],
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

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      decoration: BoxDecoration(color: _isExpanded ? const Color(0xFFF2F4FC) : Colors.transparent, borderRadius: BorderRadius.circular(24.0)),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              decoration: BoxDecoration(color: const Color(0xFFEDEEF6), borderRadius: BorderRadius.circular(24.0)),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(color: widget.category.iconBgColor, shape: BoxShape.circle),
                    child: Icon(widget.category.icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.category.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF333333))),
                        const SizedBox(height: 2),
                        Text(widget.category.subtitle, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                  ),
                  _isExpanded 
                    ? const Icon(Icons.arrow_drop_up, size: 30, color: Color(0xFF132D6B))
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: const Color(0xFF6B7FA2), borderRadius: BorderRadius.circular(20)),
                        child: Text('${widget.category.tools.length}个功能', style: const TextStyle(color: Colors.white, fontSize: 11)),
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
                        spacing: 12.0, runSpacing: 12.0,
                        children: widget.category.tools.map((toolName) {
                          // 👉 这是核心交互绑定逻辑！
                          return GestureDetector(
                            onTap: () {
                              if (toolName == '在线PS') {
                                // 点击在线PS，打开内置的通用套壳浏览器加载 Photopea
                                Navigator.push(context, MaterialPageRoute(
                                  builder: (context) =>  ToolWebPage(
                                    title: '在线PS', 
                                    url: 'https://www.photopea.com/'
                                  )
                                ));
                              } else {
                                // 点击其他功能，友好的全能提示
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text('正在玩命开发【$toolName】中...'), 
                                  duration: const Duration(milliseconds: 800),
                                  behavior: SnackBarBehavior.floating, // 让提示飘起来更好看
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                                ));
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                              decoration: BoxDecoration(
                                color: Colors.white, 
                                borderRadius: BorderRadius.circular(12.0), 
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 2))]
                              ),
                              child: Text(toolName, style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
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