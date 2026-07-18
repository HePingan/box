import 'package:flutter/material.dart';

import 'ocr_quiz_parser.dart';
import 'quiz_bank.dart';
import 'quiz_ocr_client.dart';
import 'quiz_plugin_entry.dart';
import 'quiz_bank_view_page.dart';

class QuizEntryPage extends StatefulWidget {
  const QuizEntryPage({super.key});

  @override
  State<QuizEntryPage> createState() => _QuizEntryPageState();
}

class _QuizEntryPageState extends State<QuizEntryPage> {
  QuizQuestionType _type = QuizQuestionType.singleChoice;
  final TextEditingController _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];
  int _correctIndex = 0;
  final TextEditingController _analysisController = TextEditingController();
  bool _ocrBusy = false;

  @override
  void dispose() {
    _questionController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    _analysisController.dispose();
    super.dispose();
  }

  void _setOptionsCount(int n) {
    if (n == _optionControllers.length) return;
    while (_optionControllers.length < n) {
      _optionControllers.add(TextEditingController());
    }
    while (_optionControllers.length > n) {
      _optionControllers.removeLast().dispose();
    }
    if (_correctIndex >= n) _correctIndex = 0;
    setState(() {});
  }

  Future<void> _save() async {
    final question = _questionController.text.trim();
    if (question.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入题目')));
      return;
    }

    final options = _optionControllers
        .map((e) => e.text.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (options.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少输入一个选项')));
      return;
    }

    final correctAnswer = options[_correctIndex.clamp(0, options.length - 1)];
    final analysis = _analysisController.text.trim();

    final item = QuizBankItem(
      id: UniqueQuizKeyGenerator.key(question, options: options),
      question: question,
      type: _type,
      options: options,
      correctAnswer: correctAnswer,
      analysis: analysis.isEmpty ? null : analysis,
      source: '录入',
      createdAt: DateTime.now(),
    );

    final status = await QuizBankStorage.insertIfAbsent(item);
    if (!mounted) return;
    if (status == QuizBankWriteStatus.duplicateSkipped) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('检测到完全相同的题，未写入题库')));
      return;
    }
    final total = (await QuizBankStorage.loadAll()).length;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已保存，题库共 $total 条')));
    _resetForm();
  }

  void _resetForm() {
    _questionController.clear();
    for (final c in _optionControllers) {
      c.clear();
    }
    _correctIndex = 0;
    _analysisController.clear();
    setState(() {});
  }

  void _applyParse(OcrQuizParseResult parsed) {
    _questionController.text = parsed.question;
    for (final c in _optionControllers) {
      c.clear();
    }
    // 动态扩展选项框，避免 >4 个选项被截断
    _setOptionsCount(parsed.options.length.clamp(2, 8));
    for (
      var i = 0;
      i < parsed.options.length && i < _optionControllers.length;
      i++
    ) {
      _optionControllers[i].text = parsed.options[i];
    }
    if (parsed.options.length == 2 &&
        parsed.options.any((o) => o.contains('正确')) &&
        parsed.options.any((o) => o.contains('错误'))) {
      _type = QuizQuestionType.trueFalse;
    } else {
      _type = QuizQuestionType.singleChoice;
    }
    final ans = parsed.correctAnswer;
    var idx = parsed.options.indexOf(ans);
    if (idx < 0 && ans.isNotEmpty) {
      idx = parsed.options.indexWhere(
        (o) => o.contains(ans) || ans.contains(o),
      );
    }
    _correctIndex = idx >= 0 ? idx : 0;
    if (parsed.analysis.isNotEmpty) {
      _analysisController.text = parsed.analysis;
    }
    setState(() {});
  }

  Future<void> _openOcrFloating() async {
    final ok = await QuizPluginEntry.showOcrEntryOverlay();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? '已打开 OCR 悬浮录入：框选 → 识别 → 保存' : '打开失败：请先开启无障碍「答题助手」服务',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _ocrFillCurrentForm() async {
    if (_ocrBusy) return;
    setState(() => _ocrBusy = true);
    try {
      // 触发截图 OCR 同一路径
      final bytes = await QuizPluginEntry.captureRegionScreenshot();
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('截图失败：请先开启无障碍并设置识别区域')));
        return;
      }
      final config = await QuizPluginEntry.loadConfig();
      final client = QuizOcrClient(
        endpoint: config.ocrEndpoint,
        token: config.ocrToken,
      );
      final ocr = await client.recognizeBytes(bytes);
      if (!ocr.isSuccess) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ocr.error ?? 'OCR 失败')));
        return;
      }
      final parsed = OcrQuizParser.parse(ocr.fullText);
      _applyParse(parsed);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已填入 OCR 结果，请核对后保存')));
    } finally {
      if (mounted) setState(() => _ocrBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('录入题目'),
        actions: [
          IconButton(
            onPressed: _ocrBusy ? null : _ocrFillCurrentForm,
            icon: _ocrBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.document_scanner_outlined),
            tooltip: 'OCR 填入本页',
          ),
          IconButton(
            onPressed: _openOcrFloating,
            icon: const Icon(Icons.picture_in_picture_alt_outlined),
            tooltip: 'OCR 悬浮窗录入',
          ),
          IconButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const QuizBankViewPage())),
            icon: const Icon(Icons.library_books_outlined),
            tooltip: '题库查看',
          ),
          IconButton(onPressed: _save, icon: const Icon(Icons.save_rounded)),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'OCR 悬浮窗录入',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '开启无障碍后，可在任意 App 上方框选题目区域，OCR 识别并保存到题库。',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: _openOcrFloating,
                            icon: const Icon(
                              Icons.picture_in_picture_alt_outlined,
                            ),
                            label: const Text('打开悬浮录入'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _ocrBusy ? null : _ocrFillCurrentForm,
                            icon: const Icon(Icons.document_scanner_outlined),
                            label: const Text('OCR 填本页'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 题型选择
            SegmentedButton<QuizQuestionType>(
              segments: const [
                ButtonSegment(
                  value: QuizQuestionType.singleChoice,
                  label: Text('单选题'),
                  icon: Icon(Icons.radio_button_checked_rounded),
                ),
                ButtonSegment(
                  value: QuizQuestionType.trueFalse,
                  label: Text('判断题'),
                  icon: Icon(Icons.check_circle_outline_rounded),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (selected) {
                setState(() {
                  _type = selected.first;
                  if (_type == QuizQuestionType.trueFalse) {
                    _optionControllers[0].text = '正确';
                    _optionControllers[1].text = '错误';
                    _optionControllers[2].clear();
                    _optionControllers[3].clear();
                    _correctIndex = 0;
                  } else {
                    _optionControllers[0].clear();
                    _optionControllers[1].clear();
                    _optionControllers[2].clear();
                    _optionControllers[3].clear();
                  }
                });
              },
            ),

            const SizedBox(height: 16),

            // 题干
            TextField(
              controller: _questionController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '题目',
                hintText: '请输入题目内容',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            // 选项
            const Text('选项', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...List.generate(_optionControllers.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _optionControllers[index],
                        decoration: InputDecoration(
                          labelText: '选项 ${(index + 1)}',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    Radio<int>(
                      value: index,
                      groupValue: _correctIndex,
                      onChanged: (value) {
                        setState(() => _correctIndex = value ?? 0);
                      },
                    ),
                    const Text('正确答案'),
                  ],
                ),
              );
            }),

            const SizedBox(height: 16),

            // 解析
            TextField(
              controller: _analysisController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '解析（可选）',
                hintText: '请输入解析内容',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_rounded),
                label: const Text('保存到题库'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
