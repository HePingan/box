import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

class _ScrollChapterItem {
  final int index;
  final String title;
  final String content;
  final GlobalKey key = GlobalKey();

  _ScrollChapterItem({
    required this.index,
    required this.title,
    required this.content,
  });
}

class _ReaderPageState extends State<ReaderPage> {
  late final PageController _pageController;
  late final ScrollController _scrollController;

  Timer? _saveDebounce;
  Timer? _settingsSaveDebounce;

  late int _chapterIndex;

  bool _loading = true;
  bool _isError = false;
  bool _showMenu = false;

  bool _isScrollMode = false; 

  String _title = '';
  String _content = '';
  List<String> _textPages = <String>[];
  double _lastFitWidth = 0.0;
  double _lastNormalHeight = 0.0;
  bool _isPaginating = false;
  final Map<String, List<String>> _pageCache = <String, List<String>>{};

  List<_ScrollChapterItem> _scrollItems = [];
  bool _loadingNextScroll = false;

  ReaderSettings _settings = const ReaderSettings();
  _JumpTarget _jumpTarget = _JumpTarget.restoreDb;

  @override
  void initState() {
    super.initState();
    _chapterIndex = widget.initialChapterIndex;
    _pageController = PageController();
    _scrollController = ScrollController()..addListener(_onProgressChanged);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _bootstrap();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _settingsSaveDebounce?.cancel();
    _saveProgress();

    _scrollController
      ..removeListener(_onProgressChanged)
      ..dispose();
    _pageController.dispose();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final settings = await NovelModule.repository.getReaderSettings();
    if (!mounted) return;
    setState(() => _settings = settings);
    await _loadChapter(forceRefresh: false, target: _JumpTarget.restoreDb);
  }

  void _updateScrollProgressAndDB() {
    if (!_isScrollMode || _scrollItems.isEmpty) return;

    final topInset = MediaQuery.of(context).padding.top;
    final targetY = topInset + 60.0; 

    int activeIdx = _scrollItems.first.index;
    double activeOffset = 0.0;

    for (int i = _scrollItems.length - 1; i >= 0; i--) {
      final item = _scrollItems[i];
      final ctx = item.key.currentContext;
      if (ctx != null) {
        final box = ctx.findRenderObject() as RenderBox?;
        if (box != null) {
          final topY = box.localToGlobal(Offset.zero).dy;
          if (topY <= targetY) {
            activeIdx = item.index;
            activeOffset = (targetY - topY).clamp(0.0, double.infinity);
            break;
          }
        }
      }
    }

    if (_chapterIndex != activeIdx) {
      setState(() => _chapterIndex = activeIdx);
    }

    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 320), () {
      NovelModule.repository.saveProgress(
        ReadingProgress(
          bookId: widget.detail.book.id,
          chapterIndex: activeIdx,
          chapterTitle: widget.detail.chapters[activeIdx].title,
          scrollOffset: _encodeProgressOffset(activeOffset),
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    });
  }

