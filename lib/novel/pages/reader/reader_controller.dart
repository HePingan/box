import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../novel_module.dart';
import 'reader_progress_service.dart';

enum ReaderJumpTarget {
  start,
  end,
  restoreDb,
}

class ReaderScrollChapterItem {
  final int index;
  final String title;
  final String content;
  final GlobalKey key;

  ReaderScrollChapterItem({
    required this.index,
    required this.title,
    required this.content,
    GlobalKey? key,
  }) : key = key ?? GlobalKey();
}

class ReaderController extends ChangeNotifier {
  ReaderController({
    required this.detail,
    required int initialChapterIndex,
    ReaderProgressService? progressService,
  })  : progressService = progressService ?? const ReaderProgressService(),
        chapterIndex = initialChapterIndex.clamp(
          0,
          detail.chapters.isEmpty ? 0 : detail.chapters.length - 1,
        );

  final NovelDetail detail;
  final ReaderProgressService progressService;

  int chapterIndex;

  bool loading = true;
  bool isError = false;
  String errorText = '';

  String title = '';
  String content = '';

  bool showMenu = false;
  bool isScrollMode = false;
  bool loadingNextScroll = false;

  ReaderSettings settings = const ReaderSettings();
  ReadingProgress? progress;

  final List<ReaderScrollChapterItem> scrollItems = <ReaderScrollChapterItem>[];

  Timer? _settingsSaveDebounce;

  bool get hasChapters => detail.chapters.isNotEmpty;

  int get totalChapters => detail.chapters.length;

  bool get canGoPrev => chapterIndex > 0;

  bool get canGoNext => chapterIndex < detail.chapters.length - 1;

  NovelChapter get currentChapter => detail.chapters[chapterIndex];

  String get currentChapterTitle {
    if (detail.chapters.isEmpty) return '';
    return detail.chapters[chapterIndex].title;
  }

  String get bookTitle => detail.book.title;

  void setChapterIndex(int index) {
    if (chapterIndex == index) return;
    chapterIndex = index.clamp(
      0,
      detail.chapters.isEmpty ? 0 : detail.chapters.length - 1,
    );
    notifyListeners();
  }

  void updateProgress(ReadingProgress? next) {
    progress = next;
    notifyListeners();
  }

  Future<void> bootstrap() async {
    loading = true;
    isError = false;
    errorText = '';
    notifyListeners();

    try {
      settings = await NovelModule.repository.getReaderSettings();
      notifyListeners();

      if (!hasChapters) {
        loading = false;
        isError = true;
        errorText = '暂无可阅读章节';
        notifyListeners();
        return;
      }

      await loadCurrentChapter(
        forceRefresh: false,
        target: ReaderJumpTarget.restoreDb,
      );
    } catch (e) {
      loading = false;
      isError = true;
      errorText = '初始化失败：$e';
      notifyListeners();
    }
  }

  Future<void> loadCurrentChapter({
    required bool forceRefresh,
    required ReaderJumpTarget target,
  }) async {
    if (!hasChapters) {
      loading = false;
      isError = true;
      errorText = '暂无可阅读章节';
      notifyListeners();
      return;
    }

    loading = true;
    isError = false;
    errorText = '';
    showMenu = false;
    loadingNextScroll = false;
    notifyListeners();

    try {
      final data = await NovelModule.repository.fetchChapter(
        detail: detail,
        chapterIndex: chapterIndex,
        forceRefresh: forceRefresh,
      );

      title = data.title.trim().isEmpty ? currentChapter.title : data.title;
      content = _cleanText(data.content);

      progress = await progressService.loadCurrentChapterProgress(
        detail.book.id,
        chapterIndex,
      );

      scrollItems
        ..clear()
        ..add(
          ReaderScrollChapterItem(
            index: chapterIndex,
            title: title,
            content: content,
          ),
        );

      final nextIndex = chapterIndex + 1;
      if (nextIndex < detail.chapters.length) {
        unawaited(
          NovelModule.repository
              .prefetchChapter(
                detail: detail,
                chapterIndex: nextIndex,
              )
              .catchError((_) {}),
        );
      }

      loading = false;
      notifyListeners();
    } catch (e) {
      loading = false;
      isError = true;
      errorText = '章节加载失败：$e';
      notifyListeners();
    }
  }

  Future<void> switchChapter(
    int index, {
    required ReaderJumpTarget target,
  }) async {
    if (index < 0 || index >= detail.chapters.length) return;

    chapterIndex = index;
    scrollItems.clear();
    notifyListeners();

    await loadCurrentChapter(
      forceRefresh: false,
      target: target,
    );
  }

  void setMenuVisible(bool value) {
    if (showMenu == value) return;
    showMenu = value;
    notifyListeners();
  }

  void toggleMenu() {
    setMenuVisible(!showMenu);
  }

  void setScrollMode(bool value) {
    if (isScrollMode == value) return;

    isScrollMode = value;
    showMenu = false;

    scrollItems.clear();
    if (value && hasChapters) {
      scrollItems.add(
        ReaderScrollChapterItem(
          index: chapterIndex,
          title: title,
          content: content,
        ),
      );
    }

    notifyListeners();
  }

  Future<void> fetchNextScrollChapter() async {
    if (!isScrollMode || loadingNextScroll || scrollItems.isEmpty) return;

    final nextIdx = scrollItems.last.index + 1;
    if (nextIdx >= detail.chapters.length) return;

    loadingNextScroll = true;
    notifyListeners();

    try {
      final data = await NovelModule.repository.fetchChapter(
        detail: detail,
        chapterIndex: nextIdx,
        forceRefresh: false,
      );

      final nextTitle = data.title.trim().isEmpty
          ? detail.chapters[nextIdx].title
          : data.title;

      scrollItems.add(
        ReaderScrollChapterItem(
          index: nextIdx,
          title: nextTitle,
          content: _cleanText(data.content),
        ),
      );
    } catch (_) {
      // 预加载失败不影响当前阅读
    } finally {
      loadingNextScroll = false;
      notifyListeners();
    }
  }

  Future<void> updateSettings(ReaderSettings next) async {
    settings = next;
    notifyListeners();

    _settingsSaveDebounce?.cancel();
    _settingsSaveDebounce = Timer(
      const Duration(milliseconds: 220),
      () {
        unawaited(
          NovelModule.repository.saveReaderSettings(next).catchError((_) {}),
        );
      },
    );
  }

  String _cleanText(String raw) {
    final lines = raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim()
        .split('\n');

    final cleaned = <String>[];
    for (final line in lines) {
      final t = line.trim().replaceAll(RegExp(r'^[\s\u3000]+'), '');
      if (t.isNotEmpty) cleaned.add('\u3000\u3000$t');
    }

    if (cleaned.isEmpty && raw.isNotEmpty) {
      cleaned.add('\u3000\u3000$raw');
    }

    return cleaned.join('\n');
  }

  @override
  void dispose() {
    _settingsSaveDebounce?.cancel();
    unawaited(NovelModule.repository.saveReaderSettings(settings).catchError((_) {}));
    super.dispose();
  }
}