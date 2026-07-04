import 'package:flutter/material.dart';

import 'reader_controller.dart';
import 'reader_search_types.dart';

/// 全文搜索 BottomSheet
class ReaderSearchSheet extends StatefulWidget {
  const ReaderSearchSheet({
    super.key,
    required this.controller,
    required this.bgColor,
    required this.textColor,
  });

  final ReaderController controller;
  final Color bgColor;
  final Color textColor;

  @override
  State<ReaderSearchSheet> createState() => _ReaderSearchSheetState();
}

class _ReaderSearchSheetState extends State<ReaderSearchSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  bool _isSearching = false;
  List<ChapterSearchResult> _results = [];

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      final results = await widget.controller.searchInBook(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _isSearching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasResults = _results.isNotEmpty;
    final titleCount = _results.where((r) => r.isTitleMatch).length;
    final contentCount = _results.where((r) => !r.isTitleMatch).length;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            // 搜索栏
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                style: TextStyle(
                  color: widget.textColor,
                  fontSize: 16,
                ),
                decoration: InputDecoration(
                  hintText: '搜索书名、章节、内容…',
                  hintStyle: TextStyle(
                    color: widget.textColor.withValues(alpha: 0.35),
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: widget.textColor.withValues(alpha: 0.5),
                  ),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear_rounded,
                            color: widget.textColor.withValues(alpha: 0.45),
                          ),
                          onPressed: () {
                            _controller.clear();
                            _focusNode.requestFocus();
                            setState(() {
                              _results = [];
                              _isSearching = false;
                            });
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: widget.textColor.withValues(alpha: 0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onSubmitted: _search,
                onChanged: (v) {
                  setState(() {}); // 更新清除按钮
                },
                textInputAction: TextInputAction.search,
              ),
            ),

            // 结果统计 / 加载中
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  if (_isSearching)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: widget.textColor.withValues(alpha: 0.5),
                      ),
                    ),
                  if (_isSearching)
                    const SizedBox(width: 8),
                  Text(
                    _isSearching
                        ? '搜索中…'
                        : hasResults
                            ? '找到 ${_results.length} 处匹配'
                            : _controller.text.isNotEmpty
                                ? '无匹配结果'
                                : '',
                    style: TextStyle(
                      fontSize: 12,
                      color: widget.textColor.withValues(alpha: 0.45),
                    ),
                  ),
                  if (hasResults) ...[
                    const SizedBox(width: 8),
                    if (titleCount > 0)
                      Text(
                        '标题 $titleCount',
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.textColor.withValues(alpha: 0.35),
                        ),
                      ),
                    if (titleCount > 0 && contentCount > 0)
                      Text(
                        ' · ',
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.textColor.withValues(alpha: 0.2),
                        ),
                      ),
                    if (contentCount > 0)
                      Text(
                        '内容 $contentCount',
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.textColor.withValues(alpha: 0.35),
                        ),
                      ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 6),
            Divider(
              height: 1,
              color: widget.textColor.withValues(alpha: 0.08),
            ),

            // 结果列表
            Expanded(
              child: hasResults
                  ? ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _results.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: widget.textColor.withValues(alpha: 0.05),
                      ),
                      itemBuilder: (_, i) {
                        final r = _results[i];
                        return _buildResultItem(r);
                      },
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_rounded,
                            size: 48,
                            color: widget.textColor.withValues(alpha: 0.15),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _controller.text.isNotEmpty
                                ? '没有找到匹配的内容'
                                : '输入关键词搜索全书',
                            style: TextStyle(
                              fontSize: 14,
                              color: widget.textColor.withValues(alpha: 0.35),
                            ),
                          ),
                          if (_controller.text.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '支持搜索章节标题和当前章节内容',
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      widget.textColor.withValues(alpha: 0.25),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultItem(ChapterSearchResult r) {
    final isCurrent = r.isCurrent;
    final isTitle = r.isTitleMatch;

    return InkWell(
      onTap: () => Navigator.pop(context, r.chapterIndex),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isTitle
                    ? Colors.orange.withValues(alpha: 0.12)
                    : widget.textColor.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isTitle ? '标题' : '内容',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isTitle
                      ? Colors.orange
                      : widget.textColor.withValues(alpha: 0.45),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (r.matchCount > 1)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: widget.textColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            '${r.matchCount}处',
                            style: TextStyle(
                              fontSize: 10,
                              color: widget.textColor.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          r.chapterTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                isCurrent ? FontWeight.w700 : FontWeight.w500,
                            color: isCurrent
                                ? Colors.orange
                                : widget.textColor,
                          ),
                        ),
                      ),
                      if (isCurrent)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            '当前',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (r.snippet != null && r.snippet!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _buildHighlightedSnippet(
                        r.snippet!,
                        _controller.text,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建高亮关键词的富文本片段
  Widget _buildHighlightedSnippet(String snippet, String keyword) {
    if (keyword.isEmpty) {
      return Text(
        snippet,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: widget.textColor.withValues(alpha: 0.5),
        ),
      );
    }

    final spans = <TextSpan>[];
    final qLower = keyword.toLowerCase();
    final sLower = snippet.toLowerCase();
    int lastEnd = 0;

    while (true) {
      final idx = sLower.indexOf(qLower, lastEnd);
      if (idx < 0) break;

      // 普通文本
      if (idx > lastEnd) {
        spans.add(TextSpan(text: snippet.substring(lastEnd, idx)));
      }
      // 高亮匹配
      spans.add(TextSpan(
        text: snippet.substring(idx, idx + keyword.length),
        style: TextStyle(
          color: Colors.orange,
          fontWeight: FontWeight.w600,
        ),
      ));
      lastEnd = idx + keyword.length;
    }

    // 剩余文本
    if (lastEnd < snippet.length) {
      spans.add(TextSpan(text: snippet.substring(lastEnd)));
    }

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: widget.textColor.withValues(alpha: 0.5),
        ),
        children: spans,
      ),
    );
  }
}
