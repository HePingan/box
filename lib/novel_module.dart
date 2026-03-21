import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;

// =======================================================
// 1. 小说列表页 (带下拉刷新和自动刷新)
// =======================================================
class NovelListPage extends StatefulWidget {
  const NovelListPage({super.key});

  @override
  State<NovelListPage> createState() => _NovelListPageState();
}

class _NovelListPageState extends State<NovelListPage> {
  bool _isRefreshing = true; 
  String _lastRefreshTime = "";

  @override
  void initState() {
    super.initState();
    _updateRefreshTime();
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    });
  }

  void _updateRefreshTime() {
    final now = DateTime.now();
    _lastRefreshTime = "${now.month}-${now.day} ${now.hour}:${now.minute.toString().padLeft(2, '0')}";
  }

  Future<void> _onRefresh() async {
    setState(() => _isRefreshing = true);
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) {
      setState(() {
        _updateRefreshTime();
        _isRefreshing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
          title: const Text('七猫小说', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          actions: [
            IconButton(icon: const Icon(Icons.star_border), onPressed: () {}),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _onRefresh),
          ],
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.teal,
            unselectedLabelColor: Colors.black87,
            indicatorColor: Colors.teal,
            tabs: [
              Tab(text: "全部"), Tab(text: "都市"), Tab(text: "玄幻"), Tab(text: "脑洞"), Tab(text: "穿越"),
            ],
          ),
        ),
        body: RefreshIndicator(
          color: Colors.teal,
          onRefresh: _onRefresh,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: Column(
                    children: [
                      Text(_isRefreshing ? '正在为您加载最新内容...' : '刷新完成', style: const TextStyle(fontSize: 16, color: Colors.black87)),
                      const SizedBox(height: 4),
                      Text('上次更新 $_lastRefreshTime', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildNovelListCard(context, index),
                    childCount: 5,
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
          selectedItemColor: Colors.teal,
          unselectedItemColor: Colors.grey,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: '男生'),
            BottomNavigationBarItem(icon: Icon(Icons.face_retouching_natural), label: '女生'),
            BottomNavigationBarItem(icon: Icon(Icons.search), label: '搜索'),
          ],
        ),
      ),
    );
  }

  Widget _buildNovelListCard(BuildContext context, int index) {
    final novels = [
      {'title': '你是说，我的情人是京圈大小姐？', 'tags': '杀伐果断 · 连载 · 97万字', 'img': 'https://via.placeholder.com/80x100/3A4F50/FFFFFF?text=CP'},
      {'title': '三国：老曹别猜了，我真不是卧龙', 'tags': '三国 · 穿越 · 完结 · 57万字', 'img': 'https://via.placeholder.com/80x100/2E4B3E/FFFFFF?text=SG'},
      {'title': '火红年代：开局饥荒年，我有空间农场', 'tags': '现实题材 · 连载 · 68万字', 'img': 'https://via.placeholder.com/80x100/943126/FFFFFF?text=HH'},
      {'title': '都市奇门仙医', 'tags': '高武 · 医生 · 完结 · 133万字', 'img': 'https://via.placeholder.com/80x100/4CA1A3/FFFFFF?text=DS'},
      {'title': '三寸人间', 'tags': '杀伐果断 · 完结 · 381万字', 'img': 'https://via.placeholder.com/80x100/E87A5D/FFFFFF?text=SC'},
    ];
    final novel = novels[index];

    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => NovelDetailPage(
          title: novel['title']!, coverUrl: novel['img']!, author: '飞天大土豆', wordCount: novel['tags']!.split('·').last.trim()
        )));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12.0),
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8)]),
        child: Row(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(novel['img']!, width: 60, height: 80, fit: BoxFit.cover)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(novel['title']!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 16),
                  Text(novel['tags']!, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

// =======================================================
// 2. 小说详情页&章节列表
// =======================================================
class NovelDetailPage extends StatelessWidget {
  final String title;
  final String coverUrl;
  final String author;
  final String wordCount;

  const NovelDetailPage({super.key, required this.title, required this.coverUrl, required this.author, required this.wordCount});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text('小说详情', style: TextStyle(color: Colors.black)),
        backgroundColor: const Color(0xFFF7F8FA),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [TextButton(onPressed: (){}, child: const Text('收藏', style: TextStyle(color: Colors.black87, fontSize: 16)))],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(coverUrl, width: 100, height: 140, fit: BoxFit.cover)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.teal.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: Text(author, style: const TextStyle(color: Colors.teal, fontSize: 12))),
                            const SizedBox(width: 8),
                            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: Text(wordCount, style: const TextStyle(color: Colors.blue, fontSize: 12))),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text("举头三尺无神明，掌心三寸是人间。这是继经典之作后，创作的第五部长篇小说。", style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.5), maxLines: 3, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  )
                ],
              ),
            ),
            const Divider(color: Colors.black12, thickness: 1),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, crossAxisSpacing: 12.0, mainAxisSpacing: 12.0, childAspectRatio: 3.5,
                ),
                itemCount: 16,
                itemBuilder: (context, index) {
                  List<String> mockChapters = [
                    "第一章 我要减肥！", "第二章 王宝乐", "第三章 好同学", "第四章 飘渺道院",
                    "第五章 特招学子", "第六章 麻烦大了", "第七章 全民矿工", "第八章 才智",
                    "第九章 噬气诀", "第十章 战武系", "第十一章 老师", "第十二章 突破",
                    "第十三章 化清丹", "第十四章 优势", "第十五章 抢钱", "第十六 上品"
                  ];
                  return InkWell(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => ReaderPage(
                        chapterTitle: mockChapters[index],
                        chapterUrl: "https://example.com/test", 
                      )));
                    },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                      child: Text(mockChapters[index], style: const TextStyle(fontSize: 14, color: Colors.black87)),
                    ),
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}

