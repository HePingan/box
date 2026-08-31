part of 'quiz_bank_tab.dart';

class _QuestionEditor extends StatefulWidget {
  const _QuestionEditor({this.initial});
  final QuizBankQuestion? initial;
  @override
  State<_QuestionEditor> createState() => _QuestionEditorState();
}

class _QuestionEditorState extends State<_QuestionEditor> {
  late final TextEditingController _question = TextEditingController(
    text: widget.initial?.question ?? '',
  );
  late final TextEditingController _options = TextEditingController(
    text: widget.initial?.options.join('\n') ?? '',
  );
  late final TextEditingController _answer = TextEditingController(
    text: widget.initial?.answer ?? '',
  );
  late final TextEditingController _tags = TextEditingController(
    text: widget.initial?.tags.join(', ') ?? '',
  );
  late final TextEditingController _explanation = TextEditingController(
    text: widget.initial?.explanation ?? '',
  );
  late String _status = widget.initial?.status ?? 'draft';
  String? _imageDataUrl;
  String? _imageName;
  String _existingImage = '';

  @override
  void initState() {
    super.initState();
    _existingImage = widget.initial?.image ?? '';
  }

  @override
  void dispose() {
    _question.dispose();
    _options.dispose();
    _answer.dispose();
    _tags.dispose();
    _explanation.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
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
    if (!mounted) return;
    setState(() {
      _imageName = file.name;
      _imageDataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? '添加题目' : '编辑题目'),
    content: SingleChildScrollView(
      child: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _question,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '题干 *'),
            ),
            TextField(
              controller: _options,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '选项（每行一个）'),
            ),
            TextField(
              controller: _answer,
              decoration: const InputDecoration(labelText: '答案 *'),
            ),
            TextField(
              controller: _tags,
              decoration: const InputDecoration(labelText: '标签（逗号分隔）'),
            ),
            TextField(
              controller: _explanation,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '解析'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.image_outlined),
                  label: Text(
                    _imageName == null
                        ? (_existingImage.isEmpty ? '上传题目图片' : '更换图片')
                        : '已选图片',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _imageName ??
                        (_existingImage.isEmpty ? '未设置图片' : _existingImage),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
              ],
            ),
            DropdownButtonFormField(
              initialValue: _status,
              decoration: const InputDecoration(labelText: '状态'),
              items: const [
                DropdownMenuItem(value: 'draft', child: Text('草稿')),
                DropdownMenuItem(value: 'pending', child: Text('待审核')),
                DropdownMenuItem(value: 'published', child: Text('已发布')),
                DropdownMenuItem(value: 'rejected', child: Text('已拒绝')),
              ],
              onChanged: (value) => setState(() => _status = value ?? 'draft'),
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
        onPressed: () {
          if (_question.text.trim().isEmpty || _answer.text.trim().isEmpty) {
            return;
          }
          Navigator.pop(context, {
            'question': _question.text.trim(),
            'options': _options.text
                .split('\n')
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toList(),
            'answer': _answer.text.trim(),
            'correctAnswer': _answer.text.trim(),
            'tags': _tags.text
                .split(',')
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toList(),
            'explanation': _explanation.text.trim(),
            'analysis': _explanation.text.trim(),
            'status': _status,
            if (_imageDataUrl != null) 'imageData': _imageDataUrl,
            if (_imageDataUrl == null && _existingImage.isNotEmpty)
              'image': _existingImage,
          });
        },
        child: const Text('保存'),
      ),
    ],
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.questionCount,
    required this.pendingCount,
    this.incompleteCount = 0,
    this.onTapPending,
    this.onTapIncomplete,
  });

  final int questionCount;
  final int pendingCount;
  final int incompleteCount;
  final VoidCallback? onTapPending;
  final VoidCallback? onTapIncomplete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.quiz_rounded, color: Colors.indigo),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '题目 $questionCount',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SummaryAction(
                  icon: Icons.pending_actions_rounded,
                  label: '待审核投稿',
                  count: pendingCount,
                  color: Colors.orange,
                  onTap: onTapPending,
                ),
                _SummaryAction(
                  icon: Icons.rule_folder_outlined,
                  label: '待补全',
                  count: incompleteCount,
                  color: Colors.deepPurple,
                  onTap: onTapIncomplete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryAction extends StatelessWidget {
  const _SummaryAction({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final published = status == 'published' || status == 'active';
    final color = published
        ? Colors.green
        : status == 'pending'
        ? Colors.orange
        : status == 'rejected'
        ? Colors.red
        : Colors.grey;
    return Chip(
      label: Text(
        QuizBankQuestion(
          id: '',
          question: '',
          options: const [],
          answer: '',
          status: status,
          tags: const [],
        ).statusLabel,
      ),
      backgroundColor: color.withValues(alpha: .12),
      labelStyle: TextStyle(color: color, fontSize: 11),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 44),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Card(
    color: Colors.red.withValues(alpha: .06),
    child: ListTile(
      leading: const Icon(Icons.error_outline, color: Colors.red),
      title: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: TextButton(onPressed: onRetry, child: const Text('重试')),
    ),
  );
}

class _IncompleteQueueDialog extends StatefulWidget {
  const _IncompleteQueueDialog({
    required this.items,
    required this.onComplete,
    required this.onBulk,
    required this.onReload,
  });

  final List<Map<String, dynamic>> items;
  final Future<void> Function(
    String id,
    String answer,
    String category,
    String analysis,
    String? imageData,
  )
  onComplete;
  final Future<void> Function(
    String action,
    List<String> ids,
    String category, {
    String correctAnswer,
  })
  onBulk;
  final Future<List<Map<String, dynamic>>> Function({
    String filter,
    String query,
  })
  onReload;

  @override
  State<_IncompleteQueueDialog> createState() => _IncompleteQueueDialogState();
}

class _IncompleteQueueDialogState extends State<_IncompleteQueueDialog> {
  late List<Map<String, dynamic>> _items = List<Map<String, dynamic>>.from(
    widget.items,
  );
  final Set<String> _selected = <String>{};
  final TextEditingController _query = TextEditingController();
  String _filter = '';
  bool _busy = false;
  bool _changed = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _busy = true);
    try {
      final items = await widget.onReload(
        filter: _filter,
        query: _query.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _selected.removeWhere(
          (id) => !_items.any((item) => item['id']?.toString() == id),
        );
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('刷新失败：$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(Map<String, dynamic> item) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _IncompleteEditor(item: item),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.onComplete(
        result['id'].toString(),
        result['correctAnswer'].toString(),
        (result['category']?.toString() ?? '').trim(),
        (result['analysis']?.toString() ?? '').trim(),
        result['image']?.toString(),
      );
      if (!mounted) return;
      setState(() {
        _changed = true;
        _selected.remove(result['id'].toString());
        _items = _items
            .where(
              (entry) => entry['id']?.toString() != result['id'].toString(),
            )
            .toList(growable: false);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('题目已发布')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('发布失败：$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _bulkSetCategory() async {
    if (_selected.isEmpty) return;
    final controller = TextEditingController(text: '驾驶理论题库-20260719');
    final category = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('为 ${_selected.length} 条待补全设分类'),
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
    setState(() => _busy = true);
    try {
      await widget.onBulk('set_category', _selected.toList(), category);
      _changed = true;
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已设置分类：$category')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('批量分类失败：$error')));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _bulkPublish() async {
    if (_selected.isEmpty) return;
    final controller = TextEditingController();
    final answer = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('批量发布 ${_selected.length} 条'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '为选中待补全题填写统一正确答案后发布到正式库。\n'
              '已有答案/选项不合法的条目会跳过并保留在队列。',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '统一正确答案',
                hintText: '如 A / 正确 / 选项原文',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('发布'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (answer == null || answer.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.onBulk(
        'publish',
        _selected.toList(),
        '',
        correctAnswer: answer,
      );
      _changed = true;
      _selected.clear();
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('批量发布已提交，答案：$answer')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('批量发布失败：$error')),
      );
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _bulkDiscard() async {
    if (_selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('丢弃选中的待补全？'),
        content: Text('将从队列移除 ${_selected.length} 条，不会写入正式题库。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('丢弃'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await widget.onBulk('discard', _selected.toList(), '');
      _changed = true;
      _selected.clear();
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已丢弃选中项')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('丢弃失败：$error')));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('待补全题目（${_items.length}）'),
      content: SizedBox(
        width: 680,
        height: 480,
        child: Column(
          children: [
            TextField(
              controller: _query,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: '搜索题干/原因/分类',
                suffixIcon: IconButton(
                  onPressed: _busy ? null : _reload,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
              onSubmitted: (_) => _reload(),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  label: const Text('全部'),
                  selected: _filter.isEmpty,
                  onSelected: _busy
                      ? null
                      : (_) {
                          setState(() => _filter = '');
                          _reload();
                        },
                ),
                ChoiceChip(
                  label: const Text('缺答案'),
                  selected: _filter == 'missing_answer',
                  onSelected: _busy
                      ? null
                      : (_) {
                          setState(() => _filter = 'missing_answer');
                          _reload();
                        },
                ),
                ChoiceChip(
                  label: const Text('缺选项'),
                  selected: _filter == 'missing_options',
                  onSelected: _busy
                      ? null
                      : (_) {
                          setState(() => _filter = 'missing_options');
                          _reload();
                        },
                ),
                ActionChip(
                  label: Text('批量分类（${_selected.length}）'),
                  onPressed: _busy || _selected.isEmpty
                      ? null
                      : _bulkSetCategory,
                ),
                ActionChip(
                  label: Text('批量发布（${_selected.length}）'),
                  onPressed: _busy || _selected.isEmpty ? null : _bulkPublish,
                ),
                ActionChip(
                  label: Text('丢弃（${_selected.length}）'),
                  onPressed: _busy || _selected.isEmpty ? null : _bulkDiscard,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _items.isEmpty
                  ? const Center(child: Text('队列已清空或无匹配项'))
                  : ListView.separated(
                      itemCount: _items.length.clamp(0, 200),
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final id = item['id']?.toString() ?? '';
                        final question = (item['question']?.toString() ?? '')
                            .replaceAll(RegExp(r'\s+'), ' ')
                            .trim();
                        final options = (item['options'] as List? ?? const [])
                            .map((e) => e.toString())
                            .where((e) => e.isNotEmpty)
                            .toList();
                        final category = item['category']?.toString() ?? '';
                        final reason = item['reason']?.toString() ?? '';
                        final selected = _selected.contains(id);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Checkbox(
                                value: selected,
                                onChanged: id.isEmpty || _busy
                                    ? null
                                    : (value) => setState(() {
                                          if (value == true) {
                                            _selected.add(id);
                                          } else {
                                            _selected.remove(id);
                                          }
                                        }),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      question.isEmpty ? '（无题干）' : question,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        height: 1.35,
                                      ),
                                    ),
                                    if (reason.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        reason,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.orange.shade800,
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                    if (category.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        '分类：$category',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                    if (options.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        '选项：${options.join(' · ')}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: FilledButton(
                                        onPressed:
                                            _busy ? null : () => _edit(item),
                                        child: const Text('补全发布'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, _changed),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _IncompleteEditor extends StatefulWidget {
  const _IncompleteEditor({required this.item});
  final Map<String, dynamic> item;

  @override
  State<_IncompleteEditor> createState() => _IncompleteEditorState();
}

class _IncompleteEditorState extends State<_IncompleteEditor> {
  late final TextEditingController _answer = TextEditingController(
    text: widget.item['correctAnswer']?.toString() ?? '',
  );
  late final TextEditingController _category = TextEditingController(
    text: widget.item['category']?.toString() ?? '驾驶理论题库-20260719',
  );
  late final TextEditingController _analysis = TextEditingController(
    text: widget.item['analysis']?.toString() ?? '',
  );
  String? _imageDataUrl;
  String? _imageName;

  List<String> get _options => (widget.item['options'] as List? ?? const [])
      .map((e) => e.toString())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);

  @override
  void dispose() {
    _answer.dispose();
    _category.dispose();
    _analysis.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
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
    if (!mounted) return;
    setState(() {
      _imageName = file.name;
      _imageDataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.item['question']?.toString() ?? '';
    final reason = widget.item['reason']?.toString() ?? '';
    return AlertDialog(
      title: const Text('补全并发布'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                question,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (reason.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '原因：$reason',
                  style: const TextStyle(color: Colors.orange),
                ),
              ],
              if (_options.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  '选项：${_options.join('  ·  ')}',
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: _options
                      .map(
                        (opt) => ActionChip(
                          label: Text(opt),
                          onPressed: () => setState(() => _answer.text = opt),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _answer,
                decoration: const InputDecoration(labelText: '正确答案 *'),
              ),
              TextField(
                controller: _category,
                decoration: const InputDecoration(labelText: '分类'),
              ),
              TextField(
                controller: _analysis,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '解析（可选）'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(_imageName == null ? '上传题目图片' : '更换图片'),
                  ),
                  const SizedBox(width: 8),
                  if (_imageName != null)
                    Expanded(
                      child: Text(
                        _imageName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('跳过'),
        ),
        FilledButton(
          onPressed: () {
            final answer = _answer.text.trim();
            if (answer.isEmpty) return;
            Navigator.pop(context, {
              'id': widget.item['id']?.toString() ?? '',
              'correctAnswer': answer,
              'category': _category.text.trim(),
              'analysis': _analysis.text.trim(),
              if (_imageDataUrl != null) 'image': _imageDataUrl,
            });
          },
          child: const Text('发布'),
        ),
      ],
    );
  }
}


class _PendingSubmissionsDialog extends StatefulWidget {
  const _PendingSubmissionsDialog({
    required this.items,
    required this.onReview,
    required this.onReload,
  });

  final List<QuizBankSubmission> items;
  final Future<QuizBankSubmission> Function(
    String id,
    String action, {
    String reviewNote,
  }) onReview;
  final Future<List<QuizBankSubmission>> Function() onReload;

  @override
  State<_PendingSubmissionsDialog> createState() =>
      _PendingSubmissionsDialogState();
}

class _PendingSubmissionsDialogState extends State<_PendingSubmissionsDialog> {
  late List<QuizBankSubmission> _items;
  final Set<String> _selected = <String>{};
  final TextEditingController _query = TextEditingController();
  bool _busy = false;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _items = List<QuizBankSubmission>.from(widget.items);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<QuizBankSubmission> get _visible {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((item) {
      final question = item.question;
      return question.question.toLowerCase().contains(q) ||
          question.answer.toLowerCase().contains(q) ||
          question.category.toLowerCase().contains(q) ||
          (item.submitter ?? '').toLowerCase().contains(q) ||
          item.status.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  Future<void> _reload() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final items = await widget.onReload();
      if (!mounted) return;
      setState(() {
        _items = items;
        _selected.removeWhere((id) => !items.any((e) => e.id == id));
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _reviewOne(
    QuizBankSubmission item,
    String action, {
    String reviewNote = '',
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onReview(item.id, action, reviewNote: reviewNote);
      _changed = true;
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _bulkReview(String action) async {
    final ids = _selected.toList(growable: false);
    if (ids.isEmpty) return;
    String note = '';
    if (action == 'reject') {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('批量拒绝 ${ids.length} 条？'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: '拒绝原因（可选）',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('拒绝'),
            ),
          ],
        ),
      );
      note = controller.text.trim();
      controller.dispose();
      if (ok != true) return;
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('批量通过 ${ids.length} 条？'),
          content: const Text('通过后会写入正式题库并进入同步增量；若云端已有同题则标记为“云端已有”。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('通过'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    var okCount = 0;
    var failCount = 0;
    for (final id in ids) {
      try {
        await widget.onReview(id, action, reviewNote: note);
        okCount++;
        _changed = true;
      } catch (_) {
        failCount++;
      }
    }
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          action == 'approve'
              ? '批量通过：成功 $okCount · 失败 $failCount'
              : '批量拒绝：成功 $okCount · 失败 $failCount',
        ),
      ),
    );
  }

  Future<void> _rejectWithNote(QuizBankSubmission item) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('拒绝投稿'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '拒绝原因（可选）',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('拒绝'),
          ),
        ],
      ),
    );
    final note = controller.text.trim();
    controller.dispose();
    if (ok != true) return;
    await _reviewOne(item, 'reject', reviewNote: note);
  }

  String _formatTime(DateTime? at) {
    if (at == null) return '';
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final width = MediaQuery.sizeOf(context).width;
    return AlertDialog(
      title: Text('待审核投稿（${_items.length}）'),
      content: SizedBox(
        width: width < 720 ? width : 640,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: '搜索题干 / 答案 / 分类 / 投稿者',
                border: const OutlineInputBorder(),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _query.clear();
                          setState(() {});
                        },
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: _busy || visible.isEmpty
                      ? null
                      : () {
                          setState(() {
                            for (final item in visible) {
                              _selected.add(item.id);
                            }
                          });
                        },
                  child: const Text('全选当前'),
                ),
                TextButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => setState(_selected.clear),
                  child: const Text('清空选择'),
                ),
                FilledButton.tonal(
                  onPressed: _busy || _selected.isEmpty
                      ? null
                      : () => _bulkReview('approve'),
                  child: Text('批量通过（${_selected.length}）'),
                ),
                OutlinedButton(
                  onPressed: _busy || _selected.isEmpty
                      ? null
                      : () => _bulkReview('reject'),
                  child: Text('批量拒绝（${_selected.length}）'),
                ),
              ],
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                ),
              ),
            const SizedBox(height: 6),
            Expanded(
              child: visible.isEmpty
                  ? const Center(child: Text('暂无待审核投稿'))
                  : ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final item = visible[i];
                        final q = item.question;
                        final selected = _selected.contains(item.id);
                        final stem = q.question
                            .replaceAll(RegExp(r'\s+'), ' ')
                            .trim();
                        final options = q.options
                            .map((e) => e.trim())
                            .where((e) => e.isNotEmpty)
                            .toList();
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Checkbox(
                                value: selected,
                                onChanged: _busy
                                    ? null
                                    : (v) {
                                        setState(() {
                                          if (v == true) {
                                            _selected.add(item.id);
                                          } else {
                                            _selected.remove(item.id);
                                          }
                                        });
                                      },
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      stem.isEmpty ? '（无题干）' : stem,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      [
                                        item.statusLabel,
                                        if ((item.submitter ?? '')
                                            .trim()
                                            .isNotEmpty)
                                          '投稿者 ${item.submitter}',
                                        if (_formatTime(item.submittedAt)
                                            .isNotEmpty)
                                          _formatTime(item.submittedAt),
                                        if (q.category.trim().isNotEmpty)
                                          '分类 ${q.category}',
                                      ].join(' · '),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    if (options.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        '选项：${options.join(' · ')}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Text(
                                      '答案：${q.answer.isEmpty ? "（空）" : q.answer}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.green.shade700,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (q.explanation.trim().isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        '解析：${q.explanation}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Wrap(
                                        spacing: 6,
                                        children: [
                                          OutlinedButton(
                                            onPressed: _busy
                                                ? null
                                                : () => _rejectWithNote(item),
                                            child: const Text('拒绝'),
                                          ),
                                          FilledButton(
                                            onPressed: _busy
                                                ? null
                                                : () => _reviewOne(
                                                      item,
                                                      'approve',
                                                    ),
                                            child: const Text('通过发布'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _reload,
          child: const Text('刷新'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _changed),
          child: const Text('完成'),
        ),
      ],
    );
  }
}
