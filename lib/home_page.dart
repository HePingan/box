import 'package:flutter/material.dart';
import 'dart:math'; 
import 'globals.dart'; 
import 'daily_news_page.dart'; 
import 'novel_module.dart';

// 👉 新增的两个引入：本地书架管理、小说列表/详情页（如果有红波浪线，在VSCode里按 Alt+Enter 修复一下路径即可）
import 'novel/core/bookshelf_manager.dart';
import 'novel/pages/novel_detail_page.dart'; 

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => true; 

  String _todayDateStr = "";        
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
    String month = now.month.toString().padLeft(2, '0');
    String day = now.day.toString().padLeft(2, '0');
    _todayDateStr = "$month月$day日";
  }

  Future<void> _fetchDailyNews() async {
    setState(() { _isLoadingNews = true; });
    try {
      await Future.delayed(const Duration(milliseconds: 1500));
      final random = Random().nextInt(10);
      _newsList = [
        "漂白鸡爪掀行业震荡 多品牌回应",
        "商务部回应美方对华发起301调查",
        "又被曝！曼玲粥铺被扒“糊弄式”堂食",
        "编号：$random 备用内容" 
      ];
    } catch (e) {
      _newsList = ["网络加载失败，请下拉重试"];
    } finally {
      if (mounted) {
        setState(() { _isLoadingNews = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      body: DefaultTabController(
        length: 5,
        child: SafeArea(
          child: NestedScrollView(
            headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
              return <Widget>[
                SliverToBoxAdapter(child: _buildTopHeader()),
                SliverToBoxAdapter(child: _buildDailyNewsCard()),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SliverAppBarDelegate(
                    TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      indicatorColor: Colors.blue[700],
                      indicatorSize: TabBarIndicatorSize.label,
                      indicatorWeight: 3.0,
                      labelColor: Colors.blue[700],
                      unselectedLabelColor: Colors.black54,
                      dividerColor: Colors.grey[300],
                      tabs: const [
                        Tab(child: Row(children: [Icon(Icons.local_fire_department_outlined, size: 20), SizedBox(width: 4), Text("推荐", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))])),
                        Tab(child: Row(children: [Icon(Icons.music_note_outlined, size: 20), SizedBox(width: 4), Text("音乐", style: TextStyle(fontSize: 16))])),
                        Tab(child: Row(children: [Icon(Icons.play_circle_outline, size: 20), SizedBox(width: 4), Text("影视", style: TextStyle(fontSize: 16))])),
                        Tab(child: Row(children: [Icon(Icons.image_outlined, size: 20), SizedBox(width: 4), Text("漫画", style: TextStyle(fontSize: 16))])),
                        Tab(child: Row(children: [Icon(Icons.menu_book_outlined, size: 20), SizedBox(width: 4), Text("小说", style: TextStyle(fontSize: 16))])),
                      ],
                    ),
                  ),
                ),
              ];
            },
            body: TabBarView(
              children: [
                _buildRecommendGrid(),
                const Center(child: Text("音乐功能区开发中...")),
                _buildVideoGrid(),
                const Center(child: Text("漫画功能区开发中...")),
                const NovelTabArea(), // 独立的小说书架与书源控制区
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              appScaffoldKey.currentState?.openDrawer(); 
            },
            child: const Icon(Icons.menu, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Geek工具箱', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                Text('计划赶不上变化😭', style: TextStyle(fontSize: 12, color: Colors.grey[600]), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.file_download_outlined, size: 28), onPressed: () {}),
        ],
      ),
    );
  }

  Widget _buildDailyNewsCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(color: const Color(0xFF2C3228), borderRadius: BorderRadius.circular(20)),
      child: Stack(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('视界日报', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                const SizedBox(height: 4),
                Text('Daily News - $_todayDateStr', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 16),
                if (_isLoadingNews)
                  const Padding(
                    padding: EdgeInsets.only(top: 20.0),
                    child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2))),
                  )
                else
                  ..._newsList.take(3).map((newsText) => Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        const Icon(Icons.radio_button_checked, color: Colors.white70, size: 14),
                        const SizedBox(width: 8),
                        Expanded(child: Tooltip(message: newsText, child: Text(newsText, style: const TextStyle(color: Colors.white, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis))),
                      ],
                    ),
                  )).toList(),
              ],
            ),
          ),
          Positioned(
            top: -8, right: -8,
            child: GestureDetector(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const DailyNewsPage()));
              },
              child: const Padding(padding: EdgeInsets.all(8.0), child: Icon(Icons.remove_red_eye_outlined, color: Colors.white70, size: 20)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildRecommendGrid() {
    final List<Map<String, dynamic>> items = [
      {'title': '资源嗅探', 'sub': '嗅探网页中的\n音视图片等资源', 'color': Colors.amber},
      {'title': '应用中心', 'sub': '海量实用软件\n破解版游戏下载', 'color': Colors.blue},
      {'title': '怀旧游戏', 'sub': '街机、FC等\n童年怀旧游戏', 'color': Colors.blue[700]},
      {'title': '短视频解析', 'sub': '抖音、快手等\n短视频去水印', 'color': Colors.lightGreen},
    ];
    return _buildGridView(items);
  }

  Widget _buildVideoGrid() {
    final List<Map<String, dynamic>> items = [
      {'title': '河马短剧', 'sub': '免费在线观看', 'color': Colors.brown},
      {'title': '红果短剧', 'sub': '免费在线观看', 'color': Colors.red},
      {'title': '影视搜索', 'sub': '搜索影视资源', 'color': Colors.greenAccent},
      {'title': '暴风资源', 'sub': '电影、电视剧等', 'color': Colors.blueAccent},
    ];
    return _buildGridView(items);
  }

  Widget _buildGridView(List<Map<String, dynamic>> items) {
    return GridView.builder(
      padding: const EdgeInsets.all(16.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, crossAxisSpacing: 12.0, mainAxisSpacing: 12.0, childAspectRatio: 2.1,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Container(
          decoration: BoxDecoration(color: const Color(0xFFEDEEF0), borderRadius: BorderRadius.circular(16.0)),
          child: Stack(
            children: [
              Positioned(
                left: 12, top: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item['title'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87)),
                    const SizedBox(height: 4),
                    Text(item['sub'], style: TextStyle(fontSize: 11, color: Colors.grey[600], height: 1.2)),
                  ],
                ),
              ),
              Positioned(right: 8, bottom: 8, child: Container(width: 36, height: 36, decoration: BoxDecoration(color: item['color'], shape: BoxShape.circle), child: const Center(child: Icon(Icons.star, color: Colors.white, size: 20))))
            ],
          ),
        );
      },
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);
  final TabBar _tabBar;
  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(color: const Color(0xFFF7F8FA), child: _tabBar);
  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => false;
}


