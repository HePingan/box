part of 'quiz_bank_tab.dart';


/// 新版题库编辑器：全屏页面，带实时预览。
///
/// 相比旧弹窗版的主要改进：
///  - 题型切换自动填选项（判断题 → 正确/错误，单选 → 占4个空位）
///  - 答案改成点选项指定，不再手打（消除字母形越界答案 3 道 / 多字母 4 道）
///  - 选项可增删，每行独立编辑
///  - 图片有缩略图预览 + 换图/删图
///  - 右侧实时预览，窄屏折叠成可展开面板
///  - 去掉库里 0 使用的标签字段，状态栏改小
class _QuestionEditor extends StatefulWidget {
  const _QuestionEditor({this.initial});
  final QuizBankQuestion? initial;

  @override
  State<_QuestionEditor> createState() => _QuestionEditorState();
}

class _QuestionEditorState extends State<_QuestionEditor> {
  late _QuestionDraft _d;
  final _qCtrl = TextEditingController();
  final _optCtrls = <TextEditingController>[];
  final _ansCtrl = TextEditingController();
  final _expCtrl = TextEditingController();
  final _catCtrl = TextEditingController();
  String? _imageDataUrl;
  bool _previewOpen = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _d = _QuestionDraft(
      id: init?.id,
      question: init?.question ?? '',
      type: init?.type ?? 'single_choice',
      options: List<String>.from(init?.options ?? ['A', 'B', 'C', 'D']),
      answer: _extractAnswerList(init),
      explanation: init?.explanation ?? '',
      category: init?.category ?? '',
      status: init?.status ?? 'published',
      image: init?.image ?? '',
    );
    _qCtrl.text = _d.question;
    for (var i = 0; i < _d.options.length; i++) {
      _optCtrls.add(TextEditingController(text: _d.options[i]));
    }
    _ansCtrl.text = _d.answer.join(', ');
    _expCtrl.text = _d.explanation;
    _catCtrl.text = _d.category;
    _checkLetterWarning();
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    for (final c in _optCtrls) {
      c.dispose();
    }
    _ansCtrl.dispose();
    _expCtrl.dispose();
    _catCtrl.dispose();
    super.dispose();
  }

  List<String> _extractAnswerList(QuizBankQuestion? q) {
    if (q == null) return const [];
    final raw = (q.answer).trim();
    if (raw.isEmpty) return const [];
    final normalized = raw.toUpperCase().replaceAll('，', ',').replaceAll('、', ',').replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty) return const [];
    for (final o in q.options) {
      if (o.trim().toUpperCase() == normalized) return [o];
    }
    final parts = normalized.split(',').where((s) => s.isNotEmpty).toList();
    if (parts.length > 1) return parts.map((p) => p.trim()).toList();
    if (parts.isEmpty) return const [];
    final idx = _letterIndex(parts.first);
    if (idx >= 0 && idx < q.options.length) return [q.options[idx]];
    return [raw];
  }

  int _letterIndex(String letter) {
    final ch = letter.toUpperCase().codeUnitAt(0);
    if (ch < 65 || ch > 90) return -1;
    return ch - 65;
  }

  void _checkLetterWarning() {
    _d.letterAnswerWarning = null;
    final raw = _ansCtrl.text.trim();
    if (raw.isEmpty) return;
    final letter = RegExp(r'^[A-Ha-h]{1,4}$').firstMatch(raw);
    if (letter == null) return;
    final parts = raw.toUpperCase().split('');
    for (final p in parts) {
      final idx = _letterIndex(p);
      if (idx < 0 || idx >= _d.options.length) {
        _d.letterAnswerWarning =
            '字母 "$p" 超出选项范围（共 ${_d.options.length} 个，索引 0–${_d.options.length - 1}）';
        return;
      }
    }
  }

  void _setType(String t) {
    setState(() {
      _d.type = t;
      if (t == 'true_false') {
        _d.options = ['正确', '错误'];
        _d.answer = ['正确'];
        _ansCtrl.text = '正确';
      } else if (t == 'single_choice' || t == 'multiple_choice') {
        if (_d.options.length < 4) {
          _d.options = List.filled(4, '');
          _d.answer = [];
          _ansCtrl.text = '';
        }
      }
      while (_optCtrls.length > _d.options.length) {
        _optCtrls.removeLast().dispose();
      }
      while (_optCtrls.length < _d.options.length) {
        _optCtrls.add(TextEditingController());
      }
      for (var i = 0; i < _d.options.length; i++) {
        _optCtrls[i].text = _d.options[i];
      }
      _checkLetterWarning();
    });
  }

  void _addOption() {
    setState(() {
      _d.options.add('');
      _optCtrls.add(TextEditingController());
    });
  }

  void _removeOption(int idx) {
    if (_d.options.length <= 2) return;
    final removed = _d.options[idx];
    setState(() {
      _optCtrls[idx].dispose();
      _optCtrls.removeAt(idx);
      _d.options.removeAt(idx);
      _d.answer = _d.answer.where((a) => a != removed).toList();
      _ansCtrl.text = _d.answer.join(', ');
      _checkLetterWarning();
    });
  }

  void _onOptionChanged(int idx, String v) {
    setState(() {
      _d.options[idx] = v;
      _d.answer = _d.answer.map((a) {
        for (var i = 0; i < _d.options.length; i++) {
          if (_d.options[i].trim() == a.trim()) return v;
        }
        return a;
      }).toList();
      _ansCtrl.text = _d.answer.join(', ');
      _checkLetterWarning();
    });
  }

  void _toggleAnswer(int idx) {
    setState(() {
      final opt = _d.options[idx];
      if (_d.answer.contains(opt)) {
        _d.answer.remove(opt);
      } else {
        if (!_d.isMultiple) {
          _d.answer = [opt];
        } else {
          _d.answer.add(opt);
        }
      }
      _ansCtrl.text = _d.answer.join(', ');
      _checkLetterWarning();
    });
  }

  Future<void> _pickImage() async {
    final picked = await FilePicker.pickFiles(type: FileType.image);
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
      _imageDataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
    });
  }

  void _clearImage() {
    setState(() {
      _imageDataUrl = null;
    });
  }

  Future<void> _save() async {
    if (_qCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('题干不能为空')),
      );
      return;
    }
    if (_d.answer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选定答案')),
      );
      return;
    }
    _d.question = _qCtrl.text.trim();
    _d.options = _optCtrls.map((c) => c.text.trim()).toList();
    _d.explanation = _expCtrl.text.trim();
    _d.category = _catCtrl.text.trim();

    final onData = widget.initial == null ? '添加' : '更新';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DiffConfirmDialog(
        draft: _d,
        action: onData,
        quiz: widget.initial,
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        'question': _d.question,
        'options': _d.options,
        'correctAnswer': _d.answer.join(','),
        'answer': _d.answer.join(','),
        'type': _d.type,
        'explanation': _d.explanation,
        'analysis': _d.explanation,
        'status': _d.status,
        'category': _d.category,
      };
      if (_imageDataUrl != null) {
        payload['imageData'] = _imageDataUrl;
      } else if (_d.image.isNotEmpty) {
        payload['image'] = _d.image;
      }
      if (!mounted) return;
      Navigator.pop(context, payload);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? '添加题目' : '编辑题目'),
        actions: [
          if (_d.letterAnswerWarning != null)
            IconButton(
              icon: const Icon(Icons.warning_amber, color: Colors.amber),
              tooltip: _d.letterAnswerWarning,
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_d.letterAnswerWarning!),
                    duration: const Duration(seconds: 5),
                  ),
                );
              },
            ),
          if (isWide)
            IconButton(
              icon: Icon(_previewOpen ? Icons.visibility_off : Icons.visibility),
              tooltip: _previewOpen ? '隐藏预览' : '显示预览',
              onPressed: () => setState(() => _previewOpen = !_previewOpen),
            ),
        ],
        // 题型和状态各占一行：6 个控件挤一行在 360/320 宽下会横向溢出
        // （实测溢出 96px / 120px）。每行内部再套横向滚动，
        // 保证任何窄屏都能滑到最后一个入口，不被裁掉。
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _barRow(
                label: '题型',
                children: [
                  _typeChip('单选', 'single_choice'),
                  const SizedBox(width: 8),
                  _typeChip('多选', 'multiple_choice'),
                  const SizedBox(width: 8),
                  _typeChip('判断', 'true_false'),
                ],
              ),
              _barRow(label: '状态', children: _statusChips()),
            ],
          ),
        ),
      ),
      body: isWide
          ? Row(
              children: [
                Expanded(flex: 3, child: _buildEditor()),
                if (_previewOpen) Expanded(flex: 2, child: _buildPreview()),
              ],
            )
          : Column(
              children: [
                Expanded(child: _buildEditor()),
                _previewToggleBar(),
                if (_previewOpen) _buildPreview(),
              ],
            ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _typeChip(String label, String type) {
    final selected = _d.type == type;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _setType(type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  /// 顶部一行：左侧固定小标题，右侧内容横向可滚动。
  ///
  /// 用 SingleChildScrollView 而不是 Wrap：AppBar.bottom 高度是写死的，
  /// Wrap 换行会把第二行顶出可视区（等于还是显示不全），滚动则始终能摸到。
  Widget _barRow({required String label, required List<Widget> children}) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: 12),
          SizedBox(
            width: 34,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 12),
              child: Row(children: children),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _statusChips() {
    const statuses = [
      ('草稿', 'draft'),
      ('待审核', 'pending'),
      ('已发布', 'published'),
    ];
    final out = <Widget>[];
    for (final (label, val) in statuses) {
      if (out.isNotEmpty) out.add(const SizedBox(width: 8));
      final active = _d.status == val;
      out.add(
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _d.status = val),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: active
                  ? _statusStyle(val).color.withValues(alpha: 0.18)
                  : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: active ? _statusStyle(val).color : Colors.transparent,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: active ? _statusStyle(val).color : Colors.black87,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      );
    }
    return out;
  }

  Widget _buildEditor() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(label: '题干 *', hint: '输入题目内容', ctrl: _qCtrl, maxLines: 3),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('选项 *', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(width: 8),
              Text(
                '${_d.options.length} 个',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _addOption,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('添加'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ..._d.options.asMap().entries.map((e) {
            final idx = e.key;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      String.fromCharCode(65 + idx),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _optCtrls[idx],
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => _onOptionChanged(idx, v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_d.options.length > 2)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      color: Colors.grey.shade600,
                      onPressed: () => _removeOption(idx),
                    ),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),
          _field(
              label: '答案 *', hint: '点击选项即可选择', ctrl: _ansCtrl, readOnly: true),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _d.options.asMap().entries.map((e) {
              final idx = e.key;
              final opt = e.value;
              final selected = _d.answer.contains(opt);
              return FilterChip(
                label: Text(
                  '${String.fromCharCode(65 + idx)}. $opt',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                selected: selected,
                onSelected: (_) => _toggleAnswer(idx),
                avatar: selected
                    ? const Icon(Icons.check, size: 16)
                    : null,
              );
            }).toList(),
          ),
          if (_d.letterAnswerWarning != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _d.letterAnswerWarning!,
                      style: const TextStyle(color: Colors.amberAccent),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      final parts = _ansCtrl.text.trim().toUpperCase().split('');
                      final opts = parts
                          .map((p) => _d.options[_letterIndex(p)])
                          .where((o) => o.isNotEmpty)
                          .toList();
                      if (opts.isNotEmpty) {
                        setState(() {
                          _d.answer = opts;
                          _ansCtrl.text = opts.join(', ');
                          _d.letterAnswerWarning = null;
                        });
                      }
                    },
                    child: const Text('一键修复'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _imageSection(),
          const SizedBox(height: 16),
          _field(
              label: '解析', hint: '选填，题目解析', ctrl: _expCtrl, maxLines: 4),
          const SizedBox(height: 12),
          _field(label: '分类', hint: '选填', ctrl: _catCtrl),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _field(
      {required String label,
      required String hint,
      required TextEditingController ctrl,
      int maxLines = 1,
      bool readOnly = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          maxLines: maxLines > 1 ? maxLines : null,
          readOnly: readOnly,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding:
                EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  Widget _imageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('题目图片', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        if (_imageDataUrl != null || _d.image.isNotEmpty) ...[
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _imageDataUrl != null
                ? Image.memory(
                    base64Decode(
                        _imageDataUrl!.replaceAll('data:image/*;base64,', '')),
                    fit: BoxFit.cover,
                  )
                : NetworkImageOrPlaceholder(_d.image),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.photo_camera, size: 16),
                label:
                    Text(_imageDataUrl != null ? '更换图片' : '添加图片'),
              ),
              const SizedBox(width: 8),
              if (_imageDataUrl != null || _d.image.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: _clearImage,
                  icon: const Icon(Icons.delete, size: 16),
                  label: const Text('删除'),
                ),
            ],
          ),
        ] else ...[
          OutlinedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.add_photo_alternate, size: 16),
            label: const Text('添加题目图片'),
          ),
          const SizedBox(height: 4),
          Text(
            '支持 JPG / PNG / WebP，最大 10MB',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _previewToggleBar() {
    return InkWell(
      onTap: () => setState(() => _previewOpen = !_previewOpen),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: Colors.grey.shade100,
        child: Row(
          children: [
            Icon(
              _previewOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: Colors.grey.shade600,
            ),
            const SizedBox(width: 8),
            Text(
              _previewOpen ? '收起预览' : '展开预览',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _typeBadge(_d.type),
                    const SizedBox(width: 8),
                    _statusBadge(_d.status),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _d.question.isEmpty ? '（题干为空）' : _d.question,
                  style: const TextStyle(fontSize: 16, height: 1.4),
                ),
                if (_d.image.isNotEmpty || _imageDataUrl != null) ...[
                  const SizedBox(height: 12),
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _imageDataUrl != null
                        ? Image.memory(
                            base64Decode(
                                _imageDataUrl!
                                    .replaceAll('data:image/*;base64,', '')),
                            fit: BoxFit.cover,
                          )
                        : NetworkImageOrPlaceholder(_d.image),
                  ),
                ],
                const SizedBox(height: 12),
                ..._d.options.asMap().entries.map((e) {
                  final idx = e.key;
                  final opt = e.value;
                  final selected = _d.answer.contains(opt);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey.shade300,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              String.fromCharCode(65 + idx),
                              style: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : Colors.black87,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            opt.isEmpty ? '（空选项）' : opt,
                            style: TextStyle(
                              decoration:
                                  selected ? TextDecoration.underline : null,
                              fontWeight:
                                  selected ? FontWeight.bold : null,
                            ),
                          ),
                        ),
                        if (selected)
                          const Icon(Icons.check,
                              color: Colors.green, size: 20),
                      ],
                    ),
                  );
                }),
                if (_d.explanation.isNotEmpty) ...[
                  const Divider(),
                  const Text(
                    '解析',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _d.explanation,
                    style: const TextStyle(fontSize: 14, height: 1.5),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _typeBadge(String type) {
    final style = _typeStyle(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(style.label,
          style: TextStyle(color: style.color, fontSize: 12)),
    );
  }

  Widget _statusBadge(String status) {
    final style = _statusStyle(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(style.label,
          style: TextStyle(color: style.color, fontSize: 12)),
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(color: Colors.white),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _d.question.isEmpty
                    ? '题干不能为空'
                    : '${_d.answer.length} 个答案',
                style: TextStyle(
                  color: _d.question.isEmpty || _d.answer.isEmpty
                      ? Colors.red.shade600
                      : Colors.grey.shade600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionDraft {
  _QuestionDraft({
    this.id,
    this.question = '',
    this.type = 'single_choice',
    this.options = const [],
    this.answer = const [],
    this.explanation = '',
    this.category = '',
    this.status = 'published',
    this.image = '',
  });
  String? id;
  String question;
  String type;
  List<String> options;
  List<String> answer;
  String explanation;
  String category;
  String status;
  String image;
  bool get isTrueFalse => type == 'true_false';
  bool get isMultiple => type == 'multiple_choice';
  String? letterAnswerWarning;
}

class _DiffConfirmDialog extends StatelessWidget {
  const _DiffConfirmDialog(
      {required this.draft, required this.action, required this.quiz});
  final _QuestionDraft draft;
  final String action;
  final QuizBankQuestion? quiz;

  @override
  Widget build(BuildContext context) {
    final hasChanges = quiz != null && (quiz!.question != draft.question ||
        quiz!.options.length != draft.options.length ||
        quiz!.answer != draft.answer.join(',') ||
        quiz!.explanation != draft.explanation ||
        quiz!.status != draft.status ||
        quiz!.image != draft.image);
    if (!hasChanges) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pop(context, true);
      });
      return const SizedBox.shrink();
    }
    return AlertDialog(
      title: Text('$action前确认'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _diffRow('题干', quiz?.question, draft.question),
            const SizedBox(height: 8),
            _diffRow('答案', quiz?.answer, draft.answer.join(',')),
            const SizedBox(height: 8),
            _diffRow('解析', quiz?.explanation, draft.explanation),
            const SizedBox(height: 8),
            _diffRow('状态', quiz?.status, draft.status),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('确认保存'),
        ),
      ],
    );
  }

  Widget _diffRow(String label, String? old, String? now) {
    final same = old == now;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Text(label,
              style: const TextStyle(color: Colors.grey)),
        ),
        Expanded(
          child: Text(
            '$now',
            style: TextStyle(
              color: same ? Colors.grey : Colors.black,
              decoration: same ? null : TextDecoration.underline,
            ),
          ),
        ),
        if (!same)
          const Icon(Icons.edit, size: 14, color: Colors.blue),
      ],
    );
  }
}

