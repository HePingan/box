import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../design_system/app_tokens.dart';
import '../../../design_system/widgets/app_page_scaffold.dart';

import '../../core/novel_source_capability.dart';
import '../../core/novel_source_capability_detector.dart';
import '../../novel_module.dart';
import 'widgets/book_source_manager_hero.dart';
import 'widgets/book_source_manager_widgets.dart';

class BookSourceManagerPage extends StatefulWidget {
  const BookSourceManagerPage({super.key, this.startupMessage = ''});

  final String startupMessage;

  @override
  State<BookSourceManagerPage> createState() => _BookSourceManagerPageState();
}

class _BookSourceManagerPageState extends State<BookSourceManagerPage> {
  final TextEditingController _searchController = TextEditingController();
  String _keyword = '';
  final Set<String> _expandedIds = {};

  void _toggleExpand(String id) {
    setState(() {
      if (_expandedIds.contains(id)) {
        _expandedIds.remove(id);
      } else {
        _expandedIds.add(id);
      }
    });
  }

  bool _isExpanded(String id) => _expandedIds.contains(id);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ── Dialogs ──

  Future<void> _showImportDialog() async {
    final inputController = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) {
        final maxDialogHeight = MediaQuery.sizeOf(context).height * 0.72;
        return AlertDialog(
          title: const Text('导入书源规则 JSON'),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxDialogHeight),
            child: SizedBox(
              width: 580,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '粘贴单个书源、书源数组，或按空行分隔的多个 JSON。导入前会先做可用性预检查。',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: TextField(
                      controller: inputController,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        labelText: '书源规则 JSON',
                        hintText:
                            '[{"bookSourceName": "...", "bookSourceUrl": "..."}]',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, inputController.text),
              icon: const Icon(Icons.rule_folder_rounded),
              label: const Text('预检查'),
            ),
          ],
        );
      },
    );
    inputController.dispose();
    if (!mounted || text == null || text.trim().isEmpty) return;

    final sources = _parseSources(text);
    if (sources.isEmpty) {
      _showSnack('没有解析到有效书源');
      return;
    }
    await _showImportPreviewDialog(sources);
  }

  Future<void> _showImportPreviewDialog(List<BookSourceModel> sources) async {
    final reports = sources
        .map((e) => NovelSourceCapabilityDetector.detect(e.toJson()))
        .toList();
    final usableCount = reports.where((e) => e.isUsableForRead).length;
    final partialCount = reports.where((e) => e.isPartiallySupported).length;
    final unsupportedCount = reports
        .where((e) => e.adapterKind == NovelSourceAdapterKind.unsupported)
        .length;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('书源导入预检查'),
          content: SizedBox(
            width: 680,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('检测到 ${sources.length} 条书源规则'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    BookSourceSimpleChip(
                      text: '可用 $usableCount',
                      color: Colors.green,
                      backgroundColor: Colors.green.withValues(alpha: 0.10),
                    ),
                    BookSourceSimpleChip(
                      text: '部分支持 $partialCount',
                      color: Colors.orange,
                      backgroundColor: Colors.orange.withValues(alpha: 0.10),
                    ),
                    BookSourceSimpleChip(
                      text: '暂不支持 $unsupportedCount',
                      color: Colors.redAccent,
                      backgroundColor: Colors.redAccent.withValues(alpha: 0.10),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: reports.length,
                    separatorBuilder: (_, _) => const Divider(height: 16),
                    itemBuilder: (_, i) {
                      final report = reports[i];
                      final color = bookSourceReportColor(report);
                      final source = sources[i];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            source.bookSourceName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              BookSourceSimpleChip(
                                text: report.statusLabel,
                                color: color,
                              ),
                              const SizedBox(width: 6),
                              BookSourceSimpleChip(
                                text: report.adapterLabel,
                                color: Colors.indigo,
                              ),
                            ],
                          ),
                          if (report.warnings.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                report.warnings.first,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange.shade700,
                                  height: 1.3,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.download_rounded),
              label: Text('导入 ${sources.length} 条'),
            ),
          ],
        );
      },
    );

    if (ok == true && mounted) {
      final manager = context.read<BookSourceManager>();
      int added = 0;
      for (final s in sources) {
        try {
          await manager.addOrUpdate(s);
          added++;
        } catch (e) {
          _showSnack('导入失败: ${s.bookSourceName} → $e');
        }
      }
      _showSnack('成功导入 $added / ${sources.length} 条书源');
    }
  }

  Future<void> _showEditorDialog({BookSourceModel? source}) async {
    final isNew = source == null;
    final nameCtrl = TextEditingController(text: source?.bookSourceName ?? '');
    final urlCtrl = TextEditingController(text: source?.bookSourceUrl ?? '');
    final jsonCtrl = TextEditingController(
      text: source != null ? source.toRawJson() : '',
    );
    var mode = 'form';

    final result = await showDialog<BookSourceModel?>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isNew ? '新增书源' : '编辑书源'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ChoiceChip(
                            label: const Text('表单'),
                            selected: mode == 'form',
                            onSelected: (_) =>
                                setDialogState(() => mode = 'form'),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('原始 JSON'),
                            selected: mode == 'raw',
                            onSelected: (_) =>
                                setDialogState(() => mode = 'raw'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (mode == 'form') ...[
                        TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: '书源名称 *',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: urlCtrl,
                          decoration: const InputDecoration(
                            labelText: '书源地址 *',
                            hintText: 'https://...',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ] else ...[
                        TextField(
                          controller: jsonCtrl,
                          maxLines: 12,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                          decoration: const InputDecoration(
                            labelText: '书源 JSON',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    if (mode == 'form') {
                      final name = nameCtrl.text.trim();
                      final url = urlCtrl.text.trim();
                      if (name.isEmpty || url.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('名称和地址不能为空')),
                        );
                        return;
                      }
                      final existing = source?.toJson() ?? {};
                      existing['bookSourceName'] = name;
                      existing['bookSourceUrl'] = url;
                      Navigator.pop(
                        context,
                        BookSourceModel.fromJson(existing),
                      );
                    } else {
                      try {
                        final decoded = jsonDecode(jsonCtrl.text);
                        Navigator.pop(
                          context,
                          BookSourceModel.fromJson(
                            Map<String, dynamic>.from(decoded),
                          ),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('JSON 解析失败: $e')),
                        );
                      }
                    }
                  },
                  icon: Icon(isNew ? Icons.add_rounded : Icons.save_rounded),
                  label: Text(isNew ? '新增' : '保存'),
                ),
              ],
            );
          },
        );
      },
    );

    nameCtrl.dispose();
    urlCtrl.dispose();
    jsonCtrl.dispose();

    if (result == null || !mounted) return;
    try {
      final manager = context.read<BookSourceManager>();
      await manager.addOrUpdate(result);
      _showSnack('${isNew ? "新增" : "已更新"} ${result.bookSourceName}');
    } catch (e) {
      _showSnack('保存失败: $e');
    }
  }

  Future<void> _confirmDelete(BookSourceModel source) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除书源'),
        content: Text('确定删除 "${source.bookSourceName}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('删除'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      try {
        await context.read<BookSourceManager>().deleteById(source.id);
        _showSnack('已删除 ${source.bookSourceName}');
      } catch (e) {
        _showSnack('删除失败: $e');
      }
    }
  }

  Future<void> _showDiagnostic(BookSourceModel source) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookSourceDiagnosticPage(source: source),
      ),
    );
  }

  // ── Actions ──

  Future<void> _applySource(BookSourceModel source) async {
    final report = NovelSourceCapabilityDetector.detect(source.toJson());
    if (report.adapterKind == NovelSourceAdapterKind.unsupported) {
      final ok =
          await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('当前书源暂不完整支持'),
              content: Text(
                report.primaryBlocker.isNotEmpty
                    ? '${report.primaryBlocker}\n\n仍要设为当前书源吗？'
                    : '该书源当前版本暂不完整支持，仍要设为当前书源吗？',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('仍然使用'),
                ),
              ],
            ),
          ) ??
          false;
      if (!ok || !mounted) return;
    }

    final manager = context.read<BookSourceManager>();
    await manager.setCurrentSource(source.id, ensureEnabled: true);
    NovelModule.configureRuleSource(bookSourceJson: source.toJson());

    if (!mounted) return;
    _showSnack('已切换到书源：${source.bookSourceName}');
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const NovelListPageWithProvider()),
      (_) => false,
    );
  }

  Future<void> _exportSource(BookSourceModel source) async {
    await Clipboard.setData(
      ClipboardData(
        text: const JsonEncoder.withIndent('  ').convert(source.toJson()),
      ),
    );
    if (!mounted) return;
    _showSnack('已复制书源：${source.bookSourceName}');
  }

  Future<void> _exportCurrentSource() async {
    final manager = context.read<BookSourceManager>();
    final current = manager.currentSource;
    if (current == null) {
      _showSnack('当前没有正在使用的书源');
      return;
    }
    await _exportSource(current);
  }

  Future<void> _previewSource(BookSourceModel source) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(source.toJson()),
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _checkAllHealth() async {
    final manager = context.read<BookSourceManager>();
    final enabled = manager.enabledItems;
    if (enabled.isEmpty) {
      _showSnack('没有已启用的书源需要检测');
      return;
    }

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _HealthCheckDialog(enabledCount: enabled.length),
    );

    for (int i = 0; i < enabled.length; i++) {
      if (!mounted) return;
      await manager.ping(enabled[i]);
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (!mounted) return;
    _showSnack('检测完成：${enabled.length} 个书源');
  }

  Future<void> _testSource(BookSourceModel source) async {
    final keywordController = TextEditingController(text: '斗罗');
    final keyword = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('测试书源'),
          content: TextField(
            controller: keywordController,
            decoration: const InputDecoration(
              hintText: '请输入测试搜索关键词',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, keywordController.text),
              child: const Text('开始测试'),
            ),
          ],
        );
      },
    );
    keywordController.dispose();
    if (!mounted || keyword == null || keyword.trim().isEmpty) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final sourceImpl = NovelSourceFactory.fromBookSourceJson(source.toJson());
      final books = await sourceImpl.searchBooks(keyword.trim(), page: 1);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      final preview = books.take(8).toList();
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('测试成功：共 ${books.length} 条'),
            content: SizedBox(
              width: 520,
              child: books.isEmpty
                  ? const Text('请求成功，但未返回搜索结果。')
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: preview.length,
                      separatorBuilder: (_, _) => const Divider(height: 16),
                      itemBuilder: (_, i) {
                        final b = preview[i];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              b.title.isNotEmpty ? b.title : '未知书名',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                if (b.author.isNotEmpty) b.author,
                                if (b.category.isNotEmpty) b.category,
                                if (b.status.isNotEmpty) b.status,
                              ].join(' · '),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showSnack('测试失败：$e');
    }
  }

  Future<void> _toggleEnable(
    BookSourceManager manager,
    BookSourceModel source,
    bool value,
  ) async {
    final updated = source.copyWith(enabled: value);
    await manager.addOrUpdate(updated);
    setState(() {});
  }

  // ── Utilities ──

  List<BookSourceModel> _parseSources(String text) {
    final t = text.trim();
    if (t.isEmpty) return [];
    try {
      if (t.startsWith('[')) {
        final decoded = jsonDecode(t);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map(
                (e) => BookSourceModel.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList();
        }
      } else if (t.startsWith('{')) {
        final decoded = jsonDecode(t);
        if (decoded is Map) {
          return [BookSourceModel.fromJson(Map<String, dynamic>.from(decoded))];
        }
      }
    } catch (_) {}

    final blocks = t.split(RegExp(r'\n\s*\n'));
    final result = <BookSourceModel>[];
    for (final block in blocks) {
      final b = block.trim();
      if (b.isEmpty) continue;
      try {
        final decoded = jsonDecode(b);
        if (decoded is Map) {
          result.add(
            BookSourceModel.fromJson(Map<String, dynamic>.from(decoded)),
          );
        }
      } catch (_) {}
    }
    return result;
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<BookSourceManager>();
    final sources = manager.search(_keyword);

    return AppPageScaffold(
      safeBottom: false,
      child: Column(
        children: [
          BookSourceManagerHero(
            manager: manager,
            visibleCount: sources.length,
            keyword: _keyword,
          ),
          BookSourceStartupBanner(message: widget.startupMessage),
          BookSourceQuickActions(
            onImport: _showImportDialog,
            onAddRule: () => _showEditorDialog(),
            onExportCurrent: _exportCurrentSource,
            onCheckHealth: _checkAllHealth,
          ),
          BookSourceSearchBox(
            controller: _searchController,
            keyword: _keyword,
            onChanged: (v) => setState(() => _keyword = v),
            onClear: () {
              _searchController.clear();
              setState(() => _keyword = '');
            },
          ),
          Expanded(
            child: sources.isEmpty
                ? BookSourceEmptySources(keyword: _keyword)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      AppTokens.pageBottomPadding + 32,
                    ),
                    itemCount: sources.length,
                    itemBuilder: (_, i) {
                      final src = sources[i];
                      final expanded = _isExpanded(src.id);
                      return BookSourceCard(
                        source: src,
                        manager: manager,
                        expanded: expanded,
                        onTapExpand: () => _toggleExpand(src.id),
                        onToggleEnable: (v) =>
                            _toggleEnable(manager, src, v),
                        onApply: () => _applySource(src),
                        onDiagnostic: () => _showDiagnostic(src),
                        onEdit: () => _showEditorDialog(source: src),
                        onTest: () => _testSource(src),
                        onExport: () => _exportSource(src),
                        onPreview: () => _previewSource(src),
                        onDelete: () => _confirmDelete(src),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 检测进行中的对话框
class _HealthCheckDialog extends StatelessWidget {
  const _HealthCheckDialog({required this.enabledCount});

  final int enabledCount;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 16),
            Text(
              '正在检测 $enabledCount 个书源…',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '请稍候，正在逐源测试连通性',
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