// =========================================================================
// 👇 全新升级版：支持动画折叠的独立小说板块组件（已接入真实书架数据）
// =========================================================================

class NovelTabArea extends StatefulWidget {
  const NovelTabArea({super.key});

  @override
  State<NovelTabArea> createState() => _NovelTabAreaState();
}

class _NovelTabAreaState extends State<NovelTabArea> {
  List<Map<String, dynamic>> _savedBooks = [];
  bool _isLoadingBooks = true;

  bool _isBookshelfExpanded = true;
  bool _isSourcesExpanded = true;

  @override
  void initState() {
    super.initState();
    _loadBookshelf();
  }

  // 👉 获取真实的本地书架，并关联阅读进度
  Future<void> _loadBookshelf() async {
    setState(() => _isLoadingBooks = true);
    
    try {
      // 1. 获取通过详情页“加入书架”存储的所有书籍
      final books = await BookshelfManager.getBookshelf();
      final List<Map<String, dynamic>> displayList = [];

      // 2. 遍历获取阅读进度记录
      for (var book in books) {
        final progress = await NovelModule.repository.getProgress(book.id);
        displayList.add({
          'bookId': book.id,
          'title': book.title,
          'cover': book.coverUrl,
          'chapter': progress != null ? progress.chapterTitle : '未读此书',
          'rawBook': book, 
        });
      }

      if (mounted) {
        setState(() {
          _savedBooks = displayList;
          _isLoadingBooks = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingBooks = false);
    }
  }

  Widget _buildSectionHeader({
    required String title, required bool isExpanded, required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      splashColor: Colors.transparent, highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
            AnimatedRotation(
              turns: isExpanded ? 0.25 : 0.0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBookshelfSection(),
          _buildNovelSourcesSection(),
          const SizedBox(height: 30), 
        ],
      ),
    );
  }

  Widget _buildBookshelfSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
         _buildSectionHeader(
           title: '我的书架', isExpanded: _isBookshelfExpanded,
           onTap: () => setState(() => _isBookshelfExpanded = !_isBookshelfExpanded),
         ),
         AnimatedSize(
           duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic, alignment: Alignment.topCenter,
           child: _isBookshelfExpanded
              ? (_isLoadingBooks
                  ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
                  : (_savedBooks.isEmpty ? _buildEmptyBookshelf() : _buildBookshelfList()))
              : const SizedBox(width: double.infinity, height: 0), 
         ),
      ],
    );
  }

  Widget _buildEmptyBookshelf() {
    return Container(
      height: 120, margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!)),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_stories_outlined, size: 36, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text('书架空空如也，快去寻宝吧', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildBookshelfList() {
    return SizedBox(
      height: 170, 
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal, physics: const BouncingScrollPhysics(),
        itemCount: _savedBooks.length,
        itemBuilder: (context, index) {
          final bookMap = _savedBooks[index];
          return GestureDetector(
            onTap: () {
               // 👉 重点突破：点击书架上的书，跳转到详情页，返回时刷新书架信息（以便最新阅读进度更新）
               Navigator.push(
                 context, 
                 MaterialPageRoute(builder: (_) => NovelDetailPage(entryBook: bookMap['rawBook']))
               ).then((_) => _loadBookshelf()); 
            },
            child: Container(
              width: 100, margin: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6), color: Colors.grey[300],
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(2, 2))],
                        image: DecorationImage(image: NetworkImage(bookMap['cover']), onError: (e, s) {}, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(bookMap['title'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(bookMap['chapter'], style: TextStyle(fontSize: 11, color: Colors.blueGrey[500]), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNovelSourcesSection() {
    final List<Map<String, dynamic>> items = [
      {'title': '猫眼看书', 'sub': '猫眼看书🐱\n免费小说平台', 'code': 'qimao'},
      {'title': '等待添加', 'sub': '多种分类\n免费小说平台', 'code': 'xiangshu'},
      {'title': '等待添加', 'sub': '多种分类\n免费小说平台', 'code': 'tangsan'},
      {'title': '等待添加', 'sub': '全本完结\nTXT小说下载', 'code': 'download'},
    ];
    final Map<String, IconData> iconMap = {
      'qimao': Icons.pets, 'xiangshu': Icons.auto_stories, 'tangsan': Icons.menu_book, 'download': Icons.file_download
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(title: '精选书源', isExpanded: _isSourcesExpanded, onTap: () => setState(() => _isSourcesExpanded = !_isSourcesExpanded)),
        
        AnimatedSize(
          duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic, alignment: Alignment.topCenter,
          child: _isSourcesExpanded
              ? GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), 
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12.0, mainAxisSpacing: 12.0, childAspectRatio: 2.1),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return GestureDetector(
                      onTap: () {
                        if (item['code'] == 'qimao') {
                          // 👉 进入书源找书，退出来时也会重刷下书架，保证新添加的书出现
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const NovelListPage())).then((_) => _loadBookshelf());
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('开发中...')));
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(color: const Color(0xFFEDEEF0), borderRadius: BorderRadius.circular(16.0)),
                        child: Stack(
                          children: [
                            Positioned(left: 12, top: 12, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item['title'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87)), const SizedBox(height: 4), Text(item['sub'], style: TextStyle(fontSize: 11, color: Colors.grey[600], height: 1.2))])),
                            Positioned(right: 8, bottom: 8, child: Icon(iconMap[item['code']] ?? Icons.book, size: 36, color: Colors.blueGrey[300]))
                          ],
                        ),
                      ),
                    );
                  },
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }
}