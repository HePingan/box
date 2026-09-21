import 'dart:io';

import 'package:flutter/material.dart';

import '../data/quiz_cloud_push.dart';
import '../data/quiz_vision_candidate_store.dart';
import '../domain/quiz_bank.dart';
import '../domain/quiz_vision_candidate.dart';

/// 「AI 命中候选」页：AI 读屏命中但**未自动上报**的题在此留档，由用户查看
/// 截图与识别信息、补充选项后手动投稿，或删除。
///
/// 用户 2026-09-13 拍板：
///   - 「A 档不提交，保留该题的截图及 ai 识别的题目信息，后面我再手动补充」
///   - conf ≥ 0.9 且选项齐全且已登录的题已在命中时**静默**上报，通常不在此列；
///     但若上报失败（离线/服务端异常）也会留档，用户可在此重投。
class QuizVisionCandidatesPage extends StatefulWidget {
  const QuizVisionCandidatesPage({super.key});

  @override
  State<QuizVisionCandidatesPage> createState() =>
      _QuizVisionCandidatesPageState();
}

class _QuizVisionCandidatesPageState extends State<QuizVisionCandidatesPage> {
  final _push = QuizCloudPushCoordinator();
  List<QuizVisionCandidate> _items = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await QuizVisionCandidateStore.loadAll();
    if (!mounted) return;
    setState(() {
      _items = items.reversed.toList(growable: false);
      _loading = false;
    });
  }

  Future<void> _delete(QuizVisionCandidate c) async {
    final id = c.id;
    if (id == null) return;
    await QuizVisionCandidateStore.removeById(id);
    await _load();
  }

  /// 手动投稿：把留档候选转成题库条目 → 走既有投稿链路 → 成功后从队列移除。
  Future<void> _submit(QuizVisionCandidate c) async {
    if (_busy) return;
    if (c.effectiveOptions.length < QuizVisionCandidate.minOptionCount) {
      _snack('选项不足 2 项，请先补充选项再投稿');
      return;
    }
    setState(() => _busy = true);
    try {
      final id = c.id ?? 'q_vision_manual_${DateTime.now().millisecondsSinceEpoch}';
      final item = c.toBankItem(id: id);
      await QuizBankStorage.upsertItem(item);
      final result = await _push.pushItems([item], onProgress: null);
      final ok = result.submitted + result.merged > 0;
      if (!mounted) return;
      if (ok) {
        await QuizVisionCandidateStore.removeById(id);
        await _load();
        _snack('已投稿，等待后台审核通过后自动同步到本地题库');
      } else {
        _snack('投稿未成功（${result.invalid} 校验失败 / ${result.failed} 失败），留档保留');
      }
    } catch (e) {
      if (mounted) _snack('投稿失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('AI 命中候选 ${_items.length}'),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              tooltip: '清空全部',
              onPressed: _busy
                  ? null
                  : () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('清空全部候选？'),
                          content: const Text('截图与识别信息将一并删除，不可恢复。'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('清空'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await QuizVisionCandidateStore.clear();
                        await _load();
                      }
                    },
              icon: const Icon(Icons.delete_sweep_rounded),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '暂无留档候选。\n\nAI 读屏命中的题会在置信度不足 / 选项不齐 / 未登录 / 上报失败时'
                  '自动留档到这里，方便你补充后手动投稿。',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) => _candidateCard(_items[i]),
            ),
    );
  }

  Widget _candidateCard(QuizVisionCandidate c) {
    final submitReady =
        c.effectiveOptions.length >= QuizVisionCandidate.minOptionCount;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    c.stem.isEmpty ? '（题干为空）' : c.stem,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                _confidenceChip(c.confidence),
              ],
            ),
            const SizedBox(height: 8),
            if (c.imagePath != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(c.imagePath!),
                  height: 120,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(
                    height: 40,
                    child: Text('截图已丢失', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            if (c.effectiveOptions.isEmpty)
              const Text('选项：无（需手动补充）', style: TextStyle(fontSize: 12))
            else
              ...c.effectiveOptions.map(
                (o) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('· $o', style: const TextStyle(fontSize: 13)),
                ),
              ),
            const SizedBox(height: 4),
            Text(
              'AI 判定答案：${c.answer.isEmpty ? "（空）" : c.answer}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            if (c.keepReason != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '未自动上报：${c.keepReason}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _busy || !submitReady
                        ? null
                        : () => _submit(c),
                    icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                    label: Text(submitReady ? '投稿到云端审核' : '选项不足，先补充'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '删除该候选',
                  onPressed: _busy ? null : () => _delete(c),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _confidenceChip(double conf) {
    final pct = (conf * 100).round();
    final ok = conf >= QuizVisionCandidate.confidenceThreshold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (ok ? Colors.green : Colors.orange).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '置信 $pct%',
        style: TextStyle(
          fontSize: 12,
          color: ok ? Colors.green.shade800 : Colors.orange.shade900,
        ),
      ),
    );
  }
}