// =======================================================
// 3. 沉浸式小说阅读器 (支持真实网络爬取解析的版本)
// =======================================================
class ReaderPage extends StatefulWidget {
  final String chapterTitle;
  final String chapterUrl;

  const ReaderPage({
    super.key, 
    required this.chapterTitle,
    this.chapterUrl = '', 
  });

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  String _content = '';      
  bool _isLoading = true;    
  bool _isError = false;     

  @override
  void initState() {
    super.initState();
    _fetchNovelContentFromWeb();
  }

  Future<void> _fetchNovelContentFromWeb() async {
    try {
      if (widget.chapterUrl.isEmpty || widget.chapterUrl == 'https://example.com/test') {
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          setState(() {
            _content = "      炎炎夏日，位于联邦东部的池云雨林，云雾弥漫，好似一层薄纱环绕，一棵棵参天古树，纵横交错，繁茂的树冠中，时而有几只飞鸟腾空而起。\n\n      天空上，那仿佛可以永恒存在的太阳，已然不再是人们记忆里的样子，而是在多年前，被一把庞大到难以形容的青铜古剑，直接刺穿，露出小半个剑尖！\n\n      这古剑似经历万古岁月，自星空而来，透出无尽沧桑，更有一股强烈的威压，形成光晕，笼罩苍穹，仿佛能镇压大地，让众生膜拜！";
            _isLoading = false;
          });
        }
        return;
      }

      final response = await http.get(
        Uri.parse(widget.chapterUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/89.0.4389.105 Mobile Safari/537.36',
        }
      );

      if (response.statusCode == 200) {
        var document = parse(response.body);
        var contentElement = document.querySelector('#content');

        if (contentElement != null) {
           String rawText = contentElement.text;
           if (mounted) {
             setState(() {
               _content = rawText;
               _isLoading = false;
             });
           }
        } else {
           throw Exception('网页里没找到小说正文容器');
        }
      } else {
        throw Exception('网页访问失败：${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isError = true;
          _isLoading = false;
          _content = "抓取失败了，原因：\n$e";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1E9CE),
      body: SafeArea(
        child: Stack(
          children: [
            if (_isLoading)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.brown),
                    const SizedBox(height: 16),
                    Text('正在努力从全网搜索文字...', style: TextStyle(color: Colors.brown[400])),
                  ],
                ),
              )
            else if (_isError)
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Center(child: Text(_content, style: const TextStyle(color: Colors.red, fontSize: 16))),
              )
            else 
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 100), 
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.chapterTitle, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF333333))),
                    const SizedBox(height: 24),
                    Text(
                      _content,
                      style: const TextStyle(fontSize: 18, height: 1.8, letterSpacing: 1.0, color: Color(0xFF2C2C2C)),
                    ),
                  ],
                ),
              ),
            
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                decoration: const BoxDecoration(
                  color: Color(0xFFEBE0C3),
                  border: Border(top: BorderSide(color: Colors.black12, width: 0.5))
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildBottomAction(Icons.format_list_bulleted, '目录'),
                    _buildBottomAction(Icons.arrow_back, '上一章'),
                    _buildBottomAction(Icons.arrow_forward, '下一章'),
                    _buildBottomAction(Icons.settings_outlined, '设置'),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildBottomAction(IconData icon, String text) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.black87, width: 1.5)),
          child: Icon(icon, color: Colors.black87, size: 22),
        ),
        const SizedBox(height: 4),
        Text(text, style: const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w500))
      ],
    );
  }
}