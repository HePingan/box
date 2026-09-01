import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/quiz_bank_admin_client.dart';
import '../../domain/admin_resource.dart';
import '../../domain/admin_resource_provider.dart';
import '../../domain/quiz_bank_import_report.dart';
import '../../domain/quiz_bank_filter.dart';
import '../../domain/quiz_bank_models.dart';
import '../../domain/quiz_thumb_image_source.dart';

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
  late QuizBankFilter _filter = QuizBankFilter(base: widget.serverUrl);

  /// 当前展开看全文的题目 id（一次只展开一条，列表默认保持矮身）
  String? _expandedId;

  /// 搜索框默认收起，点放大镜才占一行
  bool _searchOpen = false;

  /// 多选模式：长按题目进入，退出时清空已选
  bool _selectionMode = false;

  void _toggleSelect(String id) {
    if (id.isEmpty) return;
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  void _exitSelection() => setState(() {
    _selectionMode = false;
    _selectedIds.clear();
  });

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

  /// 首屏统一走 QuizBankFilter：状态/图片/题型/搜索四个维度一处判定，
  /// 弹层选完写回 _filter 即刻生效，chip 与列表不会各说一套。
  QuizBankFilter get _effectiveFilter =>
      _filter.copyWith(query: _searchController.text);

  List<QuizBankQuestion> get _visibleQuestions =>
      _effectiveFilter.apply(_questions);

  @override
  Widget build(BuildContext context) {
    if (_loading && _questions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _questions.isEmpty) {
      return _ErrorState(message: _error!, onRetry: _load);
    }
    final questions = _visibleQuestions;
    final activeFilter = _effectiveFilter;
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  const Text(
                    '题库管理',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: _searchOpen ? '收起搜索' : '搜索题目',
                    onPressed: () => setState(() {
                      _searchOpen = !_searchOpen;
                      if (!_searchOpen) _searchController.clear();
                    }),
                    icon: Icon(
                      _searchOpen ? Icons.search_off_rounded : Icons.search_rounded,
                    ),
                  ),
                  IconButton(
                    tooltip: '添加题目',
                    onPressed: () => _edit(),
                    icon: const Icon(Icons.add_circle_rounded),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '更多操作',
                    onSelected: (value) {
                      switch (value) {
                        case 'refresh':
                          _load();
                        case 'import':
                          _importJson();
                        case 'history':
                          _showImportHistory();
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'refresh',
                        child: Text('刷新'),
                      ),
                      const PopupMenuItem(
                        value: 'import',
                        child: Text('导入 JSON'),
                      ),
                      PopupMenuItem(
                        value: 'history',
                        child: Text('导入记录（$_importCount）'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_searchOpen)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                    hintText: '搜索题干、答案、分类、标签',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
          if (_selectionMode && _selectedIds.isNotEmpty) SliverToBoxAdapter(
            child: _SelectionBar(
              selectedCount: _selectedIds.length,
              onClear: _exitSelection,
              onBulkCategorize: _bulkCategorize,
              onBulkImage: _bulkSetImage,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _CompactSummaryBar(
                questionCount: _questions.length,
                pendingCount: _pendingCount,
                incompleteCount: _incompleteCount,
                onTapPending: _showPendingSubmissions,
                onTapIncomplete: _incompleteCount == 0 ? null : _showIncomplete,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _showFilterDialog,
                    icon: const Icon(Icons.filter_list_rounded, size: 18),
                    label: Text(
                      activeFilter.activeCount == 0
                          ? '筛选'
                          : '筛选 · ${activeFilter.activeCount}',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: activeFilter.activeCount == 0
                        ? Text(
                            '共 ${questions.length} 题',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          )
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final label in activeFilter.activeLabels)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Chip(
                                      visualDensity: VisualDensity.compact,
                                      avatar: Icon(
                                        _dimensionIcon(label.dimension),
                                        size: 14,
                                      ),
                                      label: Text(
                                        label.text,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      onDeleted: () =>
                                          _clearDimension(label.dimension),
                                    ),
                                  ),
                                Text(
                                  '${questions.length} 题',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => setState(() {
                                    _filter = _filter.clearAll();
                                    _searchController.clear();
                                    _searchOpen = false;
                                  }),
                                  child: const Text('清除'),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          if (_error != null && questions.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _InlineError(message: _error!, onRetry: _load),
              ),
            ),
          if (questions.isEmpty && _error == null)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 72),
                child: Center(child: Text('暂无题目')),
              ),
            ),
          if (questions.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final question = questions[i];
                  return _QuestionCard(
                    question: question,
                    serverUrl: widget.serverUrl,
                    expanded: _expandedId == question.id,
                    selectionMode: _selectionMode,
                    isSelected: _selectedIds.contains(question.id),
                    onToggleExpand: () => setState(
                      () => _expandedId =
                          _expandedId == question.id ? null : question.id,
                    ),
                    onToggleSelect: () => _toggleSelect(question.id),
                    onEnterSelection: () => setState(() {
                      _selectionMode = true;
                      if (question.id.isNotEmpty) {
                        _selectedIds.add(question.id);
                      }
                    }),
                    onEdit: () => _edit(question),
                    onEditImage: () => _editImage(question),
                    onDelete: () => _delete(question),
                  );
                },
                childCount: questions.length,
              ),
            ),
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
      // 批量操作收尾必须连 _selectionMode 一起退出：
      // 只 clear() 会留在多选态，卡片仍显示勾选框、点一下变选中而不是展开，
      // 而操作条因为「已选为空」不显示，用户没有出口。
      _exitSelection();
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
      _exitSelection();
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

  Future<void> _showFilterDialog() async {
    final picked = await showModalBottomSheet<QuizBankFilter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FilterDialog(
        initial: _filter,
        counts: QuizBankFilter.imageCounts(
          _questions,
          base: widget.serverUrl,
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _filter = picked);
  }

  void _clearDimension(QuizFilterDimension dimension) {
    setState(() {
      if (dimension == QuizFilterDimension.query) {
        _searchController.clear();
        _searchOpen = false;
      }
      _filter = _filter.without(dimension);
    });
  }

  IconData _dimensionIcon(QuizFilterDimension d) => switch (d) {
    QuizFilterDimension.status => Icons.filter_list_rounded,
    QuizFilterDimension.image => Icons.image_rounded,
    QuizFilterDimension.type => Icons.category_rounded,
    QuizFilterDimension.query => Icons.search_rounded,
  };
}

