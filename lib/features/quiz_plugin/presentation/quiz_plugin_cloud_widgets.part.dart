part of './quiz_plugin_entry.dart';

class _CloudQuizBankCard extends StatefulWidget {
  const _CloudQuizBankCard();

  @override
  State<_CloudQuizBankCard> createState() => _CloudQuizBankCardState();
}

class _CloudQuizBankCardState extends State<_CloudQuizBankCard> {
  final QuizCloudPullCoordinator _pull = QuizCloudPullCoordinator();
  QuizCloudPullStatus? _status;
  bool _busy = false;
  bool _autoEnabled = true;
  String? _progress;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  @override
  void dispose() {
    _pull.dispose();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    final status = await _pull.loadStatus();
    final autoEnabled = await QuizCloudAutoSync.instance.isEnabled();
    if (!mounted) return;
    setState(() {
      _status = status;
      _autoEnabled = autoEnabled;
    });
  }

  Future<void> _sync({bool resetCursor = false}) async {
    if (_busy) return;
    if (resetCursor) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('重置并全量重拉？'),
          content: const Text(
            '将清空本地同步游标，按已订阅分类重新拉取云端正式题。\n'
            '不会删除你本地 OCR/手工录入的题。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('开始'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() {
      _busy = true;
      _progress = resetCursor ? '准备全量重拉…' : '准备同步…';
    });
    try {
      final result = await _pull.pullAll(
        resetCursor: resetCursor,
        onProgress: (msg) {
          if (!mounted) return;
          setState(() => _progress = msg);
        },
      );
      await _refreshStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('云端同步完成：${result.summaryText}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('云端同步失败：$e')));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _repairImages() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = '扫描并补全题图…';
    });
    try {
      final result = await _pull.repairImages(
        onProgress: (msg) {
          if (!mounted) return;
          setState(() => _progress = msg);
        },
      );
      await _refreshStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '补图完成：扫描 ${result.scanned} · 成功 ${result.cached} · 失败 ${result.failed}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('补图失败：$e')));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _manageSubscriptions() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = '加载分类目录…';
    });
    try {
      final catalogs = await _pull.fetchCatalogs();
      final selected = (await _pull.loadSubscribedCategories()).toSet();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
      });
      final result = await showModalBottomSheet<List<String>>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) {
          return _CloudCategoryPicker(
            catalogs: catalogs,
            initiallySelected: selected,
          );
        },
      );
      if (result == null) return;
      await _pull.saveSubscribedCategories(result);
      await _refreshStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已保存订阅 ${result.length} 个分类')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加载分类失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final subtitle =
        _progress ??
        (status == null
            ? '读取同步状态…'
            : '${status.lastSyncLabel} · 本地 ${status.localCount} 题'
                  '${status.subscribedCategories.isEmpty ? '' : ' · 已订 ${status.subscribedCategories.length} 类'}'
                  '${status.lastSummary.isEmpty ? '' : '\n${status.lastSummary}'}');
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_download_rounded, color: Colors.indigo),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '云端题库',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                FilledButton.tonal(
                  onPressed: _busy ? null : () => _sync(),
                  child: Text(_busy ? '同步中' : '更新'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            if (_busy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(minHeight: 2),
            ],
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _busy ? null : _manageSubscriptions,
                  child: const Text('分类订阅'),
                ),
                TextButton(
                  onPressed: _busy ? null : _repairImages,
                  child: const Text('仅补图'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _sync(resetCursor: true),
                  child: const Text('全量重拉'),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('自动更新云端题库', style: TextStyle(fontSize: 13)),
              subtitle: const Text(
                '启动/回前台静默增量，间隔 ≥ 6 小时',
                style: TextStyle(fontSize: 11),
              ),
              value: _autoEnabled,
              onChanged: _busy
                  ? null
                  : (v) async {
                      await QuizCloudAutoSync.instance.setEnabled(v);
                      if (!mounted) return;
                      setState(() => _autoEnabled = v);
                    },
            ),
            Text(
              status == null ? '同步正式发布题到本机，供离线搜题' : '服务：${status.serverUrl}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloudCategoryPicker extends StatefulWidget {
  const _CloudCategoryPicker({
    required this.catalogs,
    required this.initiallySelected,
  });

  final List<dynamic> catalogs;
  final Set<String> initiallySelected;

  @override
  State<_CloudCategoryPicker> createState() => _CloudCategoryPickerState();
}

class _CloudCategoryPickerState extends State<_CloudCategoryPicker> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initiallySelected};
    if (_selected.isEmpty) {
      for (final raw in widget.catalogs) {
        final id = '${raw.id}'.isNotEmpty ? '${raw.id}' : '${raw.name}';
        if (id.isNotEmpty) _selected.add(id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogs = widget.catalogs;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('订阅云端分类', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              '只同步勾选的分类。取消订阅不会删除本机已有题目。',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            if (catalogs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('云端暂无分类目录')),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: catalogs.length,
                  itemBuilder: (ctx, i) {
                    final c = catalogs[i];
                    final id = '${c.id}'.isNotEmpty ? '${c.id}' : '${c.name}';
                    final checked = _selected.contains(id);
                    return CheckboxListTile(
                      value: checked,
                      dense: true,
                      title: Text('${c.name}'.isEmpty ? id : '${c.name}'),
                      subtitle: Text('题量 ${c.count}'),
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selected.add(id);
                          } else {
                            _selected.remove(id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selected
                        ..clear()
                        ..addAll(
                          catalogs.map(
                            (c) =>
                                '${c.id}'.isNotEmpty ? '${c.id}' : '${c.name}',
                          ),
                        );
                    });
                  },
                  child: const Text('全选'),
                ),
                TextButton(
                  onPressed: () => setState(_selected.clear),
                  child: const Text('清空'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, _selected.toList()..sort()),
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
