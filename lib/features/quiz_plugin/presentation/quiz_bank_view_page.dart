import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/quiz_bank.dart';
import '../data/quiz_cloud_pull.dart';
import '../data/quiz_cloud_push.dart';
import '../data/quiz_cloud_sync.dart';

class QuizBankViewPage extends StatefulWidget {
  const QuizBankViewPage({super.key});

  @override
  State<QuizBankViewPage> createState() => _QuizBankViewPageState();
}

class _QuizBankViewPageState extends State<QuizBankViewPage> {
  List<QuizBankItem> _items = const [];
  List<QuizBankItem> _filtered = const [];
  final TextEditingController _searchController = TextEditingController();
  final QuizCloudPullCoordinator _cloudPull = QuizCloudPullCoordinator();
  final QuizCloudPushCoordinator _cloudPush = QuizCloudPushCoordinator();
  final Set<String> _selectedIds = <String>{};
  bool _selectMode = false;
  bool _busy = false;
  String? _cloudStatusText;
  String _originFilter = 'all'; // all | cloud | local | unpushed
  String _categoryFilter = ''; // empty = all

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _cloudPull.dispose();
    _cloudPush.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await QuizBankCache.instance.reload();
    final items = QuizBankCache.instance.items;
    final status = await _cloudPull.loadStatus();
    if (!mounted) return;
    setState(() {
      _items = items;
      _selectedIds.removeWhere((id) => !items.any((e) => e.id == id));
      _cloudStatusText =
          '云端：${status.lastSyncLabel} · ${status.lastSummary.isEmpty ? "点右上角云图标更新" : status.lastSummary}';
      _applyFilter();
    });
  }

  void _applyFilter() {
    final q = _searchController.text.trim().toLowerCase();
    var filtered = _items;
    if (_originFilter == 'cloud') {
      filtered = filtered.where((e) => e.isCloud).toList();
    } else if (_originFilter == 'local') {
      filtered = filtered.where((e) => !e.isCloud).toList();
    } else if (_originFilter == 'unpushed') {
      filtered = filtered.where((e) => e.isUnpushedLocal).toList();
    }
    if (_categoryFilter.isNotEmpty) {
      filtered = filtered
          .where((e) => e.category.trim() == _categoryFilter)
          .toList();
    }
    if (q.isNotEmpty) {
      filtered = filtered.where((e) {
        return e.question.toLowerCase().contains(q) ||
            e.options.any((o) => o.toLowerCase().contains(q)) ||
            e.correctAnswer.toLowerCase().contains(q) ||
            e.category.toLowerCase().contains(q) ||
            e.source.toLowerCase().contains(q) ||
            QuizSyncStatus.label(e.syncStatus).contains(q);
      }).toList();
    }
    setState(() => _filtered = filtered);
  }

  List<String> get _categories {
    final set = <String>{};
    for (final item in _items) {
      final c = item.category.trim();
      if (c.isNotEmpty) set.add(c);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<QuizBankItem> get _pushTargets {
    if (_selectMode && _selectedIds.isNotEmpty) {
      return _items.where((e) => _selectedIds.contains(e.id)).toList();
    }
    if (_originFilter == 'unpushed') {
      return _filtered.where((e) => e.canPushToCloud).toList();
    }
    return _filtered.where((e) => e.isUnpushedLocal).toList();
  }

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      if (!_selectMode) _selectedIds.clear();
    });
  }

  void _toggleSelected(QuizBankItem item) {
    setState(() {
      if (_selectedIds.contains(item.id)) {
        _selectedIds.remove(item.id);
      } else {
        _selectedIds.add(item.id);
      }
    });
  }

  void _selectAllFilteredPushable() {
    setState(() {
      for (final item in _filtered.where((e) => e.canPushToCloud)) {
        _selectedIds.add(item.id);
      }
    });
  }

  String _optionsText(QuizBankItem item) {
    final prefix = item.type == QuizQuestionType.trueFalse
        ? ['正确', '错误']
        : ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];
    final buffer = StringBuffer();
    for (var i = 0; i < item.options.length; i++) {
      final p = i < prefix.length ? prefix[i] : '${i + 1}';
      // 经投影判定对号：字母形答案（如 'B'）也能正确命中选项。
      final mark = QuizAnswerProjection.isCorrectOption(item, i) ? '  ✓' : '';
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
    final resolvedAnswer = QuizAnswerProjection.resolve(item);
    buffer.writeln(
      resolvedAnswer.needsRepair
          ? '【答案】${item.correctAnswer}（待补：对不上选项）'
          : '【答案】${resolvedAnswer.answer}',
    );
    if (item.analysis != null && item.analysis!.isNotEmpty) {
      buffer.writeln('【解析】${item.analysis}');
    }
    return buffer.toString().trimRight();
  }

  Color _syncStatusColor(String status) {
    switch (status) {
      case QuizSyncStatus.pendingReview:
        return Colors.orange.shade700;
      case QuizSyncStatus.published:
        return Colors.indigo.shade700;
      case QuizSyncStatus.rejected:
        return Colors.red.shade700;
      case QuizSyncStatus.merged:
        return Colors.teal.shade700;
      default:
        return Colors.green.shade700;
    }
  }

  Color _syncStatusBg(String status) {
    switch (status) {
      case QuizSyncStatus.pendingReview:
        return Colors.orange.shade50;
      case QuizSyncStatus.published:
        return Colors.indigo.shade50;
      case QuizSyncStatus.rejected:
        return Colors.red.shade50;
      case QuizSyncStatus.merged:
        return Colors.teal.shade50;
      default:
        return Colors.green.shade50;
    }
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

  Future<void> _pushToCloud({QuizBankItem? single}) async {
    if (_busy) return;
    final targets = single != null
        ? <QuizBankItem>[single]
        : _pushTargets.where((e) => e.canPushToCloud).toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可推送的本地题（可先筛选「未推送」或勾选题目）')),
      );
      return;
    }

    final session = await _cloudPush.loadSession();
    if (!mounted) return;
    if (session == null || session.token.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未登录：请先在账号页登录后再推送云端')));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(single == null ? '推送云端审核？' : '推送该题到云端？'),
        content: Text(
          '将投稿 ${targets.length} 道本地题到云端待审核队列。\n'
          '不会直接发布；管理员通过后其他设备「更新」才能拉到。\n'
          '空答案 / 选项不足的题会校验失败，不会投稿。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('推送'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final result = await _cloudPush.pushItems(
        targets,
        onProgress: (msg) {
          if (!mounted) return;
          setState(() => _cloudStatusText = msg);
        },
      );
      await _load();
      if (!mounted) return;
      setState(() {
        _selectMode = false;
        _selectedIds.clear();
      });
      final detail = result.errors.isEmpty
          ? result.summaryText
          : '${result.summaryText}\n${result.errors.take(3).join('\n')}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('推送完成：$detail'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('推送失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    if (result == null || _busy) return;
    setState(() => _busy = true);
    try {
      // 云端镜像是只读快照：编辑必须另存为本地题，不能篡改其云端归属。
      final newId = UniqueQuizKeyGenerator.key(
        result.question,
        options: result.options,
      );
      final updated = result.copyWith(
        id: newId,
        createdAt: item.createdAt ?? result.createdAt,
        origin: item.isCloud ? 'local' : item.origin,
        source: item.isCloud ? '云端题库（本地修改）' : result.source,
        syncStatus: item.isCloud
            ? QuizSyncStatus.localOnly
            : (newId == item.id &&
                  item.syncStatus == QuizSyncStatus.pendingReview)
            ? QuizSyncStatus.pendingReview
            : QuizSyncStatus.localOnly,
        clearLastSubmitError: true,
        clearRemoteSubmissionId: item.isCloud,
      );
      if (item.isCloud) {
        await QuizBankStorage.insertIfAbsent(updated);
      } else {
        await QuizBankStorage.replaceItem(item.id, updated);
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(item.isCloud ? '已另存为本地修改副本' : '已保存修改')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pullCloud({bool resetCursor = false}) async {
    if (_busy) return;
    if (resetCursor) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('重置并全量重拉？'),
          content: const Text(
            '将清空本地同步游标，按已订阅分类重新拉取云端正式题。\n'
            '不会删除你本地 OCR/手工录入的题。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('开始'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      final result = await _cloudPull.pullAll(
        resetCursor: resetCursor,
        onProgress: (msg) {
          if (!mounted) return;
          setState(() => _cloudStatusText = msg);
        },
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('云端同步完成：${result.summaryText}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('云端同步失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _repairCloudImages() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await _cloudPull.repairImages(
        onProgress: (msg) {
          if (!mounted) return;
          setState(() => _cloudStatusText = msg);
        },
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '补图完成：扫描 ${result.scanned} · 成功 ${result.cached} · 失败 ${result.failed}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('补图失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manageCloudSubscriptions() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final catalogs = await _cloudPull.fetchCatalogs();
      final selected = (await _cloudPull.loadSubscribedCategories()).toSet();
      if (!mounted) return;
      setState(() => _busy = false);
      final result = await showModalBottomSheet<List<String>>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => _CloudSubscriptionSheet(
          catalogs: catalogs,
          initiallySelected: selected,
        ),
      );
      if (result == null) return;
      await _cloudPull.saveSubscribedCategories(result);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已保存订阅 ${result.length} 个分类')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加载分类失败：$e')));
      setState(() => _busy = false);
    }
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
    final pushableCount = _pushTargets.where((e) => e.canPushToCloud).length;
    return Scaffold(
      appBar: AppBar(
        // 窄屏：标题可收缩，避免与 actions 抢宽导致图标叠/裁切。
        title: Text(
          _selectMode
              ? '已选 ${_selectedIds.length}'
              : '题库 ${_filtered.length}/${_items.length}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // 只保留 2～3 个主操作；导出/导入/去重等进「更多」。
        actions: [
          if (_selectMode) ...[
            IconButton(
              onPressed: _busy ? null : _selectAllFilteredPushable,
              icon: const Icon(Icons.select_all_rounded),
              tooltip: '全选可推送',
            ),
            IconButton(
              onPressed: _busy ? null : () => _pushToCloud(),
              icon: const Icon(Icons.cloud_upload_rounded),
              tooltip: '推送已选',
            ),
            IconButton(
              onPressed: _busy ? null : _toggleSelectMode,
              icon: const Icon(Icons.close_rounded),
              tooltip: '退出多选',
            ),
          ] else ...[
            IconButton(
              onPressed: _busy ? null : _toggleSelectMode,
              icon: const Icon(Icons.checklist_rtl_rounded),
              tooltip: '多选推送',
            ),
            IconButton(
              onPressed: _busy ? null : () => _pushToCloud(),
              icon: const Icon(Icons.cloud_upload_rounded),
              tooltip: '推送未上云本地题',
            ),
            PopupMenuButton<String>(
              tooltip: '更多',
              enabled: !_busy,
              onSelected: (value) {
                switch (value) {
                  case 'pull':
                    _pullCloud();
                    break;
                  case 'export':
                    _exportJson();
                    break;
                  case 'import':
                    _importJson();
                    break;
                  case 'dedupe':
                    _deduplicate();
                    break;
                  case 'copy':
                    _copyAll();
                    break;
                  case 'refresh':
                    _load();
                    break;
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'pull',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.cloud_download_rounded),
                    title: Text('更新云端题库'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'export',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.upload_file_rounded),
                    title: Text('导出 JSON'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'import',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.download_rounded),
                    title: Text('导入 JSON'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'dedupe',
                  enabled: _items.isNotEmpty,
                  child: const ListTile(
                    dense: true,
                    leading: Icon(Icons.cleaning_services_rounded),
                    title: Text('去重整理'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'copy',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.copy_all_rounded),
                    title: Text('复制全部（当前筛选）'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'refresh',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.refresh_rounded),
                    title: Text('刷新'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (_cloudStatusText != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.cloud_outlined,
                        size: 16,
                        color: Colors.black54,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _cloudStatusText!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 0,
                    children: [
                      TextButton(
                        onPressed: _busy ? null : () => _pullCloud(),
                        child: const Text('更新'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : () => _pushToCloud(),
                        child: Text(
                          _selectMode
                              ? '推送已选(${_selectedIds.length})'
                              : '推送云端($pushableCount)',
                        ),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _manageCloudSubscriptions,
                        child: const Text('分类'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _repairCloudImages,
                        child: const Text('仅补图'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _pullCloud(resetCursor: true),
                        child: const Text('全量重拉'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: '搜索题目 / 选项 / 答案 / 分类',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('全部'),
                    selected: _originFilter == 'all',
                    onSelected: (_) {
                      setState(() => _originFilter = 'all');
                      _applyFilter();
                    },
                  ),
                  const SizedBox(width: 6),
                  FilterChip(
                    label: const Text('云端'),
                    selected: _originFilter == 'cloud',
                    onSelected: (_) {
                      setState(() => _originFilter = 'cloud');
                      _applyFilter();
                    },
                  ),
                  const SizedBox(width: 6),
                  FilterChip(
                    label: const Text('本地'),
                    selected: _originFilter == 'local',
                    onSelected: (_) {
                      setState(() => _originFilter = 'local');
                      _applyFilter();
                    },
                  ),
                  const SizedBox(width: 6),
                  FilterChip(
                    label: const Text('未推送'),
                    selected: _originFilter == 'unpushed',
                    onSelected: (_) {
                      setState(() => _originFilter = 'unpushed');
                      _applyFilter();
                    },
                  ),
                  if (_categories.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    DropdownButton<String>(
                      value: _categoryFilter,
                      underline: const SizedBox.shrink(),
                      hint: const Text('分类'),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('全部分类')),
                        ..._categories.map(
                          (c) => DropdownMenuItem(value: c, child: Text(c)),
                        ),
                      ],
                      onChanged: (v) {
                        setState(() => _categoryFilter = v ?? '');
                        _applyFilter();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: _filtered.isEmpty
                ? const Center(child: Text('暂无题目，去录入页添加'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final item = _filtered[i];
                      final selected = _selectedIds.contains(item.id);
                      final statusLabel = item.isCloud
                          ? '云端'
                          : QuizSyncStatus.label(item.syncStatus);
                      final statusColor = item.isCloud
                          ? Colors.indigo.shade700
                          : _syncStatusColor(item.syncStatus);
                      final statusBg = item.isCloud
                          ? Colors.indigo.shade50
                          : _syncStatusBg(item.syncStatus);
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        color: selected ? Colors.blue.shade50 : null,
                        child: InkWell(
                          onLongPress: () {
                            if (!_selectMode) {
                              setState(() {
                                _selectMode = true;
                                _selectedIds.add(item.id);
                              });
                            }
                          },
                          onTap: _selectMode
                              ? () => _toggleSelected(item)
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_selectMode) ...[
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                          top: 2,
                                        ),
                                        child: Icon(
                                          selected
                                              ? Icons.check_box_rounded
                                              : Icons
                                                    .check_box_outline_blank_rounded,
                                          size: 22,
                                          color: selected
                                              ? Colors.blue
                                              : Colors.black45,
                                        ),
                                      ),
                                    ],
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
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: statusBg,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        statusLabel,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: statusColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (item.category.trim().isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '分类：${item.category}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                                if ((item.lastSubmitError ?? '')
                                    .trim()
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '推送：${item.lastSubmitError}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.red.shade700,
                                    ),
                                  ),
                                ],
                                if (item.options.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  ...item.options.asMap().entries.map((entry) {
                                    final o = entry.value;
                                    final isCorrect =
                                        QuizAnswerProjection.isCorrectOption(
                                          item,
                                          entry.key,
                                        );
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
                                if (!_selectMode) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    alignment: WrapAlignment.end,
                                    spacing: 0,
                                    children: [
                                      if (item.canPushToCloud)
                                        TextButton.icon(
                                          onPressed: _busy
                                              ? null
                                              : () =>
                                                    _pushToCloud(single: item),
                                          icon: const Icon(
                                            Icons.cloud_upload_rounded,
                                            size: 16,
                                          ),
                                          label: const Text('推送'),
                                        ),
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
                                          ClipboardData(
                                            text: _itemToCopy(item),
                                          ),
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
                              ],
                            ),
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
  int? _correctIndex;

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
    final resolved = QuizAnswerProjection.resolve(item);
    _correctIndex = resolved.needsRepair ? null : resolved.matchedIndex;
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
    if (_correctIndex != null && _correctIndex! >= n) _correctIndex = null;
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
    final correctIndex = _correctIndex;
    final optionEntries = _opts
        .asMap()
        .entries
        .where((entry) => entry.value.text.trim().isNotEmpty)
        .toList();
    final options = optionEntries
        .map((entry) => entry.value.text.trim())
        .toList();
    if (options.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少填写一个选项')));
      return;
    }
    if (correctIndex == null ||
        !optionEntries.any((entry) => entry.key == correctIndex)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择正确答案')));
      return;
    }
    final correct = optionEntries
        .firstWhere((entry) => entry.key == correctIndex)
        .value
        .text
        .trim();
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
        imageUrl: widget.item.imageUrl,
        category: widget.item.category,
        origin: widget.item.origin,
        syncStatus: widget.item.syncStatus,
        lastSubmitAt: widget.item.lastSubmitAt,
        lastSubmitError: widget.item.lastSubmitError,
        remoteSubmissionId: widget.item.remoteSubmissionId,
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
            RadioGroup<int>(
              groupValue: _correctIndex,
              onChanged: (v) => setState(() => _correctIndex = v),
              child: Column(
                children: [
                  for (var i = 0; i < _opts.length; i++) ...[
                    Row(
                      children: [
                        Radio<int>(value: i),
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
                ],
              ),
            ),
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

class _CloudSubscriptionSheet extends StatefulWidget {
  const _CloudSubscriptionSheet({
    required this.catalogs,
    required this.initiallySelected,
  });

  final List<QuizCloudCatalog> catalogs;
  final Set<String> initiallySelected;

  @override
  State<_CloudSubscriptionSheet> createState() =>
      _CloudSubscriptionSheetState();
}

class _CloudSubscriptionSheetState extends State<_CloudSubscriptionSheet> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initiallySelected};
    if (_selected.isEmpty) {
      for (final c in widget.catalogs) {
        final id = c.id.isNotEmpty ? c.id : c.name;
        if (id.isNotEmpty) _selected.add(id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogs = widget.catalogs;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('订阅云端分类', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              '只同步勾选的分类。取消订阅不会删除本机已有题目。',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            if (catalogs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('云端暂无分类目录')),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: catalogs.length,
                  itemBuilder: (ctx, i) {
                    final c = catalogs[i];
                    final id = c.id.isNotEmpty ? c.id : c.name;
                    final checked = _selected.contains(id);
                    return CheckboxListTile(
                      value: checked,
                      dense: true,
                      title: Text(c.name.isEmpty ? id : c.name),
                      subtitle: Text('题量 ${c.count}'),
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selected.add(id);
                          } else {
                            _selected.remove(id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selected
                        ..clear()
                        ..addAll(
                          catalogs.map((c) => c.id.isNotEmpty ? c.id : c.name),
                        );
                    });
                  },
                  child: const Text('全选'),
                ),
                TextButton(
                  onPressed: () => setState(_selected.clear),
                  child: const Text('清空'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, _selected.toList()..sort()),
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
