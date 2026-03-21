import 'package:flutter/material.dart';
import 'dart:math'; 
import 'globals.dart'; 
import 'daily_news_page.dart'; 
import 'novel_module.dart';

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
                _buildNovelGrid(), 
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
                const Text('简助手', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                Text('一寸相思千万绪。人间没个安排处。', style: TextStyle(fontSize: 12, color: Colors.grey[600]), maxLines: 1, overflow: TextOverflow.ellipsis),
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
                    child: _newsItem(newsText),
                  )).toList(),
              ],
            ),
          ),
          Positioned(
            top: -8, 
            right: -8,
            child: GestureDetector(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const DailyNewsPage()));
              },
              child: const Padding(
                padding: EdgeInsets.all(8.0),
                child: Icon(Icons.remove_red_eye_outlined, color: Colors.white70, size: 20),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _newsItem(String text) {
    return Row(
      children: [
        const Icon(Icons.radio_button_checked, color: Colors.white70, size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: Tooltip(
            message: text,
            child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
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

  Widget _buildNovelGrid() {
    final List<Map<String, dynamic>> items = [
      {'title': '七猫小说', 'sub': '七猫旗下\n免费小说平台', 'code': 'qimao'},
      {'title': '香书小说', 'sub': '多种分类\n免费小说平台', 'code': 'xiangshu'},
      {'title': '唐三小说', 'sub': '多种分类\n免费小说平台', 'code': 'tangsan'},
      {'title': '小说下载', 'sub': '全本完结\nTXT小说下载', 'code': 'download'},
    ];

    final Map<String, IconData> iconMap = {
      'qimao': Icons.pets, 
      'xiangshu': Icons.auto_stories,
      'tangsan': Icons.menu_book,
      'download': Icons.file_download
    };

    return GridView.builder(
      padding: const EdgeInsets.all(16.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, crossAxisSpacing: 12.0, mainAxisSpacing: 12.0, childAspectRatio: 2.1,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return GestureDetector(
          onTap: () {
            if (item['code'] == 'qimao') {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const NovelListPage()));
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('开发中...'), duration: Duration(milliseconds: 1000)));
            }
          },
          child: Container(
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
                Positioned(right: 8, bottom: 8, child: Icon(iconMap[item['code']] ?? Icons.book, size: 36, color: Colors.blueGrey[300]))
              ],
            ),
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