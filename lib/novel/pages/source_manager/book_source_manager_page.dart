import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../design_system/app_tokens.dart';
import '../../../design_system/widgets/app_cards.dart';
import '../../../design_system/widgets/app_page_scaffold.dart';

import '../../core/novel_source_capability.dart';
import '../../core/novel_source_capability_detector.dart';
import '../../core/novel_source_factory.dart';
import '../../novel_module.dart';
import '../novel_list_page.dart';
import 'book_source_diagnostic_page.dart';
import 'book_source_manager.dart';
import 'book_source_model.dart';
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
            BookSourceModel.fromJson(Map<String, dynamic>.from(decoded)),
          );
        }
      } catch (_) {}
    }

    return result;
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

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
                      minLines: 8,
                      maxLines: null,
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

    final ok =
        await showDialog<bool>(
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
                          backgroundColor: Colors.orange.withValues(
                            alpha: 0.10,
                          ),
                        ),
                        BookSourceSimpleChip(
                          text: '暂不支持 $unsupportedCount',
                          color: Colors.redAccent,
                          backgroundColor: Colors.redAccent.withValues(
                            alpha: 0.10,
                          ),
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
                                      color: color.withValues(alpha: 0.10),
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
                                      color: Colors.blue.withValues(
                                        alpha: 0.10,
                                      ),
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
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('确认导入书源'),
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
        final maxDialogHeight = MediaQuery.sizeOf(context).height * 0.72;

        return AlertDialog(
          title: Text(source == null ? '新增书源规则 JSON' : '编辑书源规则 JSON'),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxDialogHeight),
            child: SizedBox(
              width: 620,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '编辑单个书源对象；保存前会校验 JSON 格式。',
                    style: TextStyle(color: Colors.black54, fontSize: 12.5),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: TextField(
                      controller: controller,
                      minLines: 8,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        labelText: '单个书源 JSON',
                        hintText: '请输入单个规则书源 JSON',
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
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('保存规则'),
            ),
          ],
        );
      },
    );
    controller.dispose();

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
        builder: (_) => BookSourceDiagnosticPage(source: source),
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

  Widget _buildManagerHero(BookSourceManager manager, int visibleCount) {
    final total = manager.items.length;
    final enabled = manager.enabledItems.length;
    final currentName = manager.currentSource?.bookSourceName.trim();

    return AppLightHeroCard(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      eyebrow: 'SOURCE RULES',
      title: '书源管理',
      subtitle: currentName != null && currentName.isNotEmpty
          ? '当前默认：$currentName'
          : '导入、预检查并启用小说规则源',
      badge: '小说',
      accentGradient: AppTokens.violetGradient,
      leading: IconButton.filledTonal(
        onPressed: () => Navigator.maybePop(context),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      actions: [
        AppStatusPill(
          label: '全部 $total',
          icon: Icons.rule_folder_rounded,
          color: AppTokens.violet,
        ),
        AppStatusPill(
          label: '启用 $enabled',
          icon: Icons.check_circle_rounded,
          color: AppTokens.emerald,
        ),
        if (_keyword.trim().isNotEmpty)
          AppStatusPill(
            label: '匹配 $visibleCount',
            icon: Icons.search_rounded,
            color: AppTokens.primaryBlue,
          ),
      ],
    );
  }

  Widget _buildStartupBanner() {
    if (widget.startupMessage.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: AppTokens.warning.withValues(alpha: 0.18)),
      ),
      child: Text(
        widget.startupMessage,
        style: const TextStyle(
          color: AppTokens.warning,
          fontSize: 12.5,
          height: 1.45,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: AppCompactActionCard(
              title: '导入书源',
              subtitle: 'JSON / 预检查',
              icon: Icons.playlist_add_rounded,
              color: AppTokens.violet,
              onTap: _showImportDialog,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AppCompactActionCard(
              title: '新增规则',
              subtitle: '手动编辑',
              icon: Icons.add_box_rounded,
              color: AppTokens.primaryBlue,
              onTap: () => _showEditorDialog(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AppCompactActionCard(
              title: '导出',
              subtitle: '当前书源',
              icon: Icons.ios_share_rounded,
              color: AppTokens.emerald,
              onTap: _exportCurrentSource,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBox() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTokens.divider),
        boxShadow: AppTokens.shadowSm(color: AppTokens.violet),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: AppTokens.violet),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _keyword = v),
              decoration: const InputDecoration(
                hintText: '搜索名称 / 分组 / 域名',
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (_keyword.isNotEmpty)
            IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                _searchController.clear();
                setState(() => _keyword = '');
              },
            ),
        ],
      ),
    );
  }

  Widget _buildEmptySources() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        16,
        44,
        16,
        AppTokens.pageBottomPadding,
      ),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(AppTokens.radiusLg),
            border: Border.all(color: AppTokens.divider),
            boxShadow: AppTokens.shadowSm(),
          ),
          child: Column(
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: AppTokens.surfaceTint,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(
                  _keyword.trim().isEmpty
                      ? Icons.rule_folder_outlined
                      : Icons.search_off_rounded,
                  color: AppTokens.violet,
                  size: 32,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _keyword.trim().isEmpty ? '还没有书源' : '没有找到匹配的书源',
                style: const TextStyle(
                  color: AppTokens.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _keyword.trim().isEmpty
                    ? '点击“导入书源”粘贴 JSON，系统会先做可用性预检查。'
                    : '换个关键词，或清空搜索查看全部书源。',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTokens.textSecondary,
                  fontSize: 12.5,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_keyword.trim().isEmpty) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _showImportDialog,
                  icon: const Icon(Icons.playlist_add_rounded),
                  label: const Text('导入书源'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<BookSourceManager>();
    final sources = manager.search(_keyword);

    return AppPageScaffold(
      safeBottom: false,
      child: Column(
        children: [
          _buildManagerHero(manager, sources.length),
          _buildStartupBanner(),
          _buildQuickActions(),
          _buildSearchBox(),
          Expanded(
            child: sources.isEmpty
                ? _buildEmptySources()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      AppTokens.pageBottomPadding + 32,
                    ),
                    itemCount: sources.length,
                    itemBuilder: (_, i) => BookSourceCard(
                      source: sources[i],
                      manager: manager,
                      onToggleEnable: (v) =>
                          _toggleEnable(manager, sources[i], v),
                      onApply: () => _applySource(sources[i]),
                      onDiagnostic: () => _showDiagnostic(sources[i]),
                      onEdit: () => _showEditorDialog(source: sources[i]),
                      onTest: () => _testSource(sources[i]),
                      onExport: () => _exportSource(sources[i]),
                      onPreview: () => _previewSource(sources[i]),
                      onDelete: () => _confirmDelete(sources[i]),
                    ),
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