  void _onProgressChanged() {
    if (_isScrollMode) {
      if (!_scrollController.hasClients || !mounted) return;
      _updateScrollProgressAndDB();
      return;
    }

    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 320), _saveProgress);
    if (mounted) setState(() {});
  }

  void _onPageChanged(int viewIndex) {
    if (_isScrollMode || _textPages.isEmpty) return;

    final tail = _textPages.length + 1;
    if (viewIndex == 0) {
      if (_chapterIndex > 0) {
        _switchChapter(_chapterIndex - 1, target: _JumpTarget.end);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients) _pageController.jumpToPage(1);
        });
      }
      return;
    }

    if (viewIndex == tail) {
      if (_chapterIndex < widget.detail.chapters.length - 1) {
        _switchChapter(_chapterIndex + 1, target: _JumpTarget.start);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients) _pageController.jumpToPage(_textPages.length);
        });
      }
      return;
    }

    _onProgressChanged();
  }

  double _encodeProgressOffset(double raw) => _isScrollMode ? raw : -(raw + 1.0);

  double _decodePageOffset(double saved) {
    if (saved < 0) return -saved - 1.0;
    if (saved <= 500) return saved;
    return 0.0;
  }

  double _decodeScrollOffset(double saved) => saved < 0 ? 0.0 : saved;

  Future<void> _saveProgress() async {
    if (_isScrollMode || _chapterIndex < 0 || _chapterIndex >= widget.detail.chapters.length) return;

    double raw = 0.0;
    if (_pageController.hasClients) raw = (_pageController.page ?? 1.0) - 1.0;
    if (_textPages.isNotEmpty) {
      raw = raw.clamp(0.0, (_textPages.length - 1).toDouble());
    } else {
      raw = 0.0;
    }

    await NovelModule.repository.saveProgress(
      ReadingProgress(
        bookId: widget.detail.book.id,
        chapterIndex: _chapterIndex,
        chapterTitle: widget.detail.chapters[_chapterIndex].title,
        scrollOffset: _encodeProgressOffset(raw),
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

  String _cleanText(String raw) {
    final lines = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim().split('\n');
    final cleaned = <String>[];
    for (final line in lines) {
      var t = line.trim().replaceAll(RegExp(r'^[\s\u3000]+'), '');
      if (t.isNotEmpty) cleaned.add('\u3000\u3000$t');
    }
    if (cleaned.isEmpty && raw.isNotEmpty) cleaned.add('\u3000\u3000$raw');
    return cleaned.join('\n');
  }

  Future<void> _loadChapter({required bool forceRefresh, required _JumpTarget target}) async {
    setState(() {
      _loading = true;
      _isError = false;
      _showMenu = false;
      _jumpTarget = target;
      _scrollItems.clear();
    });

    try {
      final data = await NovelModule.repository.fetchChapter(
        detail: widget.detail,
        chapterIndex: _chapterIndex,
        forceRefresh: forceRefresh,
      );

      if (!mounted) return;

      final text = _cleanText(data.content);
      final cTitle = data.title.trim().isEmpty ? widget.detail.chapters[_chapterIndex].title : data.title;

      setState(() {
        _title = cTitle;
        _content = text;
        if (_isScrollMode) {
          _scrollItems.add(_ScrollChapterItem(index: _chapterIndex, title: cTitle, content: text));
        }
      });

      if (_isScrollMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _handleScrollJump());
      } else {
        if (_lastFitWidth > 0 && _lastNormalHeight > 0) {
          setState(() => _textPages = <String>[]);
        }
      }

      final nextIndex = _chapterIndex + 1;
      if (nextIndex < widget.detail.chapters.length) {
        NovelModule.repository.prefetchChapter(detail: widget.detail, chapterIndex: nextIndex);
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

  Future<void> _fetchNextScrollChapter() async {
    if (_loadingNextScroll || _scrollItems.isEmpty) return;
    final nextIdx = _scrollItems.last.index + 1;
    if (nextIdx >= widget.detail.chapters.length) return;

    setState(() => _loadingNextScroll = true);
    try {
      final data = await NovelModule.repository.fetchChapter(detail: widget.detail, chapterIndex: nextIdx, forceRefresh: false);
      if (!mounted) return;
      final text = _cleanText(data.content);
      final cTitle = data.title.trim().isEmpty ? widget.detail.chapters[nextIdx].title : data.title;
      setState(() => _scrollItems.add(_ScrollChapterItem(index: nextIdx, title: cTitle, content: text)));
    } catch (e) {
      // 失败留到下次滑再尝试
    } finally {
      if (mounted) setState(() => _loadingNextScroll = false);
    }
  }

  Future<void> _switchChapter(int index, {required _JumpTarget target}) async {
    if (index < 0 || index >= widget.detail.chapters.length) return;
    setState(() {
      _chapterIndex = index;
      _content = '';
      _textPages = <String>[];
      _scrollItems.clear();
    });
    await _loadChapter(forceRefresh: false, target: target);
  }

  void _safeJumpScroll(double offset) {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(offset.clamp(0.0, double.infinity));
  }

  Future<void> _handleScrollJump() async {
    if (!_scrollController.hasClients) return;

    if (_jumpTarget == _JumpTarget.start || _jumpTarget == _JumpTarget.end) {
      _safeJumpScroll(0.0);
    } else if (_jumpTarget == _JumpTarget.restoreDb) {
      final saved = await _getSavedProgress();
      _safeJumpScroll(saved == null ? 0.0 : _decodeScrollOffset(saved));
    }
  }

  Future<void> _restorePagePositionAfterPaginate() async {
    if (_isScrollMode || !_pageController.hasClients || _textPages.isEmpty) return;

    int targetPage = 0;
    if (_jumpTarget == _JumpTarget.end) {
      targetPage = _textPages.length - 1;
    } else if (_jumpTarget == _JumpTarget.restoreDb) {
      final saved = await _getSavedProgress();
      if (saved != null) {
        final rawPage = _decodePageOffset(saved);
        targetPage = rawPage.clamp(0.0, (_textPages.length - 1).toDouble()).toInt();
      }
    }

    int targetView = targetPage + 1;
    if (targetView < 1) targetView = 1;
    if (targetView > _textPages.length) targetView = _textPages.length;

    _pageController.jumpToPage(targetView);
    _saveProgress();
  }

  void _calculatePages(double fitWidth, double firstPageHeight, double normalPageHeight) async {
    if (_content.isEmpty || _isScrollMode || _isPaginating) return;

    final cacheKey = '${widget.detail.book.id}_$_chapterIndex'
        '_${_settings.fontSize.toStringAsFixed(1)}_${_settings.lineHeight.toStringAsFixed(2)}'
        '_${fitWidth.toStringAsFixed(1)}_${firstPageHeight.toStringAsFixed(1)}'
        '_${normalPageHeight.toStringAsFixed(1)}_${_content.hashCode}';

    final cached = _pageCache[cacheKey];
    if (cached != null && cached.isNotEmpty) {
      if (!mounted) return;
      setState(() => _textPages = List<String>.from(cached));
      WidgetsBinding.instance.addPostFrameCallback((_) => _restorePagePositionAfterPaginate());
      return;
    }

    _isPaginating = true;
    try {
      final style = TextStyle(fontSize: _settings.fontSize, height: _settings.lineHeight, letterSpacing: 0.6, color: _textColor);
      final painter = TextPainter(textDirection: TextDirection.ltr);
      final pages = <String>[];
      final text = _content;

      int start = 0;
      final safeFirstH = firstPageHeight < 80 ? 80.0 : firstPageHeight;
      final safeNormalH = normalPageHeight < 80 ? 80.0 : normalPageHeight;

      while (start < text.length) {
        while (start < text.length && text[start] == '\n') start++;
        if (start >= text.length) break;

        int low = start, high = text.length, best = start;
        final maxH = pages.isEmpty ? safeFirstH : safeNormalH;

        while (low <= high) {
          final mid = low + ((high - low) ~/ 2);
          painter.text = TextSpan(text: text.substring(start, mid), style: style);
          painter.layout(maxWidth: fitWidth);
          if (painter.height <= maxH) {
            best = mid; low = mid + 1;
          } else {
            high = mid - 1;
          }
        }
        if (best <= start) { best = start + 1; if (best > text.length) best = text.length; }
        pages.add(text.substring(start, best));
        start = best;
      }
      if (pages.isEmpty) pages.add(text);

      if (!mounted) return;
      setState(() => _textPages = pages);
      if (_pageCache.length >= 16 && !_pageCache.containsKey(cacheKey)) _pageCache.remove(_pageCache.keys.first);
      _pageCache[cacheKey] = List<String>.from(pages);
      WidgetsBinding.instance.addPostFrameCallback((_) => _restorePagePositionAfterPaginate());
    } finally {
      _isPaginating = false;
    }
  }

  bool _onScrollNotification(ScrollNotification n) {
    if (!_isScrollMode || _loading || _isError) return false;
    if (n.metrics.axis != Axis.vertical) return false;
    if (n.metrics.extentAfter < 2000 && !_loadingNextScroll) {
      _fetchNextScrollChapter();
    }
    return false;
  }

  int _currentPageIndex() {
    if (_textPages.isEmpty || !_pageController.hasClients) return 0;
    int idx = (_pageController.page ?? 1.0).round() - 1;
    return idx.clamp(0, _textPages.length - 1);
  }

  void _onScreenTap(TapUpDetails details) {
    if (_showMenu) {
      setState(() => _showMenu = false);
      return;
    }

    final size = MediaQuery.of(context).size;
    final x = details.globalPosition.dx, y = details.globalPosition.dy;
    
    if (x > size.width * 0.33 && x < size.width * 0.66 && y > size.height * 0.33 && y < size.height * 0.66) {
      setState(() => _showMenu = true);
      return;
    }

    if (_isScrollMode) {
      if (!_scrollController.hasClients) return;
      final step = size.height * 0.82;
      final current = _scrollController.offset;
      if (y < size.height * 0.33) {
        _scrollController.animateTo((current - step).clamp(0.0, _scrollController.position.maxScrollExtent), duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
      } else if (y > size.height * 0.66) {
        _scrollController.animateTo((current + step).clamp(0.0, _scrollController.position.maxScrollExtent), duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
      }
      return;
    }

    if (!_pageController.hasClients || _textPages.isEmpty) return;
    if (x < size.width * 0.33) {
      if (_currentPageIndex() <= 0) { _switchChapter(_chapterIndex - 1, target: _JumpTarget.end); } 
      else { _pageController.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeInOut); }
    } else {
      if (_currentPageIndex() >= _textPages.length - 1) { _switchChapter(_chapterIndex + 1, target: _JumpTarget.start); } 
      else { _pageController.nextPage(duration: const Duration(milliseconds: 200), curve: Curves.easeInOut); }
    }
  }

  Widget _buildDirectoryFastDragHandle({required ScrollController controller}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final areaHeight = constraints.maxHeight <= 0 ? 1.0 : constraints.maxHeight;
        void jumpByLocalDy(double dy) {
          if (!controller.hasClients) return;
          final ratio = (dy / areaHeight).clamp(0.0, 1.0);
          controller.jumpTo(controller.position.maxScrollExtent * ratio);
        }
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (d) => jumpByLocalDy(d.localPosition.dy),
          onVerticalDragStart: (d) => jumpByLocalDy(d.localPosition.dy),
          onVerticalDragUpdate: (d) => jumpByLocalDy(d.localPosition.dy),
          child: Stack(
            children: [
              Align(alignment: Alignment.center, child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: _textColor.withOpacity(0.14), borderRadius: BorderRadius.circular(1)))),
              AnimatedBuilder(
                animation: controller,
                builder: (_, __) {
                  double ratio = 0.0;
                  if (controller.hasClients && controller.position.maxScrollExtent > 0) {
                    ratio = (controller.offset / controller.position.maxScrollExtent).clamp(0.0, 1.0);
                  }
                  return Positioned(top: ratio * (areaHeight - 28.0), left: 0, right: 0, child: Center(child: Container(width: 20, height: 28, decoration: BoxDecoration(color: Colors.orange.withOpacity(0.22), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange.withOpacity(0.45), width: 1)), child: Icon(Icons.drag_indicator_rounded, size: 14, color: Colors.orange.shade700))));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openDirectory() async {
    setState(() => _showMenu = false);
    final total = widget.detail.chapters.length;
    bool reversed = false;
    bool inited = false;
    final directoryController = ScrollController();
    const double itemHeight = 54.0;

    void jumpNearCurrent() {
      if (!directoryController.hasClients || total == 0) return;
      final visualIndex = reversed ? (total - 1 - _chapterIndex) : _chapterIndex;
      final targetOffset = (visualIndex - 4).clamp(0, total - 1) * itemHeight;
      directoryController.jumpTo(targetOffset);
    }

    int? selected = await showModalBottomSheet<int>(
      context: context, isScrollControlled: true, backgroundColor: _bgColor,
      builder: (context) {
        return StatefulBuilder(
          builder: (_, setSheetState) {
            if (!inited) {
              inited = true;
              WidgetsBinding.instance.addPostFrameCallback((_) => jumpNearCurrent());
            }
            String btnText = reversed ? '正序' : '倒序';
            IconData btnIcon = reversed ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.78,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                      child: Row(
                        children: [
                          Text('目录', style: TextStyle(color: _textColor, fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 10),
                          Text('${_chapterIndex + 1}/$total', style: TextStyle(color: _textColor.withOpacity(0.55), fontSize: 12)),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () {
                              setSheetState(() => reversed = !reversed);
                              WidgetsBinding.instance.addPostFrameCallback((_) => jumpNearCurrent());
                            },
                            icon: Icon(btnIcon, size: 16, color: _textColor),
                            label: Text(btnText, style: TextStyle(color: _textColor, fontSize: 14)),
                          )
                        ],
                      ),
                    ),
                    Divider(height: 1, color: _textColor.withOpacity(0.1)),
                    Expanded(
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 30),
                            child: ListView.builder(
                              controller: directoryController, itemCount: total,
                              itemExtent: itemHeight, 
                              itemBuilder: (_, i) {
                                final visualIndex = reversed ? total - 1 - i : i;
                                final chapter = widget.detail.chapters[visualIndex];
                                final current = visualIndex == _chapterIndex;
                                return Container(
                                  height: itemHeight, decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _textColor.withOpacity(0.05), width: 1))),
                                  child: ListTile(
                                    dense: true, selected: current, selectedTileColor: current ? Colors.orange.withOpacity(0.12) : Colors.transparent,
                                    title: Text(chapter.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: current ? Colors.orange : _textColor)),
                                    trailing: current ? const Icon(Icons.my_location_rounded, size: 16, color: Colors.orange) : null,
                                    onTap: () => Navigator.pop(context, visualIndex),
                                  ),
                                );
                              },
                            ),
                          ),
                          Positioned(top: 8, bottom: 8, right: 4, width: 24, child: _buildDirectoryFastDragHandle(controller: directoryController)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    directoryController.dispose();
    if (selected != null) await _switchChapter(selected, target: _JumpTarget.start);
  }

  void _changeMode(bool isScroll, StateSetter setSheetState) {
    if (_isScrollMode == isScroll) return;
    setState(() {
      _isScrollMode = isScroll;
      _jumpTarget = _JumpTarget.start;
      if (isScroll) {
        _scrollItems = [_ScrollChapterItem(index: _chapterIndex, title: _title, content: _content)];
      } else {
        _textPages = <String>[];
        _scrollItems.clear();
      }
    });
    setSheetState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isScrollMode) _handleScrollJump();
    });
  }

  Future<void> _updateSettings(ReaderSettings next) async {
    setState(() {
      _settings = next;
      if (!_isScrollMode) _textPages = <String>[];
    });
    _settingsSaveDebounce?.cancel();
    _settingsSaveDebounce = Timer(const Duration(milliseconds: 220), () => NovelModule.repository.saveReaderSettings(next));
  }

  Future<void> _openSettings() async {
    setState(() => _showMenu = false);
    await showModalBottomSheet<void>(
      context: context, 
      backgroundColor: _bgColor,
      isScrollControlled: true, 
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: SingleChildScrollView( 
                padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('阅读设置', style: TextStyle(color: _textColor, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Text('翻页方式', style: TextStyle(color: _textColor.withOpacity(0.75))),
                        const SizedBox(width: 16),
                        ChoiceChip(label: const Text('左右翻页'), selected: !_isScrollMode, showCheckmark: false, selectedColor: Colors.orange.withOpacity(0.18), onSelected: (_) => _changeMode(false, setSheetState)),
                        const SizedBox(width: 8),
                        ChoiceChip(label: const Text('上下滑动'), selected: _isScrollMode, showCheckmark: false, selectedColor: Colors.orange.withOpacity(0.18), onSelected: (_) => _changeMode(true, setSheetState)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text('字体大小', style: TextStyle(color: _textColor.withOpacity(0.75))),
                    Slider(value: _settings.fontSize, min: 14, max: 30, divisions: 16, activeColor: Colors.orange, inactiveColor: _textColor.withOpacity(0.2), onChanged: (v) { setSheetState((){}); _updateSettings(_settings.copyWith(fontSize: v)); }),
                    const SizedBox(height: 12),
                    Text('行距', style: TextStyle(color: _textColor.withOpacity(0.75))),
                    Slider(value: _settings.lineHeight, min: 1.4, max: 2.4, divisions: 10, activeColor: Colors.orange, inactiveColor: _textColor.withOpacity(0.2), onChanged: (v) { setSheetState((){}); _updateSettings(_settings.copyWith(lineHeight: v)); }),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFCBE5D2), foregroundColor: Colors.black87), onPressed: () => _updateSettings(_settings.copyWith(themeMode: ReaderThemeMode.warm)), child: const Text('护眼')),
                        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF1E9CE), foregroundColor: Colors.black87), onPressed: () => _updateSettings(_settings.copyWith(themeMode: ReaderThemeMode.paper)), child: const Text('纸张')),
                        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF141414), foregroundColor: Colors.white70), onPressed: () => _updateSettings(_settings.copyWith(themeMode: ReaderThemeMode.dark)), child: const Text('夜间')),
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

  Color get _bgColor {
    switch (_settings.themeMode) {
      case ReaderThemeMode.warm: return const Color(0xFFCBE5D2);
      case ReaderThemeMode.paper: return const Color(0xFFF1E9CE);
      case ReaderThemeMode.dark: return const Color(0xFF141414);
    }
  }

  Color get _textColor {
    switch (_settings.themeMode) {
      case ReaderThemeMode.dark: return const Color(0xFF9A9A9A);
      case ReaderThemeMode.warm: return const Color(0xFF161F1A);
      case ReaderThemeMode.paper: return const Color(0xFF2C2C2C);
    }
  }

  Widget _action(IconData icon, String text, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(opacity: onTap == null ? 0.35 : 1.0, child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 28, color: _textColor), const SizedBox(height: 2), Text(text, style: TextStyle(fontSize: 12, color: _textColor))])),
    );
  }

  Widget _buildContinuousScrollView(double topPad) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: ListView.builder(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20, 0, 20, 100), 
        itemCount: _scrollItems.length + 1, 
        itemBuilder: (context, index) {
          if (index == _scrollItems.length) {
            final isLastInWholeBook = _scrollItems.isNotEmpty && _scrollItems.last.index >= widget.detail.chapters.length - 1;
            if (isLastInWholeBook) {
              return Padding(padding: const EdgeInsets.only(top: 60, bottom: 40), child: Center(child: Text('—— 全书完 ——', style: TextStyle(color: _textColor.withOpacity(0.4), letterSpacing: 2))));
            }
            return Padding(padding: const EdgeInsets.only(top: 50, bottom: 50), child: Center(child: CircularProgressIndicator(color: _textColor.withOpacity(0.35), strokeWidth: 2.5)));
          }

          final item = _scrollItems[index];

          return Container(
            key: item.key,
            padding: EdgeInsets.only(top: index == 0 ? topPad + 16 : 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: _textColor, height: 1.2)),
                const SizedBox(height: 30),
                Text(item.content, style: TextStyle(fontSize: _settings.fontSize, height: _settings.lineHeight, letterSpacing: 0.6, color: _textColor)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBoundaryPage({required bool isNext, required double topPad}) {
    final canMove = isNext ? _chapterIndex < widget.detail.chapters.length - 1 : _chapterIndex > 0;
    String tip = !canMove ? (isNext ? '已经是最后一章' : '已经是第一章') : (isNext ? '继续左滑进入下一章' : '继续右滑进入上一章');
    String nextTitle = '';
    if (canMove) nextTitle = widget.detail.chapters[isNext ? _chapterIndex + 1 : _chapterIndex - 1].title;

    return Container(
      padding: EdgeInsets.fromLTRB(20, topPad + 24, 20, 24), alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isNext ? Icons.swipe_left_rounded : Icons.swipe_right_rounded, size: 34, color: _textColor.withOpacity(0.45)),
          const SizedBox(height: 10),
          Text(tip, style: TextStyle(fontSize: 14, color: _textColor.withOpacity(0.72), fontWeight: FontWeight.w600)),
          if (nextTitle.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(nextTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: _textColor.withOpacity(0.52)))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalChapters = widget.detail.chapters.length;

    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        top: false, bottom: false,
        child: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque, onTapUp: _onScreenTap,
              child: _loading
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: _textColor.withOpacity(0.5)), const SizedBox(height: 14), Text('正在铺排...', style: TextStyle(color: _textColor.withOpacity(0.5)))]))
                  : _isError ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_content, style: const TextStyle(color: Colors.redAccent, fontSize: 16))))
                  : _isScrollMode
                      ? _buildContinuousScrollView(MediaQuery.of(context).padding.top)
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final topPad = MediaQuery.of(context).padding.top;
                            final fitWidth = constraints.maxWidth - 40.0;
                            final paddingTotal = topPad + 8.0 + 8.0;
                            
                            final firstTextHeight = constraints.maxHeight - paddingTotal - 46.0 - 24.0 - 14.0;
                            final normalTextHeight = constraints.maxHeight - paddingTotal - 24.0 - 24.0 - 14.0;

                            if (fitWidth != _lastFitWidth || normalTextHeight != _lastNormalHeight || _textPages.isEmpty) {
                              _lastFitWidth = fitWidth; _lastNormalHeight = normalTextHeight;
                              WidgetsBinding.instance.addPostFrameCallback((_) => _calculatePages(fitWidth, firstTextHeight, normalTextHeight));
                            }
                            if (_textPages.isEmpty) return Center(child: CircularProgressIndicator(strokeWidth: 2, color: _textColor.withOpacity(0.4)));

                            final totalPages = _textPages.length;
                            return PageView.builder(
                              controller: _pageController, itemCount: totalPages + 2, onPageChanged: _onPageChanged, physics: const BouncingScrollPhysics(),
                              itemBuilder: (context, viewIndex) {
                                if (viewIndex == 0) return _buildBoundaryPage(isNext: false, topPad: topPad);
                                if (viewIndex == totalPages + 1) return _buildBoundaryPage(isNext: true, topPad: topPad);
                                final index = viewIndex - 1;

                                return Container(
                                  padding: EdgeInsets.fromLTRB(20, topPad + 8, 20, 8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (index == 0) Container(height: 46, alignment: Alignment.bottomLeft, padding: const EdgeInsets.only(bottom: 8), child: Text(_title.isNotEmpty ? _title : widget.detail.chapters[_chapterIndex].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: _textColor, height: 1.1)))
                                      else SizedBox(height: 24, child: Align(alignment: Alignment.topLeft, child: Text(_title.isNotEmpty ? _title : widget.detail.chapters[_chapterIndex].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: _textColor.withOpacity(0.5), fontWeight: FontWeight.w500)))),
                                      Expanded(child: Text(_textPages[index], style: TextStyle(fontSize: _settings.fontSize, height: _settings.lineHeight, letterSpacing: 0.6, color: _textColor))),
                                      SizedBox(height: 24, child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: Text(widget.detail.book.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: _textColor.withOpacity(0.5)))), Text('${index + 1}/$totalPages   ${((index + 1) / totalPages * 100).toStringAsFixed(1)}%', style: TextStyle(fontSize: 11, color: _textColor.withOpacity(0.5)))]))
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
            ),
            
            if (_showMenu)
              Positioned(top: 0, left: 0, right: 0, child: Container(height: 56 + MediaQuery.of(context).padding.top, padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top), decoration: BoxDecoration(color: _bgColor, border: Border(bottom: BorderSide(color: _textColor.withOpacity(0.08), width: 1))), child: Row(children: [IconButton(icon: Icon(Icons.arrow_back_ios_new_rounded, color: _textColor, size: 20), onPressed: () => Navigator.pop(context)), Expanded(child: Text(widget.detail.book.title, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _textColor)))]))),
            if (_showMenu)
              Positioned(left: 0, right: 0, bottom: 0, child: Container(padding: const EdgeInsets.only(top: 16, bottom: 24), decoration: BoxDecoration(color: _bgColor, border: Border(top: BorderSide(color: _textColor.withOpacity(0.08), width: 1))), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_action(Icons.format_list_bulleted, '目录', _openDirectory), _action(Icons.skip_previous_rounded, '上一章', _chapterIndex > 0 ? () { setState(() => _showMenu = false); _switchChapter(_chapterIndex - 1, target: _JumpTarget.start); } : null), _action(Icons.skip_next_rounded, '下一章', _chapterIndex < totalChapters - 1 ? () { setState(() => _showMenu = false); _switchChapter(_chapterIndex + 1, target: _JumpTarget.start); } : null), _action(Icons.settings_outlined, '设置', _openSettings)]))),
          ],
        ),
      ),
    );
  }
}