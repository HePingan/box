// 题库歧义组批量补标页。
//
// 为什么需要：134 组同题干不同答案里，很多是新规/旧规并存（货车超限 1分 vs 6分）。
// 以前只能一题一题进编辑页勾「新规题」，慢且容易漏。这里按题干分组一次列全，
// 用户自己点哪条是新规 —— **不猜规则、不自动改数据**。
import 'package:flutter/material.dart';

import '../../../design_system/app_tokens.dart';
import '../domain/quiz_bank.dart';

class AmbiguousGroup {
  const AmbiguousGroup({
    required this.stem,
    required this.items,
    required this.answerCount,
  });

  final String stem;
  final List<QuizBankItem> items;
  final int answerCount;
}

/// 按归一化题干分组，只保留「同题干但答案不止一种」的组。
/// 纯函数，便于测试；排序让最大歧义组排在最前（报障优先级最高）。
List<AmbiguousGroup> groupAmbiguousQuestions(List<QuizBankItem> items) {
  final byStem = <String, List<QuizBankItem>>{};
  for (final item in items) {
    final stem = QuizBankTextNormalizer.cleanForMatch(item.question);
    if (stem.isEmpty) continue;
    (byStem[stem] ??= []).add(item);
  }
  final groups = <AmbiguousGroup>[];
  for (final entry in byStem.entries) {
    if (entry.value.length < 2) continue;
    final answers = entry.value.map((e) => e.correctAnswer.trim()).toSet();
    if (answers.length < 2) continue;
    groups.add(
      AmbiguousGroup(
        stem: entry.key,
        items: List.unmodifiable(entry.value),
        answerCount: answers.length,
      ),
    );
  }
  groups.sort((a, b) => b.items.length.compareTo(a.items.length));
  return List.unmodifiable(groups);
}

class QuizAmbiguousGroupsPage extends StatefulWidget {
  const QuizAmbiguousGroupsPage({super.key});

  @override
  State<QuizAmbiguousGroupsPage> createState() =>
      _QuizAmbiguousGroupsPageState();
}

class _QuizAmbiguousGroupsPageState extends State<QuizAmbiguousGroupsPage> {
  List<AmbiguousGroup> _groups = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final groups = groupAmbiguousQuestions(await QuizBankStorage.loadAll());
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _toggle(QuizBankItem item) async {
    try {
      await QuizBankStorage.replaceItem(
        item.id,
        item.copyWith(isNewRule: !item.isNewRule),
      );
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('标记失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('歧义题补标'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.spaceLg),
                child: Text('读取题库失败：$_error'),
              ),
            )
          : _groups.isEmpty
          ? const Center(child: Text('没有同题干异答案的题目'))
          : ListView.builder(
              padding: const EdgeInsets.all(AppTokens.spaceMd),
              itemCount: _groups.length,
              itemBuilder: (context, index) {
                final group = _groups[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: AppTokens.spaceSm),
                  child: ExpansionTile(
                    title: Text(
                      group.stem,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${group.items.length} 条 · ${group.answerCount} 种答案',
                    ),
                    initiallyExpanded: index < 3,
                    children: [
                      for (final item in group.items)
                        ListTile(
                          dense: true,
                          title: Text(
                            '答案：${item.correctAnswer}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${item.options.length} 个选项'
                            '${(item.imageUrl ?? '').isNotEmpty ? ' · 有题图' : ''}'
                            '${item.isNewRule ? ' · 已标新规' : ''}',
                          ),
                          trailing: FilledButton.tonal(
                            onPressed: () => _toggle(item),
                            child: Text(
                              item.isNewRule ? '取消新规' : '标为新规',
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
