import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';

import '../domain/ocr_quiz_parser.dart';
import '../domain/quiz_bank.dart';
import '../data/quiz_ocr_client.dart';
import './quiz_plugin_entry.dart';
import './quiz_bank_view_page.dart';

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
    if (!mounted) return;
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
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const QuizBankViewPage())),
            icon: const Icon(Icons.library_books_outlined),
            tooltip: '题库查看',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'ocr-page',
                child: Row(
                  children: [
                    Icon(Icons.document_scanner_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('OCR 填本页'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'ocr-float',
                child: Row(
                  children: [
                    Icon(Icons.picture_in_picture_alt_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('悬浮窗录入'),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'ocr-float') _openOcrFloating();
              if (value == 'ocr-page' && !_ocrBusy) _ocrFillCurrentForm();
            },
          ),
          IconButton(onPressed: _save, icon: const Icon(Icons.save_rounded)),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
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

            const SizedBox(height: 12),

            // 题干
            TextField(
              controller: _questionController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '题目',
                hintText: '请输入题目内容',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 选项 — 紧凑行：输入框 + 单选按钮 + 标签
            const Row(
              children: [
                Text(
                  '选项',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                Spacer(),
                Text(
                  '点击 ● 标记正确答案',
                  style: TextStyle(fontSize: 11, color: AppTokens.textTertiary),
                ),
              ],
            ),
            const SizedBox(height: 6),
            RadioGroup<int>(
              groupValue: _correctIndex,
              onChanged: (value) => setState(() => _correctIndex = value ?? 0),
              child: Column(
                children: List.generate(_optionControllers.length, (index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: Radio<int>(
                            value: index,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: TextField(
                            controller: _optionControllers[index],
                            decoration: InputDecoration(
                              hintText: '选项 ${(index + 1)}',
                              border: const OutlineInputBorder(),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),

            const SizedBox(height: 12),

            // 解析
            TextField(
              controller: _analysisController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '解析（可选）',
                hintText: '请输入解析内容',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),

            const SizedBox(height: 16),
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
