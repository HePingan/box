import 'package:flutter/material.dart';

import 'quiz_bank.dart';

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

  @override
  void dispose() {
    _questionController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    _analysisController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final question = _questionController.text.trim();
    if (question.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入题目')),
      );
      return;
    }

    final options = _optionControllers.map((e) => e.text.trim()).where((e) => e.isNotEmpty).toList();
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少输入一个选项')),
      );
      return;
    }

    final correctAnswer = options[_correctIndex];
    final analysis = _analysisController.text.trim();

    final item = QuizBankItem(
      id: UniqueQuizKeyGenerator.key(question),
      question: question,
      type: _type,
      options: options,
      correctAnswer: correctAnswer,
      analysis: analysis.isEmpty ? null : analysis,
      source: '录入',
      createdAt: DateTime.now(),
    );

    final merged = await QuizBankStorage.importItems([item]);
    QuizBankCache.instance.assign(merged);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已保存，题库共 ${merged.length} 条')),
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('录入题目'),
        actions: [
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
            const Text('选项',
                style: TextStyle(fontWeight: FontWeight.w700)),
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
