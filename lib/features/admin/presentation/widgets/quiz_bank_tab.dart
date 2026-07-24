import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/quiz_bank_admin_client.dart';
import '../../domain/admin_resource.dart';
import '../../domain/admin_resource_provider.dart';
import '../../domain/quiz_bank_import_report.dart';
import '../../domain/quiz_bank_models.dart';

part 'quiz_bank_tab_widgets.part.dart';

class QuizBankResourceProvider implements ResourceProvider<QuizBankQuestion> {
  QuizBankResourceProvider({QuizBankAdminClient? client})
    : _client = client ?? QuizBankAdminClient();

  final QuizBankAdminClient _client;

  @override
  AdminResourceType get resourceType => AdminResourceType.quizBank;

  @override
  Future<List<QuizBankQuestion>> fetchAll(String? serverUrl, String? token) {
    return _client.fetchQuestions(
      serverUrl: _required(serverUrl, '服务器地址'),
      token: _required(token, '管理员令牌'),
    );
  }

  @override
  Future<QuizBankQuestion> create(
    String? serverUrl,
    String? token,
    Map<String, dynamic> data,
  ) => _client.createQuestion(
    serverUrl: _required(serverUrl, '服务器地址'),
    token: _required(token, '管理员令牌'),
    data: data,
  );

  @override
  Future<QuizBankQuestion> update(
    String? serverUrl,
    String? token,
    String id,
    Map<String, dynamic> data,
  ) => _client.updateQuestion(
    serverUrl: _required(serverUrl, '服务器地址'),
    token: _required(token, '管理员令牌'),
    id: id,
    data: data,
  );

  @override
  Future<void> delete(String? serverUrl, String? token, String id) =>
      _client.deleteQuestion(
        serverUrl: _required(serverUrl, '服务器地址'),
        token: _required(token, '管理员令牌'),
        id: id,
      );

  @override
  Widget buildListPage({
    required BuildContext context,
    String? serverUrl,
    String? token,
  }) => QuizBankAdminTab(
    provider: this,
    serverUrl: serverUrl ?? '',
    token: token ?? '',
  );

  Future<List<QuizBankSubmission>> fetchPending(
    String serverUrl,
    String token,
  ) => _client.fetchPendingSubmissions(serverUrl: serverUrl, token: token);

  Future<List<QuizBankSubmission>> fetchSubmissions(
    String serverUrl,
    String token, {
    String status = '',
  }) => _client.fetchSubmissions(
    serverUrl: serverUrl,
    token: token,
    status: status,
  );

  Future<QuizBankSubmission> reviewSubmission(
    String serverUrl,
    String token,
    String id,
    String action, {
    String reviewNote = '',
  }) => _client.reviewSubmission(
    serverUrl: serverUrl,
    token: token,
    id: id,
    action: action,
    reviewNote: reviewNote,
  );

  Future<QuizBankImportReport> importQuestions(
    String serverUrl,
    String token,
    List<Map<String, dynamic>> items, {
    bool dryRun = false,
    bool publish = true,
  }) => _client.importQuestions(
    serverUrl: serverUrl,
    token: token,
    items: items,
    dryRun: dryRun,
    publish: publish,
  );

  Future<void> bulkSetCategory(
    String serverUrl,
    String token,
    List<String> ids,
    String category,
  ) => _client.bulkSetCategory(
    serverUrl: serverUrl,
    token: token,
    ids: ids,
    category: category,
  );

  Future<List<Map<String, dynamic>>> fetchIncomplete(
    String serverUrl,
    String token, {
    String filter = '',
    String query = '',
  }) => _client.fetchIncomplete(
    serverUrl: serverUrl,
    token: token,
    filter: filter,
    query: query,
  );

  Future<Map<String, dynamic>> bulkIncomplete(
    String serverUrl,
    String token, {
    required String action,
    required List<String> ids,
    String category = '',
    String correctAnswer = '',
    String analysis = '',
    String image = '',
    Map<String, String>? answers,
  }) => _client.bulkIncomplete(
    serverUrl: serverUrl,
    token: token,
    action: action,
    ids: ids,
    category: category,
    correctAnswer: correctAnswer,
    analysis: analysis,
    image: image,
    answers: answers,
  );

