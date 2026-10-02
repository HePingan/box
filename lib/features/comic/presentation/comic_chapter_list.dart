// 章节目录列表 —— 详情页和阅读器「目录」共用同一份。
//
// 为什么抽出来（2026-10-02 用户提"目录要能快速滑动 + 正序/倒序"）：漫画目录动辄
// 几百话，而两处目录各写各的 ListView，就会"一处修好、另一处还是老样子"。
//
// 这块只解决三件事，全是"几百话时才痛"的：
//   1. **快速滑动**：可拖动的滚动条（`interactive`）+ 可拖的拇指，一屏一屏拖；
//   2. **跳话**：直接输第几话 / 一键跳到正在读 / 最新一话，别用手指划 300 行；
//   3. **正序 / 倒序**：追更看最新、补番从头翻，选择记在本机（见 `ComicReaderPrefs`）。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/comic_online_service.dart';
import '../domain/comic_reader_prefs.dart';

/// 目录每行的固定高度。
///
/// **固定**是关键：几百话的书要"跳话 / 拖滚动条"，只有每行等高才能用
/// `行号 × 行高` 一次算准（64px = 带副标题的 dense 两行高度）。
/// 早先按"实际行高"估算 + `ensureVisible` 对齐，反而被框架的 element 复用坑了：
/// 跳完之后屏外的行还留着 element、位置判断全乱，表现就是"点了跳话但没动"。
const double _rowExtent = 64;

class ComicChapterList extends StatefulWidget {
  const ComicChapterList({
    super.key,
    required this.chapters,
    this.currentUrl,
    this.downloaded = const <String>{},
    this.onPick,
    this.trailing,
    this.prefs,
  });

  /// **正序**的章节目录（倒序由本组件自己翻，调用方不用关心）。
  final List<ComicChapterRef> chapters;

  /// 正在读的那一话（打开时会自动滚到它）。
  final String? currentUrl;

  /// 已下载到本机的话（用于"已下载"标记）。
  final Set<String> downloaded;

  /// 点了某一话：给了就允许点（阅读器里=跳过去）；不给只能看。
  final void Function(ComicChapterRef chapter)? onPick;

  /// 每行右侧的控件（详情页放"下载这一话"）。
  final Widget Function(ComicChapterRef chapter)? trailing;

  final ComicReaderPrefs? prefs;

  @override
  State<ComicChapterList> createState() => _ComicChapterListState();
}

class _ComicChapterListState extends State<ComicChapterList> {
  late final ComicReaderPrefs _prefs;
  final ScrollController _controller = ScrollController();

  /// 是否倒序（最新一话在最上面）。
  ///
  /// 初始值先按正序渲染、读到设置再切：目录这种"看一眼就走"的界面不该为了
  /// 一个布尔值卡在加载态。
  bool _desc = false;

  @override
  void initState() {
    super.initState();
    _prefs = widget.prefs ?? ComicReaderPrefs();
    unawaited(_loadPrefs());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    bool desc;
    try {
      desc = await _prefs.chapterDescending();
    } catch (_) {
      desc = false; // 读不出来当正序，别为了一个排序把目录卡住。
    }
    if (!mounted) return;
    if (desc != _desc) setState(() => _desc = desc);
    // 读到设置（或者排序变了）之后，"正在读"那一行的行号会变：跟着滚过去。
    WidgetsBinding.instance.addPostFrameCallback((_) => _locateToCurrent());
  }

  /// 第 [i] 行（**显示顺序**）对应正序里的第几话（0 基）。
  int _ascIndex(int i) => _desc ? widget.chapters.length - 1 - i : i;

  ComicChapterRef _chapterAt(int i) => widget.chapters[_ascIndex(i)];

  /// 显示顺序里，"正在读"那一话在第几行。
  int? get _currentRow {
    final url = widget.currentUrl;
    if (url == null) return null;
    final asc = widget.chapters.indexWhere((c) => c.url == url);
    if (asc < 0) return null;
    return _desc ? widget.chapters.length - 1 - asc : asc;
  }

  /// 行号 → 滚动位置。行高固定，这一步是**算准的**，不用"先跳再对齐"。
  double _offsetOf(int row) {
    if (!_controller.hasClients) return row * _rowExtent;
    return (row * _rowExtent).clamp(0.0, _controller.position.maxScrollExtent);
  }

  /// 滚到"正在读"那一话（没有在读的就留在原地）。
  void _locateToCurrent() {
    if (!mounted || !_controller.hasClients) return;
    final row = _currentRow;
    if (row == null) return;
    _controller.jumpTo(_offsetOf(row));
  }