/// 状态色板：列表、弹层、汇总共用一套，避免同一状态在三处三个颜色。
({Color color, String label}) _statusStyle(String status) => switch (status) {
  'published' || 'active' => (color: const Color(0xFF10B981), label: '已发布'),
  'pending' || 'pending_review' => (color: const Color(0xFFF59E0B), label: '待审核'),
  'rejected' => (color: const Color(0xFFEF4444), label: '已拒绝'),
  'draft' => (color: const Color(0xFF94A3B8), label: '草稿'),
  _ => (color: const Color(0xFF94A3B8), label: status.isEmpty ? '未知' : status),
};

/// 题型标签：服务端存的是 single/multi/judge 这类裸串，直接摆到卡片上很生硬。
({Color color, String label, String short}) _typeStyle(String type) =>
    switch (type.toLowerCase()) {
      'single' || 'choice' || 'single_choice' => (
        color: const Color(0xFF3B82F6),
        label: '单选',
        short: '单',
      ),
      'multi' || 'multiple' || 'multi_choice' => (
        color: const Color(0xFF8B5CF6),
        label: '多选',
        short: '多',
      ),
      'judge' || 'boolean' || 'tf' || 'true_false' => (
        color: const Color(0xFF06B6D4),
        label: '判断',
        short: '判',
      ),
      'sort' || 'order' => (color: const Color(0xFFF97316), label: '排序', short: '序'),
      'fill' || 'blank' => (color: const Color(0xFF14B8A6), label: '填空', short: '填'),
      _ => (
        color: const Color(0xFF94A3B8),
        label: type.isEmpty ? '未分类' : type,
        short: '题',
      ),
    };

