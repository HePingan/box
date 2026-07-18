import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'quiz_bank.dart';

class QuizBankViewPage extends StatefulWidget {
  const QuizBankViewPage({super.key});

  @override
  State<QuizBankViewPage> createState() => _QuizBankViewPageState();
}

class _QuizBankViewPageState extends State<QuizBankViewPage> {
  List<QuizBankItem> _items = const [];
  List<QuizBankItem> _filtered = const [];
  final TextEditingController _searchController = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await QuizBankCache.instance.reload();
    final items = QuizBankCache.instance.items;
    if (!mounted) return;
    setState(() {
      _items = items;
      _applyFilter();
    });
  }

  void _applyFilter() {
    final q = _searchController.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _items
        : _items.where((e) {
            return e.question.toLowerCase().contains(q) ||
                e.options.any((o) => o.toLowerCase().contains(q)) ||
                e.correctAnswer.toLowerCase().contains(q);
          }).toList();
    setState(() => _filtered = filtered);
  }

  String _optionsText(QuizBankItem item) {
    final prefix = item.type == QuizQuestionType.trueFalse
        ? ['正确', '错误']
        : ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];
    final buffer = StringBuffer();
    for (var i = 0; i < item.options.length; i++) {
      final p = i < prefix.length ? prefix[i] : '${i + 1}';
      final mark = item.options[i] == item.correctAnswer ? '  ✓' : '';
      buffer.writeln('$p. ${item.options[i]}$mark');
    }
    return buffer.toString().trimRight();
  }

  String _itemToCopy(QuizBankItem item) {
    final buffer = StringBuffer();
    buffer.writeln('【题目】${item.question}');
    if (item.options.isNotEmpty) {
      buffer.writeln('【选项】');
      buffer.writeln(_optionsText(item));
    }
    buffer.writeln('【答案】${item.correctAnswer}');
    if (item.analysis != null && item.analysis!.isNotEmpty) {
      buffer.writeln('【解析】${item.analysis}');
    }
    return buffer.toString().trimRight();
  }

  Future<void> _copyAll() async {
    if (_filtered.isEmpty) return;
    final buffer = StringBuffer();
    for (final item in _filtered) {
      buffer.writeln(_itemToCopy(item));
      buffer.writeln('--------------------------------');
      buffer.writeln('');
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString().trimRight()));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已复制 ${_filtered.length} 条到剪贴板')));
  }

  Future<void> _deduplicate() async {
    if (_busy || _items.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('整理重复题？'),
        content: const Text('将按“题干 + 选项集合”识别重复题。重复时优先保留答案、解析更完整的记录；此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('开始整理'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final scanned = _items.length;
      final result = await QuizBankStorage.deduplicateAll();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.removed == 0
                ? '未发现重复题，题库共 $scanned 条'
                : '去重完成：扫描 $scanned 条，发现 ${result.duplicateGroups} 组重复，删除 ${result.removed} 条，保留 ${result.items.length} 条',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('去重失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(QuizBankItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除该题？'),
        content: Text(
          item.question,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await QuizBankStorage.deleteById(item.id);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已删除')));
  }

  Future<void> _edit(QuizBankItem item) async {
    final result = await showModalBottomSheet<QuizBankItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _QuizBankEditSheet(item: item),
    );
    if (result == null) return;
    // 编辑后按 题干+选项 重算 id；若 id 变化则删旧插新
    final newId = UniqueQuizKeyGenerator.key(
      result.question,
      options: result.options,
    );
    final updated = result.copyWith(
      id: newId,
      createdAt: item.createdAt ?? result.createdAt,
    );
    await QuizBankStorage.replaceItem(item.id, updated);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已保存修改')));
  }

  Future<void> _exportJson() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final json = await QuizBankStorage.exportJsonString();
      final dir = await getTemporaryDirectory();
      final name =
          'quiz_bank_${DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first}.json';
      final file = File('${dir.path}/$name');
      await file.writeAsString(json, encoding: utf8);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: '题库导出 $name',
          text: '共 ${_items.length} 题',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importJson() async {
    if (_busy) return;
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入题库 JSON'),
        content: const Text(
          '系统会按「题干 + 选项集合」自动识别重复（选项顺序不同仍算同题）。\n'
          '同题重复时保留文件中最后一条，避免重复录入；同题干但选项不同会保留为不同题。\n\n'
          '合并：已有同题不写入，仅追加新题\n'
          '替换：先去重，再原子替换整库',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'merge'),
            child: const Text('合并导入'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'replace'),
            child: const Text('替换导入', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (mode == null) return;

    final pick = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json', 'txt'],
    );
    if (pick == null || pick.files.isEmpty) return;
    final f = pick.files.first;
    String raw;
    if (f.path != null) {
      raw = await File(f.path!).readAsString();
    } else {
      final bytes = await f.readAsBytes();
      raw = utf8.decode(bytes);
    }

    setState(() => _busy = true);
    try {
      final result = await QuizBankStorage.importFromJsonString(
        raw,
        merge: mode == 'merge',
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已${mode == 'merge' ? '合并' : '替换'}导入 ${result.imported} 条'
            '（新增 ${result.added}，已存在不写入 ${result.skipped}），'
            '题库共 ${result.total} 条',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('题库（${_filtered.length}/${_items.length}）'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _exportJson,
            icon: const Icon(Icons.upload_file_rounded),
            tooltip: '导出 JSON',
          ),
          IconButton(
            onPressed: _busy ? null : _importJson,
            icon: const Icon(Icons.download_rounded),
            tooltip: '导入 JSON',
          ),
          IconButton(
            onPressed: _busy || _items.isEmpty ? null : _deduplicate,
            icon: const Icon(Icons.cleaning_services_rounded),
            tooltip: '去重整理',
          ),
          IconButton(
            onPressed: _copyAll,
            icon: const Icon(Icons.copy_all_rounded),
            tooltip: '复制全部（当前筛选）',
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: '搜索题目 / 选项 / 答案',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: _filtered.isEmpty
                ? const Center(child: Text('暂无题目，去录入页添加'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final item = _filtered[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.question,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          item.type ==
                                              QuizQuestionType.trueFalse
                                          ? Colors.orange.shade50
                                          : Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      item.type == QuizQuestionType.trueFalse
                                          ? '判断'
                                          : '单选',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            item.type ==
                                                QuizQuestionType.trueFalse
                                            ? Colors.orange.shade700
                                            : Colors.blue.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (item.options.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                ...item.options.map((o) {
                                  final isCorrect = o == item.correctAnswer;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isCorrect
                                              ? Icons.check_circle_rounded
                                              : Icons.circle_outlined,
                                          size: 16,
                                          color: isCorrect
                                              ? Colors.green
                                              : Colors.grey,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            o,
                                            style: TextStyle(
                                              color: isCorrect
                                                  ? Colors.green.shade700
                                                  : null,
                                              fontWeight: isCorrect
                                                  ? FontWeight.w600
                                                  : null,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                              if (item.analysis != null &&
                                  item.analysis!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  '解析：${item.analysis}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _edit(item),
                                    icon: const Icon(
                                      Icons.edit_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('编辑'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => Clipboard.setData(
                                      ClipboardData(text: _itemToCopy(item)),
                                    ),
                                    icon: const Icon(
                                      Icons.copy_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('复制'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _delete(item),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 16,
                                    ),
                                    label: const Text(
                                      '删除',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _QuizBankEditSheet extends StatefulWidget {
  const _QuizBankEditSheet({required this.item});

  final QuizBankItem item;

  @override
  State<_QuizBankEditSheet> createState() => _QuizBankEditSheetState();
}

class _QuizBankEditSheetState extends State<_QuizBankEditSheet> {
  late final TextEditingController _q;
  late final TextEditingController _analysis;
  late final List<TextEditingController> _opts;
  late QuizQuestionType _type;
  late int _correctIndex;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _q = TextEditingController(text: item.question);
    _analysis = TextEditingController(text: item.analysis ?? '');
    _type = item.type;
    final opts = List<String>.from(item.options);
    while (opts.length < 2) {
      opts.add('');
    }
    _opts = opts.map((e) => TextEditingController(text: e)).toList();
    final idx = item.options.indexOf(item.correctAnswer);
    _correctIndex = idx >= 0 ? idx : 0;
  }

  @override
  void dispose() {
    _q.dispose();
    _analysis.dispose();
    for (final c in _opts) {
      c.dispose();
    }
    super.dispose();
  }

  void _setOptionCount(int n) {
    n = n.clamp(2, 8);
    while (_opts.length < n) {
      _opts.add(TextEditingController());
    }
    while (_opts.length > n) {
      _opts.removeLast().dispose();
    }
    if (_correctIndex >= n) _correctIndex = 0;
    setState(() {});
  }

  void _submit() {
    final question = _q.text.trim();
    if (question.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('题目不能为空')));
      return;
    }
    final options = _opts
        .map((e) => e.text.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (options.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少填写一个选项')));
      return;
    }
    final correct = options[_correctIndex.clamp(0, options.length - 1)];
    final analysis = _analysis.text.trim();
    Navigator.pop(
      context,
      QuizBankItem(
        id: widget.item.id,
        question: question,
        type: _type,
        options: options,
        correctAnswer: correct,
        analysis: analysis.isEmpty ? null : analysis,
        source: widget.item.source,
        createdAt: widget.item.createdAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '编辑题目',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            SegmentedButton<QuizQuestionType>(
              segments: const [
                ButtonSegment(
                  value: QuizQuestionType.singleChoice,
                  label: Text('单选'),
                ),
                ButtonSegment(
                  value: QuizQuestionType.trueFalse,
                  label: Text('判断'),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (s) {
                setState(() {
                  _type = s.first;
                  if (_type == QuizQuestionType.trueFalse) {
                    _setOptionCount(2);
                    if (_opts[0].text.isEmpty) _opts[0].text = '正确';
                    if (_opts[1].text.isEmpty) _opts[1].text = '错误';
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _q,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '题目',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('选项'),
                const Spacer(),
                IconButton(
                  onPressed: () => _setOptionCount(_opts.length - 1),
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: '减少选项',
                ),
                Text('${_opts.length}'),
                IconButton(
                  onPressed: () => _setOptionCount(_opts.length + 1),
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: '增加选项',
                ),
              ],
            ),
            for (var i = 0; i < _opts.length; i++) ...[
              Row(
                children: [
                  Radio<int>(
                    value: i,
                    groupValue: _correctIndex,
                    onChanged: (v) => setState(() => _correctIndex = v ?? 0),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _opts[i],
                      decoration: InputDecoration(
                        labelText:
                            '${String.fromCharCode(0x41 + (i % 26))}. 选项（点左选正确答案）',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _analysis,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '解析（可选）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _submit, child: const Text('保存修改')),
          ],
        ),
      ),
    );
  }
}
