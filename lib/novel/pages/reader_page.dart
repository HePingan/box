import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../novel_module.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.detail,
    required this.initialChapterIndex,
  });

  final NovelDetail detail;
  final int initialChapterIndex;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

enum _JumpTarget { start, end, restoreDb }

class _ReaderPageState extends State<ReaderPage> {
  late PageController _pageController;
  Timer? _saveDebounce;

  late int _chapterIndex;
  bool _loading = true;
  bool _isError = false;
  bool _fromCache = false;
  bool _showMenu = false;

  String _title = '';
  String _content = '';
  ReaderSettings _settings = const ReaderSettings();

  List<String> _textPages = [];
  
  // 用于判定是否需要重新铺切的缓存变量，消除重复计算
  double _lastMaxW = 0.0;
  double _lastMaxH = 0.0;

  _JumpTarget _jumpTarget = _JumpTarget.restoreDb;

  @override
  void initState() {
    super.initState();
    _chapterIndex = widget.initialChapterIndex;
    _pageController = PageController();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _bootstrap();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _saveProgress();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final settings = await NovelModule.repository.getReaderSettings();
    if (!mounted) return;
    setState(() => _settings = settings);
    await _loadChapter(forceRefresh: false, target: _JumpTarget.restoreDb);
  }

  void _onPageChanged(int pageIndex) {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), _saveProgress);
    setState(() {}); // 刷新页面进度与底部页码
  }

  Future<void> _saveProgress() async {
    if (!_pageController.hasClients) return;
    final chapter = widget.detail.chapters[_chapterIndex];
    await NovelModule.repository.saveProgress(
      ReadingProgress(
        bookId: widget.detail.book.id,
        chapterIndex: _chapterIndex,
        chapterTitle: chapter.title,
        scrollOffset: _pageController.page ?? 0.0,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<double?> _getSavedProgress() async {
    final progress = await NovelModule.repository.getProgress(widget.detail.book.id);
    if (progress != null && progress.chapterIndex == _chapterIndex) {
      return progress.scrollOffset;
    }
    return null;
  }

  Future<void> _loadChapter({
    required bool forceRefresh,
    required _JumpTarget target,
  }) async {
    setState(() {
      _loading = true;
      _isError = false;
      _showMenu = false;
      _jumpTarget = target;
    });

    try {
      final data = await NovelModule.repository.fetchChapter(
        detail: widget.detail,
        chapterIndex: _chapterIndex,
        forceRefresh: forceRefresh,
      );

      if (!mounted) return;
      
      // ✅ 终极清洗：彻底清理小说网站带来的乱七八糟格式，同时绝对保留每段开头的全角缩进
      final rawText = data.content.trim(); 
      final lines = rawText.split('\n');
      final formattedLines = <String>[];
      
      for (var currentLine in lines) {
        var t = currentLine.trim();
        // 清理原有的乱码缩进，统一使用规范的两个全角空格
        t = t.replaceAll(RegExp(r'^[\s\u3000]+'), ''); 
        if (t.isNotEmpty) {
          formattedLines.add('\u3000\u3000$t'); 
        }
      }

      setState(() {
        _title = data.title;
        // 绝对不要在 join 之后再去 trim ！那样会把第一张拼死拼活加进去的空格删掉！
        _content = formattedLines.join('\n'); 
        _fromCache = data.fromCache;
      });

      // 如果屏幕尺寸数据已经存在，立即触发重新排版
      if (_lastMaxW > 0 && _lastMaxH > 0) {
        setState(() => _textPages = []); 
      }

      // 预加载下一章，体验起飞
      final nextIndex = _chapterIndex + 1;
      if (nextIndex < widget.detail.chapters.length) {
        NovelModule.repository.prefetchChapter(
          detail: widget.detail,
          chapterIndex: nextIndex,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isError = true;
        _content = '章节加载失败：$e';
      });
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _switchChapter(int index, {required _JumpTarget target}) async {
    if (index < 0 || index >= widget.detail.chapters.length) return;
    setState(() {
      _chapterIndex = index;
      _content = '';
    });
    await _loadChapter(forceRefresh: false, target: target);
  }

  // 🚀 终极精一切割算法，带入严格数学公式
  void _calculatePages(double fitWidth, double firstPageHeight, double normalPageHeight) async {
    if (_content.isEmpty) return;

    final style = TextStyle(
      fontSize: _settings.fontSize,
      height: _settings.lineHeight,
      letterSpacing: 0.6,
      color: _textColor,
    );

    final List<String> pages = [];
    int start = 0;
    final text = _content;
    final painter = TextPainter(textDirection: TextDirection.ltr);

    while (start < text.length) {
      // ✅ 终极绝杀：如果跨页后的第一个字符又特么是换行符（会导致顶部莫名出现大块空白），无情跳过！
      while (start < text.length && text[start] == '\n') {
        start++;
      }
      if (start >= text.length) break;

      int low = start;
      int high = text.length;
      int mid;
      int best = start;

      // 第一页要给大标题让路，高度比后面的页要矮一点
      double currentMaxHeight = (pages.isEmpty) ? firstPageHeight : normalPageHeight;

      while (low <= high) {
        mid = low + ((high - low) ~/ 2);
        painter.text = TextSpan(text: text.substring(start, mid), style: style);
        painter.layout(maxWidth: fitWidth);

        if (painter.height <= currentMaxHeight) {
          best = mid;
          low = mid + 1;
        } else {
          high = mid - 1;
        }
      }

      // 如果一个字都塞不下（不可能，但做个保底防死循环），硬塞一个字
      if (best == start) best = start + 1; 

      pages.add(text.substring(start, best));
      start = best;
    }

    if (!mounted) return;
    setState(() {
      _textPages = pages;
    });

    // 页面铺设完毕，执行历史位置跳转或首尾跳转
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_pageController.hasClients || _textPages.isEmpty) return;
      
      int targetPage = 0;
      if (_jumpTarget == _JumpTarget.end) {
        targetPage = _textPages.length - 1;
      } else if (_jumpTarget == _JumpTarget.restoreDb) {
        final savedOffset = await _getSavedProgress();
        if (savedOffset != null) {
          targetPage = savedOffset.clamp(0, _textPages.length - 1).toInt();
        }
      }

      if (targetPage > 0 && targetPage < _textPages.length) {
        _pageController.jumpToPage(targetPage);
      } else {
        _pageController.jumpToPage(0);
      }
      
      _saveProgress(); 
    });
  }

  void _onScreenTap(TapUpDetails details) {
    if (_showMenu) {
      setState(() => _showMenu = false);
      return;
    }

    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    final x = details.globalPosition.dx;
    final y = details.globalPosition.dy;

    // 点击中间1/3呼出菜单
    if (x > width * 0.33 && x < width * 0.66 && y > height * 0.33 && y < height * 0.66) {
      setState(() => _showMenu = true);
      return;
    }
    
    // 点击左侧1/3上翻
    if (x < width * 0.33) {
      if (_pageController.page == 0) {
        _switchChapter(_chapterIndex - 1, target: _JumpTarget.end);
      } else {
        _pageController.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
      }
    } 
    // 点击右侧1/3下翻
    else {
      if (_pageController.page?.toInt() == _textPages.length - 1) {
        _switchChapter(_chapterIndex + 1, target: _JumpTarget.start);
      } else {
        _pageController.nextPage(duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
      }
    }
  }

  Future<void> _openDirectory() async {
    setState(() => _showMenu = false);

    // ✅ 让目录自动滑到当前章节附近，再也不用从第一章往下划了！
    double initOffset = 0.0;
    if (_chapterIndex > 4) {
      initOffset = (_chapterIndex - 4) * 52.0; 
    }
    final scrollController = ScrollController(initialScrollOffset: initOffset);

    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bgColor,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.75,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('目录', style: TextStyle(color: _textColor, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
                Divider(height: 1, color: _textColor.withOpacity(0.1)),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: widget.detail.chapters.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: _textColor.withOpacity(0.05)),
                    itemBuilder: (_, i) {
                      final chapter = widget.detail.chapters[i];
                      final current = i == _chapterIndex;
                      return ListTile(
                        selected: current,
                        selectedTileColor: current ? Colors.orange.withOpacity(0.1) : Colors.transparent,
                        title: Text(chapter.title, style: TextStyle(color: current ? Colors.orange : _textColor)),
                        onTap: () => Navigator.pop(context, i),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected != null) {
      await _switchChapter(selected, target: _JumpTarget.start);
    }
  }

  Future<void> _updateSettings(ReaderSettings next) async {
    setState(() => _settings = next);
    await NovelModule.repository.saveReaderSettings(next);
    // 设置改变后，清空已有的切割缓存，强制下一次 build 时重新按照新字体大小切割
    setState(() => _textPages = []); 
  }

  Future<void> _openSettings() async {
    setState(() => _showMenu = false);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _bgColor, 
      builder: (context) {
        return StatefulBuilder(
          builder: (_, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  runSpacing: 16,
                  children: [
                    Text('阅读设置', style: TextStyle(color: _textColor, fontSize: 18, fontWeight: FontWeight.bold)),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('字体大小', style: TextStyle(color: _textColor.withOpacity(0.7))),
                        Slider(
                          value: _settings.fontSize,
                          min: 14, max: 30, divisions: 16,
                          activeColor: Colors.orange, inactiveColor: _textColor.withOpacity(0.2),
                          onChanged: (v) {
                            final next = _settings.copyWith(fontSize: v);
                            setSheetState(() {});
                            _updateSettings(next);
                          },
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('行距', style: TextStyle(color: _textColor.withOpacity(0.7))),
                        Slider(
                          value: _settings.lineHeight,
                          min: 1.4, max: 2.4, divisions: 10,
                          activeColor: Colors.orange, inactiveColor: _textColor.withOpacity(0.2),
                          onChanged: (v) {
                            final next = _settings.copyWith(lineHeight: v);
                            setSheetState(() {});
                            _updateSettings(next);
                          },
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFCBE5D2), foregroundColor: Colors.black87),
                          onPressed: () => _updateSettings(_settings.copyWith(themeMode: ReaderThemeMode.warm)),
                          child: const Text('护眼'),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF1E9CE), foregroundColor: Colors.black87),
                          onPressed: () => _updateSettings(_settings.copyWith(themeMode: ReaderThemeMode.paper)),
                          child: const Text('纸张'),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF141414), foregroundColor: Colors.white70),
                          onPressed: () => _updateSettings(_settings.copyWith(themeMode: ReaderThemeMode.dark)),
                          child: const Text('夜间'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 色彩配置引擎
  Color get _bgColor {
    switch (_settings.themeMode) {
      case ReaderThemeMode.warm: return const Color(0xFFCBE5D2); 
      case ReaderThemeMode.paper: return const Color(0xFFF1E9CE);
      case ReaderThemeMode.dark: return const Color(0xFF141414);
    }
  }

  Color get _textColor {
    switch (_settings.themeMode) {
      case ReaderThemeMode.dark: return const Color(0xFF707070);
      case ReaderThemeMode.warm: return const Color(0xFF161F1A); 
      case ReaderThemeMode.paper: return const Color(0xFF2C2C2C);
    }
  }

  Widget _action(IconData icon, String text, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.35 : 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: _textColor),
            const SizedBox(height: 2),
            Text(text, style: TextStyle(fontSize: 12, color: _textColor)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalChapters = widget.detail.chapters.length;

    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        top: false, // 彻底关闭系统默认预留，全责交接给下面代码算出的高度
        bottom: false,
        child: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: _onScreenTap,
              child: _loading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: _textColor.withOpacity(0.5)),
                          const SizedBox(height: 14),
                          Text('正在铺切排版...', style: TextStyle(color: _textColor.withOpacity(0.5))),
                        ],
                      ),
                    )
                  : _isError
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(_content, style: const TextStyle(color: Colors.red, fontSize: 16)),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            // 🚀 物理断头台：最严谨的高度控制计算学
                            final double maxW = constraints.maxWidth;
                            final double maxH = constraints.maxHeight;
                            final double topPad = MediaQuery.of(context).padding.top;
                            
                            // 文字容器需要被扣除的所有间距：系统刘海顶边(topPad) + 容器自身顶内距(8.0) + 容器自身底内距(8.0)
                            final double paddingTotal = topPad + 8.0 + 8.0; 
                            
                            // 第一页特权：多扣除大标题高度(46.0)，预留大标题底部留白(24.0)
                            final double absoluteFirstTextH = maxH - paddingTotal - 46.0 - 24.0;
                            // 后续普通页：只需要扣除小标题(24.0)以及底部阅读进度高度(24.0)
                            final double absoluteNormalTextH = maxH - paddingTotal - 24.0 - 24.0;
                            
                            // 实际的画布宽度：屏幕宽度 - 左右两侧各 20 留白 = 40
                            final double fitWidth = maxW - 40; 

                            // 当屏幕尺寸发生变更，或内容为空时，再唤醒天团进行切页
                            if (fitWidth != _lastMaxW || absoluteNormalTextH != _lastMaxH || _textPages.isEmpty) {
                              _lastMaxW = fitWidth;
                              _lastMaxH = absoluteNormalTextH;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _calculatePages(fitWidth, absoluteFirstTextH, absoluteNormalTextH);
                              });
                            }

                            if (_textPages.isEmpty) return const SizedBox.shrink(); 

                            return PageView.builder(
                              controller: _pageController,
                              itemCount: _textPages.length,
                              onPageChanged: _onPageChanged,
                              physics: const BouncingScrollPhysics(),
                              itemBuilder: (context, index) {
                                return Container(
                                  // 这里必须强依赖刚才数学公式里的 paddingTotal！
                                  padding: EdgeInsets.fromLTRB(20, topPad + 8, 20, 8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // 头部组件
                                      if (index == 0)
                                        Container(
                                          height: 46, // 对应公式里的第一页扣除项
                                          alignment: Alignment.bottomLeft,
                                          padding: const EdgeInsets.only(bottom: 8),
                                          child: Text(
                                            _title.isNotEmpty ? _title : widget.detail.chapters[_chapterIndex].title,
                                            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: _textColor, height: 1.1),
                                            maxLines: 1, overflow: TextOverflow.ellipsis,
                                          ),
                                        )
                                      else
                                        SizedBox(
                                          height: 24, // 对应公式里的普通页扣除项
                                          child: Align(
                                            alignment: Alignment.topLeft,
                                            child: Text(
                                              _title.isNotEmpty ? _title : widget.detail.chapters[_chapterIndex].title,
                                              style: TextStyle(fontSize: 10, color: _textColor.withOpacity(0.5), fontWeight: FontWeight.w500),
                                              maxLines: 1,
                                            ),
                                          ),
                                        ),
                                      
                                      // 文字渲染层（因为有了严密护城河计算保镖，此时这里再无可能是半截字出没的地方）
                                      Expanded(
                                        child: Text(
                                          _textPages[index],
                                          style: TextStyle(
                                            fontSize: _settings.fontSize,
                                            height: _settings.lineHeight,
                                            letterSpacing: 0.6,
                                            color: _textColor,
                                          ),
                                        ),
                                      ),
                                      
                                      // 底部组件
                                      SizedBox(
                                        height: 24, // 对应公式里的底部进度页扣除项
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                widget.detail.book.title,
                                                style: TextStyle(fontSize: 11, color: _textColor.withOpacity(0.5)),
                                                maxLines: 1,
                                              ),
                                            ),
                                            Text(
                                              '${index + 1}/${_textPages.length}   ${((index + 1) / _textPages.length * 100).toStringAsFixed(1)}%',
                                              style: TextStyle(fontSize: 11, color: _textColor.withOpacity(0.5)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
            ),

            // 功能菜单
            if (_showMenu)
              Positioned(
                top: 0, left: 0, right: 0,
                child: Container(
                  padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
                  decoration: BoxDecoration(
                    color: _bgColor,
                    border: Border(bottom: BorderSide(color: _textColor.withOpacity(0.08), width: 1)),
                  ),
                  height: 56 + MediaQuery.of(context).padding.top,
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back_ios_new_rounded, color: _textColor, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          widget.detail.book.title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _textColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 底部操作栏
            if (_showMenu)
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: Container(
                  padding: const EdgeInsets.only(top: 16, bottom: 24),
                  decoration: BoxDecoration(
                    color: _bgColor,
                    border: Border(top: BorderSide(color: _textColor.withOpacity(0.08), width: 1)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _action(Icons.format_list_bulleted, '目录', _openDirectory),
                      _action(
                        Icons.skip_previous_rounded, '上一章',
                        _chapterIndex > 0 ? () {
                          _showMenu = false;
                          _switchChapter(_chapterIndex - 1, target: _JumpTarget.start);
                        } : null,
                      ),
                      _action(
                        Icons.skip_next_rounded, '下一章',
                        _chapterIndex < totalChapters - 1 ? () {
                          _showMenu = false;
                          _switchChapter(_chapterIndex + 1, target: _JumpTarget.start);
                        } : null,
                      ),
                      _action(Icons.settings_outlined, '设置', _openSettings),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}