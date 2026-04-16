import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/novel_source_capability.dart';
import '../../core/novel_source_capability_detector.dart';
import '../../core/novel_source_factory.dart';
import '../../novel_module.dart';
import '../novel_list_page.dart';
import 'book_source_diagnostic_page.dart';
import 'book_source_manager.dart';
import 'book_source_model.dart';

class BookSourceManagerPage extends StatefulWidget {
  const BookSourceManagerPage({
    super.key,
    this.startupMessage = '',
  });

  final String startupMessage;

  @override
  State<BookSourceManagerPage> createState() => _BookSourceManagerPageState();
}

class _BookSourceManagerPageState extends State<BookSourceManagerPage> {
  final TextEditingController _searchController = TextEditingController();

  String _keyword = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
                (e) => BookSourceModel.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList();
        }
      } else if (t.startsWith('{')) {
        final decoded = jsonDecode(t);
        if (decoded is Map) {
          return [
            BookSourceModel.fromJson(
              Map<String, dynamic>.from(decoded),
            ),
          ];
        }
      }
    } catch (_) {
      // 继续按空行分段尝试
    }

    final blocks = t.split(RegExp(r'\n\s*\n'));
    final result = <BookSourceModel>[];

    for (final block in blocks) {
      final b = block.trim();
      if (b.isEmpty) continue;

      try {
        final decoded = jsonDecode(b);
        if (decoded is Map) {
          result.add(
            BookSourceModel.fromJson(
              Map<String, dynamic>.from(decoded),
            ),
          );
        }
      } catch (_) {}
    }

    return result;
  }

  Color _reportColor(NovelSourceCapabilityReport report) {
    if (report.isUsableForRead) return Colors.green;
    if (report.isPartiallySupported) return Colors.orange;
    return Colors.redAccent;
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _showImportDialog() async {
    final inputController = TextEditingController();

    final text = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('导入规则书源'),
          content: SizedBox(
            width: 560,
            child: TextField(
              controller: inputController,
              maxLines: 16,
              decoration: const InputDecoration(
                hintText: '粘贴单个书源 JSON、多个书源数组 JSON，或按段分隔的多个 JSON',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, inputController.text),
              child: const Text('下一步'),
            ),
          ],
        );
      },
    );

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
              title: const Text('导入预检查'),
              content: SizedBox(
                width: 680,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('检测到 ${sources.length} 条书源'),
                    const SizedBox(height: 8),
                    Text('可用：$usableCount'),
                    Text('部分支持：$partialCount'),
                    Text('暂不支持：$unsupportedCount'),
                    const SizedBox(height: 14),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: reports.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 16),
                        itemBuilder: (_, i) {
                          final report = reports[i];
                          final color = _reportColor(report);

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                report.sourceName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(0.10),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      report.statusLabel,
                                      style: TextStyle(
                                        color: color,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.10),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      report.adapterLabel,
                                      style: const TextStyle(
                                        color: Colors.blue,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (report.primaryBlocker.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  report.primaryBlocker,
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '说明：导入不会拦截“暂不支持”的书源，但建议导入后先点“诊断”查看详情。',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.black54,
                        height: 1.5,
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
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('确认导入'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!ok || !mounted) return;

    final manager = context.read<BookSourceManager>();
    final count = await manager.addMany(sources);

    if (!mounted) return;

    _showSnack('成功导入 $count 个书源');

    if (unsupportedCount > 0) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('导入完成'),
          content: Text(
            '其中有 $unsupportedCount 条书源当前版本暂不完整支持。\n'
            '你可以在书源列表中点击“诊断”查看详细原因。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _showEditorDialog({BookSourceModel? source}) async {
    final controller = TextEditingController(
      text: source == null
          ? const JsonEncoder.withIndent('  ').convert({
              'bookSourceName': '',
              'bookSourceUrl': '',
              'bookSourceGroup': '',
              'searchUrl': '',
              'exploreUrl': '',
              'ruleSearch': {},
              'ruleBookInfo': {},
              'ruleToc': {},
              'ruleContent': {},
            })
          : const JsonEncoder.withIndent('  ').convert(source.toJson()),
    );

    final raw = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(source == null ? '新增书源' : '编辑书源'),
          content: SizedBox(
            width: 620,
            child: TextField(
              controller: controller,
              maxLines: 18,
              decoration: const InputDecoration(
                hintText: '请输入单个规则书源 JSON',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    if (!mounted || raw == null || raw.trim().isEmpty) return;

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! Map) {
        throw const FormatException('编辑模式只接受单个书源 JSON 对象，不接受数组');
      }

      final next = BookSourceModel.fromJson(Map<String, dynamic>.from(decoded));
      final manager = context.read<BookSourceManager>();

      if (source != null && source.id != next.id) {
        await manager.deleteById(source.id);
      }

      await manager.addOrUpdate(next);

      if (!mounted) return;
      _showSnack(source == null ? '书源已新增' : '书源已更新');
    } catch (e) {
      if (!mounted) return;
      _showSnack('保存失败：$e');
    }
  }

  Future<void> _confirmDelete(BookSourceModel source) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除书源'),
          content: Text('确定删除「${source.bookSourceName}」吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );

    if (ok != true || !mounted) return;

    await context.read<BookSourceManager>().deleteById(source.id);

    if (!mounted) return;
    _showSnack('已删除书源');
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
Future<void> _showDiagnostic(BookSourceModel source) async {
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => BookSourceDiagnosticPage(
        source: source,
      ),
    ),
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

    if (!mounted || keyword == null || keyword.trim().isEmpty) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(),
      ),
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
                      separatorBuilder: (_, __) => const Divider(height: 16),
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
                              ].join(' · ').ifEmpty('暂无更多信息'),
                              style: const TextStyle(
                                fontSize: 12.5,
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

  Future<void> _applySource(BookSourceModel source) async {
    final report = NovelSourceCapabilityDetector.detect(source.toJson());

    if (report.adapterKind == NovelSourceAdapterKind.unsupported) {
      final ok = await showDialog<bool>(
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

    NovelModule.configureRuleSource(
      bookSourceJson: source.toJson(),
    );

    if (!mounted) return;

    _showSnack('已切换到书源：${source.bookSourceName}');

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const NovelListPageWithProvider(),
      ),
      (_) => false,
    );
  }

  Future<void> _toggleEnable(
    BookSourceManager manager,
    BookSourceModel source,
    bool value,
  ) async {
    await manager.setEnabled(source.id, value);

    if (!mounted) return;

    _showSnack(
      value ? '已启用：${source.bookSourceName}' : '已禁用：${source.bookSourceName}',
    );
  }

  Widget _buildSimpleChip({
    required String text,
    required Color color,
    Color? backgroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor ?? color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildStatusChips(
    BookSourceModel source,
    BookSourceManager manager,
  ) {
    final report = NovelSourceCapabilityDetector.detect(source.toJson());
    final chips = <Widget>[];

    if (manager.currentSourceId == source.id) {
      chips.add(
        _buildSimpleChip(
          text: '当前使用',
          color: Colors.deepOrange,
          backgroundColor: Colors.orange.withOpacity(0.12),
        ),
      );
    }

    chips.add(
      _buildSimpleChip(
        text: source.enabled ? '已启用' : '未启用',
        color: source.enabled ? Colors.green : Colors.grey,
      ),
    );

    if (source.exploreUrl.isNotEmpty) {
      chips.add(
        _buildSimpleChip(
          text: '支持发现页',
          color: Colors.blue,
          backgroundColor: Colors.blue.withOpacity(0.10),
        ),
      );
    }

    final reportColor = _reportColor(report);
    chips.add(
      _buildSimpleChip(
        text: report.statusLabel,
        color: reportColor,
        backgroundColor: reportColor.withOpacity(0.10),
      ),
    );

    chips.add(
      _buildSimpleChip(
        text: report.adapterLabel,
        color: Colors.indigo,
        backgroundColor: Colors.indigo.withOpacity(0.10),
      ),
    );

    if (report.warnings.isNotEmpty) {
      chips.add(
        _buildSimpleChip(
          text: '警告 ${report.warnings.length}',
          color: Colors.orange,
          backgroundColor: Colors.orange.withOpacity(0.10),
        ),
      );
    }

    if (report.blockers.isNotEmpty) {
      chips.add(
        _buildSimpleChip(
          text: '阻塞 ${report.blockers.length}',
          color: Colors.redAccent,
          backgroundColor: Colors.redAccent.withOpacity(0.10),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips,
    );
  }

  Widget _buildSourceCard(
    BookSourceModel source,
    BookSourceManager manager,
  ) {
    final report = NovelSourceCapabilityDetector.detect(source.toJson());
    final reportColor = _reportColor(report);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: reportColor.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  source.bookSourceName.isNotEmpty
                      ? source.bookSourceName
                      : '未命名书源',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Switch(
                value: source.enabled,
                onChanged: (v) => _toggleEnable(manager, source, v),
              ),
            ],
          ),
          _buildStatusChips(source, manager),
          const SizedBox(height: 10),
          if (source.bookSourceGroup.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '分组：${source.bookSourceGroup}',
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 12.5,
                ),
              ),
            ),
          Text(
            source.bookSourceUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 12.5,
            ),
          ),
          if (source.searchUrl.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '搜索：${source.searchUrl}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.black45,
                fontSize: 12,
              ),
            ),
          ],
          if (report.primaryBlocker.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              report.primaryBlocker,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 12.2,
              ),
            ),
          ] else if (report.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              report.warnings.first,
              style: const TextStyle(
                color: Colors.orange,
                fontSize: 12.2,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton(
                onPressed: () => _applySource(source),
                child: Text(
                  manager.currentSourceId == source.id ? '重新使用' : '启用并使用',
                ),
              ),
              OutlinedButton(
                onPressed: () => _showDiagnostic(source),
                child: const Text('诊断'),
              ),
              OutlinedButton(
                onPressed: () => _showEditorDialog(source: source),
                child: const Text('编辑'),
              ),
              OutlinedButton(
                onPressed: () => _testSource(source),
                child: const Text('测试'),
              ),
              OutlinedButton(
                onPressed: () => _exportSource(source),
                child: const Text('导出'),
              ),
              OutlinedButton(
                onPressed: () => _previewSource(source),
                child: const Text('查看'),
              ),
              OutlinedButton(
                onPressed: () => _confirmDelete(source),
                child: const Text('删除'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<BookSourceManager>();
    final sources = manager.search(_keyword);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          '书源管理',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            tooltip: '新增书源',
            onPressed: () => _showEditorDialog(),
            icon: const Icon(Icons.add_box_outlined),
          ),
          IconButton(
            tooltip: '导入书源',
            onPressed: _showImportDialog,
            icon: const Icon(Icons.playlist_add),
          ),
          IconButton(
            tooltip: '导出当前书源',
            onPressed: _exportCurrentSource,
            icon: const Icon(Icons.ios_share_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showImportDialog,
        icon: const Icon(Icons.add),
        label: const Text('导入书源'),
      ),
      body: Column(
        children: [
          if (widget.startupMessage.trim().isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                widget.startupMessage,
                style: const TextStyle(
                  color: Colors.deepOrange,
                  fontSize: 13,
                ),
              ),
            ),
          if (manager.currentSource != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '当前默认书源：${manager.currentSource!.bookSourceName}',
                style: const TextStyle(
                  color: Colors.blue,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _keyword = v),
              decoration: InputDecoration(
                hintText: '搜索书源名称 / 分组 / 域名',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _keyword.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _keyword = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: sources.isEmpty
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(16, 40, 16, 100),
                    children: [
                      Center(
                        child: Text(
                          _keyword.trim().isEmpty
                              ? '还没有书源，点击右下角“导入书源”开始'
                              : '没有找到匹配的书源',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    itemCount: sources.length,
                    itemBuilder: (_, i) => _buildSourceCard(sources[i], manager),
                  ),
          ),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) {
    return trim().isEmpty ? fallback : this;
  }
}