/// 扁平小标签。Chip 自带 padding 太肥，一行挤三个就换行了，这里手搓。
class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.text, required this.color, this.icon});

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              height: 1.2,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final s = _statusStyle(status);
    return _MiniTag(text: s.label, color: s.color);
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type});
  final String type;
  @override
  Widget build(BuildContext context) {
    final t = _typeStyle(type);
    return _MiniTag(text: t.label, color: t.color);
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

// ============================================================
// 首界面重构 v10：新组件
// ============================================================

/// 三格汇总条：总题 / 待审 / 残缺，横向 Row 三等分。
class _CompactSummaryBar extends StatelessWidget {
  const _CompactSummaryBar({
    required this.questionCount,
    required this.pendingCount,
    required this.incompleteCount,
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
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withValues(alpha: .4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryCell(
              label: '总题',
              value: questionCount,
              icon: Icons.inventory_2_outlined,
              onTap: null,
            ),
          ),
          _cellDivider(theme),
          Expanded(
            child: _SummaryCell(
              label: '待审',
              value: pendingCount,
              icon: Icons.pending_actions_rounded,
              color: const Color(0xFFF59E0B),
              onTap: onTapPending,
            ),
          ),
          _cellDivider(theme),
          Expanded(
            child: _SummaryCell(
              label: '残缺',
              value: incompleteCount,
              icon: Icons.report_gmailerrorred_rounded,
              color: const Color(0xFFEF4444),
              onTap: onTapIncomplete,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cellDivider(ThemeData theme) => Container(
    width: 1,
    height: 28,
    color: theme.dividerColor.withValues(alpha: .4),
  );
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({
    required this.label,
    required this.value,
    this.icon,
    this.color,
    this.onTap,
  });

  final String label;
  final int value;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 计数为 0 时不该用警示色喊人，褪成灰
    final live = value > 0;
    final tint = live ? (color ?? theme.colorScheme.primary) : theme.hintColor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 14, color: tint),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    '$value',
                    style: TextStyle(
                      fontSize: 19,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      color: tint,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.hintColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 筛选底部弹层。
class _FilterDialog extends StatefulWidget {
  const _FilterDialog({
    required this.initial,
    required this.counts,
  });

  final QuizBankFilter initial;
  final Map<QuizImageFilter, int> counts;

  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  late QuizBankFilter _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initial;
  }

  void _setStatus(QuizStatusFilter v) {
    setState(() => _current = _current.copyWith(status: v));
  }

  void _setImage(QuizImageFilter v) {
    setState(() => _current = _current.copyWith(image: v));
  }

  void _setType(QuizTypeFilter v) {
    setState(() => _current = _current.copyWith(type: v));
  }

  @override
  Widget build(BuildContext context) {
    final counts = widget.counts;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '筛选',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            _FilterGroup(
              title: '状态',
              dimension: QuizFilterDimension.status,
              initial: _current,
              selected: _current.status,
              onSelected: _setStatus,
              options: const [
                QuizFilterOption(QuizStatusFilter.any, '全部'),
                QuizFilterOption(QuizStatusFilter.pending, '待审核'),
                QuizFilterOption(QuizStatusFilter.approved, '已通过'),
                QuizFilterOption(QuizStatusFilter.rejected, '已驳回'),
              ],
            ),
            const SizedBox(height: 16),
            _FilterGroup(
              title: '图片',
              dimension: QuizFilterDimension.image,
              initial: _current,
              selected: _current.image,
              onSelected: _setImage,
              options: [
                const QuizFilterOption(QuizImageFilter.any, '全部'),
                QuizFilterOption(QuizImageFilter.withImage, '有图 (${counts[QuizImageFilter.withImage]})'),
                QuizFilterOption(QuizImageFilter.withoutImage, '无图 (${counts[QuizImageFilter.withoutImage]})'),
              ],
            ),
            const SizedBox(height: 16),
            _FilterGroup(
              title: '题型',
              dimension: QuizFilterDimension.type,
              initial: _current,
              selected: _current.type,
              onSelected: _setType,
              options: const [
                QuizFilterOption(QuizTypeFilter.any, '全部题型'),
                QuizFilterOption(QuizTypeFilter.judge, '判断题'),
                QuizFilterOption(QuizTypeFilter.single, '单选题'),
                QuizFilterOption(QuizTypeFilter.multi, '多选题'),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _current),
                    child: const Text('应用'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterGroup<T extends Enum> extends StatelessWidget {
  const _FilterGroup({
    required this.title,
    required this.dimension,
    required this.initial,
    required this.selected,
    required this.onSelected,
    required this.options,
  });

  final String title;
  final QuizFilterDimension dimension;
  final QuizBankFilter initial;
  final T selected;
  final void Function(T) onSelected;
  final List<QuizFilterOption> options;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: options.map((opt) {
            final active = opt.value == selected;
            return FilterChip(
              label: Text(opt.label),
              selected: active,
              onSelected: (v) => onSelected(opt.value as T),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class QuizFilterOption {
  const QuizFilterOption(this.value, this.label);
  final dynamic value;
  final String label;
}

/// 题目列表卡片，支持展开看全文、长按进多选、操作走菜单。
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.serverUrl,
    this.expanded = false,
    this.selectionMode = false,
    this.isSelected = false,
    this.onToggleExpand,
    this.onToggleSelect,
    this.onEnterSelection,
    this.onEdit,
    this.onEditImage,
    this.onDelete,
  });

  final QuizBankQuestion question;
  final String serverUrl;
  final bool expanded;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback? onToggleExpand;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onEnterSelection;
  final VoidCallback? onEdit;
  final VoidCallback? onEditImage;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final hasImage = question.image.trim().isNotEmpty;
    final theme = Theme.of(context);
    final accent = _statusStyle(question.status).color;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: .06)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onToggleExpand,
          onLongPress: onEnterSelection,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary.withValues(alpha: .5)
                    : theme.dividerColor.withValues(alpha: .5),
              ),
              // 左侧状态色条：一眼扫出这条是待审还是已拒
              gradient: LinearGradient(
                colors: [accent.withValues(alpha: .5), Colors.transparent],
                stops: const [0.008, 0.008],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (selectionMode)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: isSelected,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onChanged: (_) => onToggleSelect?.call(),
                          ),
                        ),
                      ),
                    // 缩略图挪到左侧：原来埋在卡片最底下，得展开才看得见
                    if (hasImage) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _QuestionThumb(
                          image: question.image,
                          serverUrl: serverUrl,
                          size: expanded ? 64 : 52,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            question.question,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              height: 1.35,
                            ),
                            maxLines: expanded ? null : 2,
                            overflow: expanded ? null : TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 5,
                            runSpacing: 5,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (question.type.isNotEmpty)
                                _TypeChip(type: question.type),
                              if (question.status.isNotEmpty)
                                _StatusChip(status: question.status),
                              if (question.category.trim().isNotEmpty)
                                _MiniTag(
                                  text: question.category,
                                  color: const Color(0xFF64748B),
                                  icon: Icons.folder_outlined,
                                ),
                              if (!hasImage)
                                const _MiniTag(
                                  text: '无图',
                                  color: Color(0xFFB0B7C3),
                                  icon: Icons.image_not_supported_outlined,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!selectionMode)
                      SizedBox(
                        width: 32,
                        child: PopupMenuButton<String>(
                          tooltip: '题目操作',
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            Icons.more_vert_rounded,
                            size: 18,
                            color: theme.hintColor,
                          ),
                          onSelected: (v) => switch (v) {
                            'edit' => onEdit?.call(),
                            'editImage' => onEditImage?.call(),
                            'delete' => onDelete?.call(),
                            _ => null,
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.edit_outlined, size: 18),
                                title: Text('编辑'),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'editImage',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.image_outlined, size: 18),
                                title: Text('补图/换图'),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: Color(0xFFEF4444),
                                ),
                                title: Text(
                                  '删除',
                                  style: TextStyle(color: Color(0xFFEF4444)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                if (expanded) ...[
                  if (question.options.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const _CardSectionLabel(text: '选项', icon: Icons.list_rounded),
                    const SizedBox(height: 6),
                    ...question.options.asMap().entries.map(
                      (e) => _OptionRow(
                        letter: String.fromCharCode(65 + e.key),
                        text: e.value,
                        correct: _isCorrectOption(
                          question.answer,
                          e.key,
                          e.value,
                        ),
                      ),
                    ),
                  ],
                  if (question.answer.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const _CardSectionLabel(
                      text: '答案',
                      icon: Icons.check_circle_outline_rounded,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      question.answer,
                      style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  if (question.explanation.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const _CardSectionLabel(
                      text: '解析',
                      icon: Icons.lightbulb_outline_rounded,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      question.explanation,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 答案可能是「A」「AB」也可能是选项原文，两种都要能打对号。
  static bool _isCorrectOption(String answer, int index, String option) {
    final a = answer.trim();
    if (a.isEmpty) return false;
    final letter = String.fromCharCode(65 + index);
    final letterOnly = RegExp(r'^[A-Za-z]+$');
    if (letterOnly.hasMatch(a)) {
      return a.toUpperCase().contains(letter);
    }
    return a.toLowerCase() == option.trim().toLowerCase();
  }
}

/// 展开区的小节标题，替掉原来「选项：」这种裸文案。
class _CardSectionLabel extends StatelessWidget {
  const _CardSectionLabel({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).hintColor;
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: .4,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// 选项行：字母走圆形徽标，正确项加对号和绿底。
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.letter,
    required this.text,
    required this.correct,
  });

  final String letter;
  final String text;
  final bool correct;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF10B981);
    final badgeColor = correct ? green : Theme.of(context).hintColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: correct ? .18 : .1),
              shape: BoxShape.circle,
            ),
            child: correct
                ? const Icon(Icons.check_rounded, size: 12, color: green)
                : Text(
                    letter,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: badgeColor,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: correct ? green : null,
                fontWeight: correct ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 题目图片缩略图。
///
/// 取源判定走 QuizThumbImageSource（纯函数、有单测）：脏 data URL 不会在
/// build 里抛 FormatException 把列表项糊红，一律降级成占位图。
///
/// [serverUrl] 是服务器地址（不带 path），用于解析相对路径。
class _QuestionThumb extends StatelessWidget {
  const _QuestionThumb({
    required this.image,
    required this.serverUrl,
    this.size = 48,
  });

  final String image;
  final String serverUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    // base 必须传：生产库里 image 全是 /api/quiz/images/xxx 这种相对路径，
    // 不传 base 的话 parse 会把它们全判成 placeholder，后台有图的题看起来都没图。
    final source = QuizThumbImageSource.parse(image, base: serverUrl);
    return SizedBox(
      width: size,
      height: size,
      child: source.kind == QuizThumbKind.bytes
          ? Image.memory(
              source.bytes!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const _PlaceholderThumb(),
            )
          : source.kind == QuizThumbKind.network && source.url != null
          // parse 已经把相对路径解析成完整 URL，这里不用再拼一次。
          ? NetworkImageOrPlaceholder(source.url!)
          : const _PlaceholderThumb(),
    );
  }
}

class _PlaceholderThumb extends StatelessWidget {
  const _PlaceholderThumb();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .6),
      alignment: Alignment.center,
      child: Icon(
        Icons.image_not_supported,
        size: 18,
        color: theme.hintColor.withValues(alpha: .7),
      ),
    );
  }
}

class NetworkImageOrPlaceholder extends StatelessWidget {
  const NetworkImageOrPlaceholder(this.url, {super.key});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const _PlaceholderThumb(),
      // 加载中给个静默底色，不要闪白块
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : Container(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: .6),
            ),
    );
  }
}

/// 多选操作条，用 SliverToBoxAdapter 避免 SliverPersistentHeader 滚动崩溃。
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.selectedCount,
    required this.onClear,
    required this.onBulkCategorize,
    required this.onBulkImage,
  });

  final int selectedCount;
  final VoidCallback onClear;
  final VoidCallback onBulkCategorize;
  final VoidCallback onBulkImage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              // 「取消」放最左当出口，右边留给操作，符合手指习惯
              IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded, size: 20),
                visualDensity: VisualDensity.compact,
                tooltip: '退出多选',
              ),
              Text(
                '已选 $selectedCount 题',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const Spacer(),
              // 操作按钮不能进 Flexible：文字会被压成省略号
              _BarAction(
                icon: Icons.category_rounded,
                label: '分类',
                onPressed: onBulkCategorize,
              ),
              const SizedBox(width: 6),
              _BarAction(
                icon: Icons.image_rounded,
                label: '图片',
                onPressed: onBulkImage,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarAction extends StatelessWidget {
  const _BarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(0, 34),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