  Future<List<Map<String, dynamic>>> fetchImports(
    String serverUrl,
    String token,
  ) => _client.fetchImports(serverUrl: serverUrl, token: token);

  Future<Map<String, dynamic>> bulkUpdateQuestions(
    String serverUrl,
    String token, {
    required String action,
    required List<String> ids,
    String category = '',
    String image = '',
  }) => _client.bulkUpdateQuestions(
    serverUrl: serverUrl,
    token: token,
    action: action,
    ids: ids,
    category: category,
    image: image,
  );

  Future<void> completeIncomplete(
    String serverUrl,
    String token,
    String id,
    String correctAnswer, {
    String category = '',
    String analysis = '',
    String? image,
  }) => _client.completeIncomplete(
    serverUrl: serverUrl,
    token: token,
    id: id,
    correctAnswer: correctAnswer,
    category: category,
    analysis: analysis,
    image: image,
  );

  Future<String> uploadQuizImage(
    String serverUrl,
    String token,
    String imageData,
  ) => _client.uploadQuizImage(
    serverUrl: serverUrl,
    token: token,
    imageData: imageData,
  );

  static String _required(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      throw StateError('请先登录并配置$label。');
    }
    return value;
  }
}

class QuizBankAdminTab extends StatefulWidget {
  const QuizBankAdminTab({
    super.key,
    required this.provider,
    required this.serverUrl,
    required this.token,
  });

  final QuizBankResourceProvider provider;
  final String serverUrl;
  final String token;

  @override
  State<QuizBankAdminTab> createState() => _QuizBankAdminTabState();
}

