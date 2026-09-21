import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:box/features/comic/domain/comic_book.dart';
import 'package:box/features/comic/domain/comic_library_store.dart';
import 'package:box/features/comic/presentation/comic_reader_controller.dart';

/// 漫画阅读器页面（翻页 / 长条两种模式）。
///
/// 契约说明（有回归测试锁住）：
/// - 点击页面只切换沉浸态（隐藏/显示底栏），**不退出**阅读器；返回走系统返回键。
/// - 翻页手势完全交给 [PageView]，页面本身不再挂水平拖拽回调，避免一次滑动翻两页。
/// - 有已保存进度时，[PageController.initialPage] 必须真的落在那一页，否则续读形同失效。
class ComicReaderPage extends StatefulWidget {
  const ComicReaderPage({
    super.key,
    required this.comicBook,
    this.libraryStore,
  });

  final ComicBook comicBook;

  /// 可注入的本地库存储（测试用；生产环境省略即走默认实例）。
  final ComicLibraryStore? libraryStore;

  @override
  State<ComicReaderPage> createState() => _ComicReaderPageState();
}

class _ComicReaderPageState extends State<ComicReaderPage> {
  late final ComicReaderController _controller;
  late final ComicLibraryStore _store;

  /// 进度读回来之后才建 PageController，这样 initialPage 能一次落对页。
  PageController? _pageController;
  Timer? _saveDebounce;

  bool _restoring = true;
  bool _chromeVisible = true;

  @override
  void initState() {
    super.initState();
    _store = widget.libraryStore ?? ComicLibraryStore();
    _controller = ComicReaderController(
      comicBook: widget.comicBook,
      libraryStore: _store,
    );
    unawaited(WakelockPlus.enable());
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    await _controller.loadPages();

    final saved = await _controller.loadProgress();
    var startIndex = 0;
    if (saved != null && _controller.totalPages > 0) {
      startIndex = saved.currentPageIndex.clamp(0, _controller.totalPages - 1);
      _controller.setPage(startIndex);
      if (saved.isScrollMode != _controller.isScrollMode) {
        _controller.toggleScrollMode();
      }
    }

    if (!mounted) return;
    setState(() {
      _pageController = PageController(initialPage: startIndex);
      _restoring = false;
    });
  }

  void _saveProgressDebounced() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 1), () {
      unawaited(_controller.saveProgress());
    });
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    unawaited(WakelockPlus.disable());
    _controller.dispose();
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, result) {
          unawaited(_controller.saveProgress());
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: _buildBody(),
          bottomNavigationBar: _chromeVisible ? _buildBottomBar() : null,
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_restoring || _pageController == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Consumer<ComicReaderController>(
      builder: (context, controller, child) {
        if (controller.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.isError) {
          return Center(
            child: Text(
              '加载失败: ${controller.errorText}',
              style: const TextStyle(color: Colors.white70),
            ),
          );
        }
        if (controller.totalPages == 0) {
          return const Center(
            child: Text('这本漫画没有可显示的页面', style: TextStyle(color: Colors.white70)),
          );
        }

        return controller.isScrollMode
            ? _buildScrollMode(controller)
            : _buildPageMode(controller);
      },
    );
  }

  void _toggleChrome() => setState(() => _chromeVisible = !_chromeVisible);

  Widget _buildPageMode(ComicReaderController controller) {
    // 翻页手势只由 PageView 处理一次；外层仅接管单击（切换沉浸态）。
    return GestureDetector(
      onTap: _toggleChrome,
      child: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) {
          controller.setPage(index);
          _saveProgressDebounced();
        },
        itemCount: controller.totalPages,
        itemBuilder: (context, index) => _buildPage(
          controller.comicBook.pages[index],
          index,
          controller.totalPages,
        ),
      ),
    );
  }

  Widget _buildPage(String imagePath, int index, int totalPages) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.file(
            File(imagePath),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => const Center(
              child: Icon(Icons.broken_image, size: 64, color: Colors.white54),
            ),
          ),
        ),
        if (_chromeVisible)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                '${index + 1} / $totalPages',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildScrollMode(ComicReaderController controller) {
    return GestureDetector(
      onTap: _toggleChrome,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: controller.totalPages,
        itemBuilder: (context, index) {
          return Image.file(
            File(controller.comicBook.pages[index]),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => const SizedBox(
              height: 400,
              child: Center(
                child: Icon(Icons.broken_image, size: 48, color: Colors.white54),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomBar() {
    return Consumer<ComicReaderController>(
      builder: (context, controller, child) {
        final atFirst = controller.currentPageIndex <= 0;
        final atLast = controller.currentPageIndex >= controller.totalPages - 1;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${controller.currentPageIndex + 1} / ${controller.totalPages}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: '上一页',
                      icon: const Icon(Icons.chevron_left, color: Colors.white70),
                      onPressed: atFirst ? null : () => _jumpBy(-1),
                    ),
                    IconButton(
                      tooltip: '下一页',
                      icon: const Icon(Icons.chevron_right, color: Colors.white70),
                      onPressed: atLast ? null : () => _jumpBy(1),
                    ),
                    IconButton(
                      tooltip: controller.isScrollMode ? '切换为翻页模式' : '切换为长条模式',
                      icon: Icon(
                        controller.isScrollMode
                            ? Icons.auto_stories_outlined
                            : Icons.view_day_outlined,
                        color: Colors.white70,
                      ),
                      onPressed: () {
                        controller.toggleScrollMode();
                        _saveProgressDebounced();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 底栏翻页：同时驱动 PageView，避免 controller 与视图脱钩。
  void _jumpBy(int delta) {
    final target = (_controller.currentPageIndex + delta)
        .clamp(0, _controller.totalPages - 1);
    final pageController = _pageController;
    if (pageController != null && pageController.hasClients) {
      pageController.animateToPage(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _controller.setPage(target);
    }
    _saveProgressDebounced();
  }
}
