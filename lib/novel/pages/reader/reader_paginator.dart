import 'dart:collection';

import 'package:flutter/painting.dart';

/// 一次分页所需的输入参数
class ReaderPaginationRequest {
  const ReaderPaginationRequest({
    required this.bookId,
    required this.chapterIndex,
    required this.content,
    required this.fitWidth,
    required this.firstPageHeight,
    required this.normalPageHeight,
    required this.fontSize,
    required this.lineHeight,
    this.letterSpacing = 0.6,
    this.textDirection = TextDirection.ltr,
    this.cacheSize = 16,
  });

  final String bookId;
  final int chapterIndex;
  final String content;

  /// 每页可用宽度
  final double fitWidth;

  /// 第一页可用高度
  final double firstPageHeight;

  /// 后续页可用高度
  final double normalPageHeight;

  final double fontSize;
  final double lineHeight;
  final double letterSpacing;
  final TextDirection textDirection;

  /// 内存缓存条数上限
  final int cacheSize;
}

/// 阅读器分页工具
///
/// 职责：
/// - 将正文内容按当前字体/行距/宽高切成分页
/// - 内置一个简单的内存 LRU 缓存，避免重复计算
class ReaderPaginator {
  ReaderPaginator._();

  static final LinkedHashMap<String, List<String>> _cache =
      LinkedHashMap<String, List<String>>();

  /// 清空内存缓存，测试或切换大主题时可调用
  static void clearCache() {
    _cache.clear();
  }

  /// 执行分页
  static List<String> paginate(ReaderPaginationRequest request) {
    final key = _buildCacheKey(request);

    final cached = _cache.remove(key);
    if (cached != null) {
      // 重新插入，模拟 LRU 的“最近使用”
      _cache[key] = cached;
      return List<String>.from(cached);
    }

    final pages = _paginate(request);

    _cache[key] = List<String>.unmodifiable(pages);
    while (_cache.length > request.cacheSize) {
      _cache.remove(_cache.keys.first);
    }

    return List<String>.from(pages);
  }

  static String _buildCacheKey(ReaderPaginationRequest request) {
    final contentSignature =
        '${request.content.length}:${request.content.hashCode}';

    return [
      request.bookId,
      request.chapterIndex,
      request.fitWidth.toStringAsFixed(1),
      request.firstPageHeight.toStringAsFixed(1),
      request.normalPageHeight.toStringAsFixed(1),
      request.fontSize.toStringAsFixed(1),
      request.lineHeight.toStringAsFixed(2),
      request.letterSpacing.toStringAsFixed(2),
      contentSignature,
    ].join('|');
  }

  static List<String> _paginate(ReaderPaginationRequest request) {
    final text = request.content;

    if (text.isEmpty) {
      return <String>[''];
    }

    if (request.fitWidth <= 0 ||
        request.firstPageHeight <= 0 ||
        request.normalPageHeight <= 0) {
      return <String>[text];
    }

    final pages = <String>[];

    final style = TextStyle(
      fontSize: request.fontSize,
      height: request.lineHeight,
      letterSpacing: request.letterSpacing,
    );

    final painter = TextPainter(textDirection: request.textDirection);

    int start = 0;
    final safeFirstH = request.firstPageHeight < 80
        ? 80.0
        : request.firstPageHeight;
    final safeNormalH = request.normalPageHeight < 80
        ? 80.0
        : request.normalPageHeight;

    while (start < text.length) {
      // 跳过开头连续换行，避免空白页
      while (start < text.length && text[start] == '\n') {
        start++;
      }

      if (start >= text.length) break;

      int low = start;
      int high = text.length;
      int best = start;

      final maxH = pages.isEmpty ? safeFirstH : safeNormalH;

      while (low <= high) {
        final mid = low + ((high - low) ~/ 2);

        painter.text = TextSpan(
          text: text.substring(start, mid),
          style: style,
        );
        painter.layout(maxWidth: request.fitWidth);

        if (painter.height <= maxH) {
          best = mid;
          low = mid + 1;
        } else {
          high = mid - 1;
        }
      }

      if (best <= start) {
        best = start + 1;
        if (best > text.length) best = text.length;
      }

      pages.add(text.substring(start, best));
      start = best;
    }

    if (pages.isEmpty) {
      pages.add(text);
    }

    return pages;
  }
}