class _QuizBankAdminTabState extends State<QuizBankAdminTab> {
  final _searchController = TextEditingController();
  List<QuizBankQuestion> _questions = const [];
  int _pendingCount = 0;
  int _incompleteCount = 0;
  int _importCount = 0;
  final Set<String> _selectedIds = <String>{};
  bool _loading = true;
  String? _error;
  /// all | published | pending | rejected
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.serverUrl.trim().isEmpty || widget.token.trim().isEmpty) {
      setState(() {
        _loading = false;
        _error = '请先以管理员身份登录服务器后再管理题库。';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        widget.provider.fetchAll(widget.serverUrl, widget.token),
        widget.provider.fetchPending(widget.serverUrl, widget.token),
        widget.provider.fetchIncomplete(widget.serverUrl, widget.token),
        widget.provider.fetchImports(widget.serverUrl, widget.token),
      ]);
      if (!mounted) return;
      setState(() {
        _questions = results[0] as List<QuizBankQuestion>;
        _pendingCount = (results[1] as List<QuizBankSubmission>).length;
        _incompleteCount = (results[2] as List).length;
        _importCount = (results[3] as List).length;
        _selectedIds.removeWhere((id) => !_questions.any((q) => q.id == id));
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<QuizBankQuestion> get _visibleQuestions {
    final query = _searchController.text.trim().toLowerCase();
    Iterable<QuizBankQuestion> items = _questions;
    if (_statusFilter != 'all') {
      items = items.where((item) {
        if (_statusFilter == 'published') return item.isPublished;
        return item.status == _statusFilter;
      });
    }
    if (query.isEmpty) return items.toList(growable: false);
    return items
        .where((item) {
          return item.question.toLowerCase().contains(query) ||
              item.answer.toLowerCase().contains(query) ||
              item.category.toLowerCase().contains(query) ||
              item.tags.any((tag) => tag.toLowerCase().contains(query));
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _questions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _questions.isEmpty) {
      return _ErrorState(message: _error!, onRetry: _load);
    }
    final questions = _visibleQuestions;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '题库管理',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: _loading ? null : _load,
                tooltip: '刷新',
                icon: const Icon(Icons.refresh_rounded),
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : _importJson,
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('导入 JSON'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加题目'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _SummaryCard(
            questionCount: _questions.length,
            pendingCount: _pendingCount,
            incompleteCount: _incompleteCount,
            onTapPending: _showPendingSubmissions,
            onTapIncomplete: _incompleteCount == 0 ? null : _showIncomplete,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ActionChip(
                avatar: const Icon(Icons.pending_actions_rounded, size: 18),
                label: Text('待审核投稿 $_pendingCount'),
                onPressed: _showPendingSubmissions,
              ),
              ActionChip(
                avatar: const Icon(Icons.category_outlined, size: 18),
                label: Text('批量分类（${_selectedIds.length}）'),
                onPressed: _selectedIds.isEmpty || _loading
                    ? null
                    : _bulkCategorize,
              ),
              ActionChip(
                avatar: const Icon(Icons.image_outlined, size: 18),
                label: Text('批量补图（${_selectedIds.length}）'),
                onPressed: _selectedIds.isEmpty || _loading
                    ? null
                    : _bulkSetImage,
              ),
              ActionChip(
                avatar: const Icon(Icons.rule_folder_outlined, size: 18),
                label: Text('待补全 $_incompleteCount'),
                onPressed: _incompleteCount == 0 ? null : _showIncomplete,
              ),
              ActionChip(
                avatar: const Icon(Icons.history_rounded, size: 18),
                label: Text('导入记录 $_importCount'),
                onPressed: _importCount == 0 ? null : _showImportHistory,
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    ),
              hintText: '搜索题干、答案、分类或标签',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in const [
                  ('all', '全部'),
                  ('published', '已发布'),
                  ('pending', '待审核'),
                  ('rejected', '已拒绝'),
                ]) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(entry.$2),
                      selected: _statusFilter == entry.$1,
                      onSelected: (_) =>
                          setState(() => _statusFilter = entry.$1),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null) _InlineError(message: _error!, onRetry: _load),
          if (questions.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 72),
              child: Center(
                child: Text(
                  _searchController.text.isEmpty && _statusFilter == 'all'
                      ? '暂无题目'
                      : '未找到匹配题目',
                ),
              ),
            )
          else
            ...questions.map(_questionCard),
        ],
      ),
    );
  }

  Future<void> _showPendingSubmissions() async {
    if (_loading) return;
    try {
      setState(() => _loading = true);
      final items = await widget.provider.fetchPending(
        widget.serverUrl,
        widget.token,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _pendingCount = items.length;
      });
      if (items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无待审核投稿')),
        );
        return;
      }
      final changed = await showDialog<bool>(
        context: context,
        builder: (context) => _PendingSubmissionsDialog(
          items: items,
          onReview: (id, action, {String reviewNote = ''}) async {
            return widget.provider.reviewSubmission(
              widget.serverUrl,
              widget.token,
              id,
              action,
              reviewNote: reviewNote,
            );
          },
          onReload: () async {
            return widget.provider.fetchPending(
              widget.serverUrl,
              widget.token,
            );
          },
        ),
      );
      if (changed == true && mounted) {
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('投稿审核已更新')),
          );
        }
      } else if (mounted) {
        // 即使未改动也刷新计数，避免摘要卡过期。
        await _load();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载待审核失败：$error')),
      );
    }
  }

  Future<void> _bulkCategorize() async {
    final controller = TextEditingController();
    final category = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('为 ${_selectedIds.length} 道题设置分类'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '分类名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (category == null || category.isEmpty) return;
    try {
      setState(() => _loading = true);
      await widget.provider.bulkSetCategory(
        widget.serverUrl,
        widget.token,
        _selectedIds.toList(),
        category,
      );
      if (!mounted) return;
      _selectedIds.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('题目分类已更新')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('分类失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _bulkSetImage() async {
    if (_selectedIds.isEmpty) return;
    final pick = await FilePicker.pickFiles(
      type: FileType.image,
    );
    if (pick == null || pick.files.isEmpty) return;
    final file = pick.files.first;
    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      bytes = Uint8List(0);
    }
    if (bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法读取图片数据')),
      );
      return;
    }
    final b64 = base64Encode(bytes);
    final ext = (file.extension ?? 'png').toLowerCase();
    final mime = ext == 'jpg' || ext == 'jpeg'
        ? 'image/jpeg'
        : ext == 'webp'
            ? 'image/webp'
            : 'image/png';
    final dataUrl = 'data:$mime;base64,$b64';
    try {
      setState(() => _loading = true);
      final url = await widget.provider.uploadQuizImage(
        widget.serverUrl,
        widget.token,
        dataUrl,
      );
      final result = await widget.provider.bulkUpdateQuestions(
        widget.serverUrl,
        widget.token,
        action: 'set_image',
        ids: _selectedIds.toList(),
        image: url,
      );
      if (!mounted) return;
      _selectedIds.clear();
      await _load();
      if (!mounted) return;
      final updated = result['updated'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('批量补图完成：更新 $updated 题')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('批量补图失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showIncomplete() async {
    final items = await widget.provider.fetchIncomplete(
      widget.serverUrl,
      widget.token,
    );
    if (!mounted) return;
    if (items.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂无待补全题目')));
      return;
    }
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _IncompleteQueueDialog(
        items: items,
        onComplete: (id, answer, category, analysis, imageData) async {
          String? imageUrl;
          if (imageData != null && imageData.isNotEmpty) {
            imageUrl = await widget.provider.uploadQuizImage(
              widget.serverUrl,
              widget.token,
              imageData,
            );
          }
          await widget.provider.completeIncomplete(
            widget.serverUrl,
            widget.token,
            id,
            answer,
            category: category,
            analysis: analysis,
            image: imageUrl,
          );
        },
        onBulk: (action, ids, category, {String correctAnswer = ''}) async {
          await widget.provider.bulkIncomplete(
            widget.serverUrl,
            widget.token,
            action: action,
            ids: ids,
            category: category,
            correctAnswer: correctAnswer,
          );
        },
        onReload: ({String filter = '', String query = ''}) async {
          return widget.provider.fetchIncomplete(
            widget.serverUrl,
            widget.token,
            filter: filter,
            query: query,
          );
        },
      ),
    );
    if (changed == true && mounted) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('待补全题目已更新')));
      }
    }
  }

  Future<void> _showImportHistory() async {
    final items = await widget.provider.fetchImports(
      widget.serverUrl,
      widget.token,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入记录'),
        content: SizedBox(
          width: 560,
          child: ListView(
            children: items
                .map(
                  (item) => ListTile(
                    title: Text(
                      '${item['importedAt'] ?? ''} · ${item['mode'] ?? ''}',
                    ),
                    subtitle: Text(
                      '总计 ${item['total'] ?? 0}，新增 ${item['inserted'] ?? 0}，重复 ${item['duplicateSkipped'] ?? 0}，无效 ${item['invalid'] ?? 0}',
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _importJson() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      final files = picked?.files ?? const <PlatformFile>[];
      if (files.length != 1) {
        return;
      }
      final bytes = await files.first.readAsBytes();
      if (bytes.isEmpty) {
        return;
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      final rawItems = decoded is Map
          ? (decoded['items'] ?? decoded['questions'] ?? decoded['data'])
          : decoded;
      if (rawItems is! List) throw const FormatException('文件中没有 items 题目数组。');
      final items = rawItems
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
      if (items.isEmpty) throw const FormatException('文件中没有可导入的题目。');
      if (!mounted) return;
      final publish = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入题库'),
          content: Text(
            '已读取 ${items.length} 道题。\n\n选择“直接发布”会立刻下发到用户同步；选择“待审核”仅保存到后台。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('导入待审核'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('直接发布'),
            ),
          ],
        ),
      );
      if (publish == null) return;
      setState(() => _loading = true);
      final preview = await widget.provider.importQuestions(
        widget.serverUrl,
        widget.token,
        items,
        dryRun: true,
        publish: publish,
      );
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入预览'),
          content: Text(
            '总计 ${preview.total} 道\n可导入 ${preview.inserted} 道\n重复跳过 ${preview.duplicateSkipped} 道\n格式/答案不完整 ${preview.invalid} 道\n\n确认执行导入？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认导入'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      final report = await widget.provider.importQuestions(
        widget.serverUrl,
        widget.token,
        items,
        publish: publish,
      );
      if (!mounted) return;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '导入完成：新增 ${report.inserted}，重复跳过 ${report.duplicateSkipped}，无效 ${report.invalid}',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导入失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _questionCard(QuizBankQuestion question) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: _selectedIds.contains(question.id),
                onChanged: question.id.isEmpty
                    ? null
                    : (selected) => setState(() {
                        if (selected == true) {
                          _selectedIds.add(question.id);
                        } else {
                          _selectedIds.remove(question.id);
                        }
                      }),
              ),
              Expanded(
                child: Text(
                  question.question.isEmpty ? '未命名题目' : question.question,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              _StatusChip(status: question.status),
              PopupMenuButton<String>(
                onSelected: (action) {
                  if (action == 'edit') {
                    _edit(question);
                  } else if (action == 'image') {
                    _editImage(question);
                  } else {
                    _delete(question);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'image', child: Text('补图/换图')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('删除', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ],
          ),
          if (question.options.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '选项：${question.options.join('  ·  ')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              Text(
                '答案：${question.answer.isEmpty ? '未设置' : question.answer}',
                style: const TextStyle(fontSize: 12),
              ),
              if (question.category.isNotEmpty)
                Chip(
                  label: Text(question.category),
                  visualDensity: VisualDensity.compact,
                  labelStyle: const TextStyle(fontSize: 11),
                ),
              if (question.image.isNotEmpty)
                const Chip(
                  avatar: Icon(Icons.image_outlined, size: 14),
                  label: Text('有图'),
                  visualDensity: VisualDensity.compact,
                  labelStyle: TextStyle(fontSize: 11),
                ),
              ...question.tags.map(
                (tag) => Chip(
                  label: Text(tag),
                  visualDensity: VisualDensity.compact,
                  labelStyle: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Future<void> _edit([QuizBankQuestion? question]) async {
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _QuestionEditor(initial: question),
    );
    if (data == null) return;
    try {
      final payload = Map<String, dynamic>.from(data);
      final imageData = payload.remove('imageData')?.toString();
      if (imageData != null && imageData.isNotEmpty) {
        final url = await widget.provider.uploadQuizImage(
          widget.serverUrl,
          widget.token,
          imageData,
        );
        if (url.isNotEmpty) payload['image'] = url;
      }
      if (question == null) {
        final created = await widget.provider.create(
          widget.serverUrl,
          widget.token,
          payload,
        );
        if (mounted) setState(() => _questions = [created, ..._questions]);
      } else {
        final updated = await widget.provider.update(
          widget.serverUrl,
          widget.token,
          question.id,
          payload,
        );
        if (mounted) {
          setState(
            () => _questions = _questions
                .map((item) => item.id == updated.id ? updated : item)
                .toList(growable: false),
          );
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(question == null ? '题目已添加' : '题目已更新')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _delete(QuizBankQuestion question) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除题目？'),
        content: Text(question.question),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.provider.delete(widget.serverUrl, widget.token, question.id);
      if (mounted) {
        setState(
          () => _questions = _questions
              .where((item) => item.id != question.id)
              .toList(growable: false),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _editImage(QuizBankQuestion question) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.image,
    );
    final file = picked?.files.isNotEmpty == true ? picked!.files.first : null;
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return;
    final ext = (file.extension ?? 'png').toLowerCase();
    final mime = switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/png',
    };
    final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
    try {
      setState(() => _loading = true);
      final url = await widget.provider.uploadQuizImage(
        widget.serverUrl,
        widget.token,
        dataUrl,
      );
      if (url.isEmpty) throw StateError('图片上传失败');
      final updated = await widget.provider.update(
        widget.serverUrl,
        widget.token,
        question.id,
        {
          'question': question.question,
          'options': question.options,
          'answer': question.answer,
          'correctAnswer': question.answer,
          'status': question.status,
          'tags': question.tags,
          'explanation': question.explanation,
          'analysis': question.explanation,
          'category': question.category,
          'type': question.type,
          'image': url,
        },
      );
      if (!mounted) return;
      setState(
        () => _questions = _questions
            .map((item) => item.id == updated.id ? updated : item)
            .toList(growable: false),
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('题目图片已更新')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('补图失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