  /// 跳到第 [row] 行（显示顺序）。
  ///
  /// 行高固定（见 [_rowExtent]），"第几行 → 滚到哪"是一次乘法算准的 ——
  /// 不需要"估算 + 逐帧逼近 + ensureVisible 对齐"那套（那套会被框架的 element
  /// 复用坑成"点了没动"，这一轮实测过一次）。
  Future<void> _jumpToRow(int row, {bool animate = true}) async {
    if (!mounted || !_controller.hasClients) return;
    final row0 = row.clamp(0, widget.chapters.length - 1);
    final offset = _offsetOf(row0);
    if (animate) {
      await _controller.animateTo(
        offset,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    } else {
      _controller.jumpTo(offset);
    }
  }

  Future<void> _toggleOrder() async {
    final next = !_desc;
    setState(() => _desc = next);
    // 换了顺序，"正在读"那一行就换位置了：跟着滚过去，别让用户又自己找一次。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _currentRow;
      if (row != null) unawaited(_jumpToRow(row));
    });
    try {
      await _prefs.setChapterDescending(next);
    } catch (_) {
      // 记不住就算了（下次开还是正序），不影响这一次的浏览。
    }
  }

  /// 跳话对话框：输第几话 / 一键到"正在读"或"最新一话"。
  ///
  /// 输入框的 controller 交给对话框自己持有（`_JumpDialog`）：在这里持有并在
  /// `showDialog` 返回后立刻 dispose，会撞上"退场动画还在跑、TextField 还在用"
  /// —— 本项目已经踩过一次（`A TextEditingController was used after being disposed`）。
  Future<void> _openJumpDialog() async {
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => _JumpDialog(
        total: widget.chapters.length,
        currentRow: _currentRow,
      ),
    );
    if (picked == null || !mounted) return;
    await _jumpToRow(_rowOfChapter(picked - 1));
  }

  /// 正序里第 [asc] 话在显示顺序里的行号。
  int _rowOfChapter(int asc) =>
      _desc ? widget.chapters.length - 1 - asc : asc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = widget.chapters.length;
    final currentRow = _currentRow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 6, 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  // 带"目录"二字：详情页页眉已经有一句「共 N 话」，
                  // 这里再写一遍就是同一个数字两处（而且测试里会撞成两处匹配）。
                  currentRow == null
                      ? '目录 · 共 $total 话'
                      : '目录 · 共 $total 话 · 正在读第 ${currentRow + 1} 话',
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 排序：图标+文字，别只放一个图标 —— "倒序"这两个字点一次就懂了。
              Tooltip(
                message: _desc
                    ? '最新的在最上面（点一下改成从第 1 话开始）'
                    : '从第 1 话开始（点一下改成最新在最上面）',
                child: TextButton.icon(
                  onPressed: _toggleOrder,
                  icon: Icon(
                    _desc
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    size: 18,
                  ),
                  label: Text(_desc ? '倒序' : '正序'),
                ),
              ),
              TextButton.icon(
                onPressed: _openJumpDialog,
                icon: const Icon(Icons.keyboard_double_arrow_down_rounded, size: 18),
                label: const Text('跳话'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Scrollbar(
            controller: _controller,
            // 可拖动的拇指：几百话时这是唯一"一拖到底"的办法。
            thumbVisibility: true,
            interactive: true,
            child: ListView.builder(
              controller: _controller,
              // 固定行高：跳话与拖滚动条都靠它算准（见 [_rowExtent]）。
              itemExtent: _rowExtent,
              itemCount: total,
              itemBuilder: (context, i) {
                final c = _chapterAt(i);
                final asc = _ascIndex(i);
                return ListTile(
                  key: ValueKey<String>('chapter-${c.url}'),
                  dense: true,
                  selected: c.url == widget.currentUrl,
                  leading: Text(
                    '${asc + 1}',
                    style: TextStyle(
                      color: c.url == widget.currentUrl
                          ? theme.colorScheme.primary
                          : null,
                      fontWeight: c.url == widget.currentUrl
                          ? FontWeight.w600
                          : null,
                    ),
                  ),
                  title: Text(
                    c.title.isEmpty ? c.url : c.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: c.url == widget.currentUrl
                      ? const Text('正在读')
                      : widget.downloaded.contains(c.url)
                      ? const Text('已下载')
                      : null,
                  trailing: widget.trailing?.call(c),
                  onTap: widget.onPick == null
                      ? null
                      : () => widget.onPick!(c),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// 「跳话」对话框：自己持有输入框的 controller（见 [_ComicChapterListState._openJumpDialog]）。
///
/// 返回 1 基的"第几话"；取消返回 null。
class _JumpDialog extends StatefulWidget {
  const _JumpDialog({required this.total, required this.currentRow});

  final int total;

  /// 显示顺序里"正在读"那一话的行号（0 基），没有则为 null。
  final int? currentRow;

  @override
  State<_JumpDialog> createState() => _JumpDialogState();
}

class _JumpDialogState extends State<_JumpDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final n = int.tryParse(_controller.text.trim());
    if (n == null || n < 1 || n > widget.total) return;
    Navigator.of(context).pop(n);
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.currentRow;
    return AlertDialog(
      title: Text('跳到第几话（共 ${widget.total} 话）'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          hintText: '比如 180',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        if (row != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(row + 1),
            child: const Text('正在读'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(widget.total),
          child: const Text('最新一话'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(1),
          child: const Text('第 1 话'),
        ),
        FilledButton(onPressed: _submit, child: const Text('跳过去')),
      ],
    );
  }
}
