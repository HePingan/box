// 服务器运维插件：文件**编辑**页。
//
// 为什么要有它：改一行配置（hosts、nginx、systemd 单元、脚本）以前只能在文件页
// 预览、然后装个第三方编辑器再输一遍口令。这里把这一步收进 App。
//
// 设计取舍（都不是随手定的）：
//   * **只给文本**：有 NUL 字节、非 UTF-8、超过 256KB —— 三种情况都只读并说明原因。
//     GBK 的配置读进来是乱码，存回去就是把好好的文件改坏；
//   * **保存前必须备份**：内容 COPY 成 `<name>.box-bak-<时间戳>`（只留最近 3 份），
//     备份失败就**不放行保存** —— 没有后路的写入不做；
//   * **会把自己锁在门外的文件多一道确认**（sshd_config / fstab / nginx / htpasswd…）：
//     不是禁止，是把"改坏了的后果"写在按钮上方，让人知道自己在改什么；
//   * **改动检测**：打开时记下大小与修改时间，保存前重取一次，期间被人改过就问一句；
//   * **按原风格回写**：BOM、结尾换行、CRLF 都跟着原文件走 —— 否则一次保存会把
//     整个文件的换行都改掉，diff 一屏红。

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_files_service.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_text_edit.dart';

/// 打开编辑器：读文件 → 判断能不能编辑 → 编辑 → 保存（带备份与确认）。
class OpsFileEditorPage extends StatefulWidget {
  const OpsFileEditorPage({
    super.key,
    required this.service,
    required this.path,
    required this.name,
    this.onSaved,
  });

  final ServerOpsFilesService service;
  final String path;
  final String name;

  /// 保存成功后回调（文件页据此刷新）。
  final Future<void> Function()? onSaved;

  @override
  State<OpsFileEditorPage> createState() => _OpsFileEditorPageState();
}

class _OpsFileEditorPageState extends State<OpsFileEditorPage> {
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();

  bool _loading = true;
  String? _blocked; // 不能编辑的原因（只读展示）
  String? _error;
  bool _dirty = false;
  bool _saving = false;

  OpsTextStyle _style = OpsTextStyle.plain;

  /// 打开时的大小/修改时间：保存前比对，用来发现"期间被别人改过"。
  int? _openedSize;
  DateTime? _openedModifiedAt;

  /// 查找/替换条。
  bool _showFind = false;
  final TextEditingController _find = TextEditingController();
  final TextEditingController _replace = TextEditingController();
  String? _findMsg;

  @override
  void initState() {
    super.initState();
    _text.addListener(() {
      final dirty = !_dirty;
      if (dirty) setState(() => _dirty = true);
    });
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    _find.dispose();
    _replace.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _blocked = null;
    });
    try {
      final stat = await widget.service.statFor(widget.path);
      if (!mounted) return;
      final size = stat?.size;
      if (size != null && size > kOpsEditMaxBytes) {
        setState(() {
          _loading = false;
          _blocked = '这个文件 ${_pretty(size)}，超过编辑上限 '
              '${_pretty(kOpsEditMaxBytes)} —— 请用文件页的预览，或在终端里改。';
        });
        return;
      }
      final result =
          await widget.service.readUpTo(widget.path, kOpsEditMaxBytes);
      if (!mounted) return;
      final bytes = Uint8List.fromList(result.bytes);
      if (result.truncated) {
        setState(() {
          _loading = false;
          _blocked = '这个文件比编辑上限（${_pretty(kOpsEditMaxBytes)}）还大，只支持预览。';
        });
        return;
      }
      if (opsLooksBinary(bytes)) {
        setState(() {
          _loading = false;
          _blocked = '这个文件看着是二进制（不是文本），不能当文本编辑。';
        });
        return;
      }
      if (!opsIsValidUtf8(bytes)) {
        setState(() {
          _loading = false;
          _blocked = '这个文件不是 UTF-8 编码（可能是 GBK 等）—— 直接编辑存回去会变乱码，'
              '所以只给预览。要改就先在终端里用 iconv 转好。';
        });
        return;
      }
      // 去掉 BOM 再进编辑器：BOM 属于文件风格，保存时按 _style 还原。
      var text = utf8.decode(bytes);
      if (text.startsWith('\uFEFF')) text = text.substring(1);
      setState(() {
        _loading = false;
        _style = OpsTextStyle.detect(bytes, text);
        _text.text = text;
        _dirty = false;
        _openedSize = stat?.size;
        _openedModifiedAt = stat?.modifiedAt;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = serverOpsErrorMessage(e);
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    // 1) 会把自己锁在门外的文件：先把后果说清楚
    final lockout = opsLockoutWarning(widget.path);
    if (lockout != null) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('保存前确认'),
          content: Text('$lockout\n\n路径：${widget.path}\n\n'
              '（保存前会自动把原内容备份成 ${ServerOpsFilesService.basename(widget.path)}'
              '$kOpsBackupMarker…，真出问题还能在「历史版本」里退回来。）'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('先不改'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('仍要保存'),
            ),
          ],
        ),
      );
      if (go != true) return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // 2) 期间被人改过吗（大小或修改时间变了）
      final now = await widget.service.statFor(widget.path);
      final changed = now != null &&
          ((_openedSize != null && now.size != _openedSize) ||
              (_openedModifiedAt != null &&
                  now.modifiedAt != null &&
                  now.modifiedAt!.isAfter(_openedModifiedAt!)));
      if (changed && mounted) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('这台上的文件已经变了'),
            content: Text('打开之后，${ServerOpsFilesService.basename(widget.path)} '
                '在服务器上被改过（大小或时间不一样）。\n\n'
                '现在保存会用你手机上的这一份覆盖掉它。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('覆盖'),
              ),
            ],
          ),
        );
        if (go != true) {
          if (mounted) setState(() => _saving = false);
          return;
        }
      }

      // 3) 备份（失败就抛，不放行保存）
      final backup = await widget.service.backupBeforeSave(widget.path);
      // 4) 回写：按原文件的风格（BOM / 结尾换行 / CRLF）
      final bytes = opsEncodeWithStyle(_text.text, _style);
      // 先写临时名再 MOVE 盖上去：断网不会把目标文件留成半截
      await widget.service.saveTextAtomic(widget.path, bytes);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
        _openedSize = bytes.length;
        _openedModifiedAt = DateTime.now();
      });
      await widget.onSaved?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已保存（原文件备份成 ${ServerOpsFilesService.basename(backup)}）'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = serverOpsErrorMessage(e);
      });
    }
  }

  /// 历史版本：列备份、可恢复（恢复前会把当前内容也备份一份）。
  Future<void> _history() async {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => FutureBuilder<List<RemoteStorageEntry>>(
        future: widget.service.listBackups(widget.path),
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final backups = snap.data!;
          if (backups.isEmpty) {
            return const SizedBox(
              height: 140,
              child: Center(
                child: Text('还没有备份 —— 每次保存都会自动留一份。'),
              ),
            );
          }
          return ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                dense: true,
                title: Text(
                  '历史版本（恢复前会先把当前内容备份一次，恢复错了还能退回来）',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              for (final b in backups)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.history_rounded, size: 18),
                  title: Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(b.modifiedAt == null
                      ? ''
                      : _prettyTime(b.modifiedAt!)),
                  trailing: TextButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _restore(b);
                    },
                    child: const Text('恢复'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _restore(RemoteStorageEntry backup) async {
    setState(() => _saving = true);
    try {
      await widget.service.restoreBackup(backup.path, widget.path);
      if (!mounted) return;
      await widget.onSaved?.call();
      await _load(); // 重新读回来，别让编辑器里还留着旧内容
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已恢复到这个版本')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = serverOpsErrorMessage(e);
      });
    }
  }

  // ── 查找 / 替换 ──────────────────────────────────────────────

  void _findNext({bool backwards = false}) {
    final q = _find.text;
    if (q.isEmpty) {
      setState(() => _findMsg = '先填要查找的内容');
      return;
    }
    final text = _text.text;
    final sel = _text.selection;
    int at;
    if (backwards) {
      final from = sel.isValid && sel.start > 0 ? sel.start : text.length;
      at = text.lastIndexOf(q, from > 0 ? from - 1 : 0);
      if (at < 0) at = text.lastIndexOf(q); // 回绕到末尾
    } else {
      final from = sel.isValid && sel.end > 0 ? sel.end : 0;
      at = text.indexOf(q, from);
      if (at < 0) at = text.indexOf(q); // 回绕到开头
    }
    if (at < 0) {
      setState(() => _findMsg = '没有匹配');
      return;
    }
    _text.selection = TextSelection(baseOffset: at, extentOffset: at + q.length);
    setState(() => _findMsg = '已定位到第 ${_lineOf(at)} 行');
  }

  void _replaceCurrent() {
    final q = _find.text;
    final sel = _text.selection;
    if (q.isEmpty) {
      setState(() => _findMsg = '先填要查找的内容');
      return;
    }
    if (!sel.isValid || _text.text.substring(sel.start, sel.end) != q) {
      _findNext();
      return;
    }
    final text = _text.text;
    _text.value = TextEditingValue(
      text: text.replaceRange(sel.start, sel.end, _replace.text),
      selection: TextSelection.collapsed(
        offset: sel.start + _replace.text.length,
      ),
    );
    _findNext();
  }

  void _replaceAll() {
    final q = _find.text;
    if (q.isEmpty) {
      setState(() => _findMsg = '先填要查找的内容');
      return;
    }
    final count = q.allMatches(_text.text).length;
    if (count == 0) {
      setState(() => _findMsg = '没有匹配');
      return;
    }
    _text.text = _text.text.replaceAll(q, _replace.text);
    setState(() => _findMsg = '已替换 $count 处');
  }

  int _lineOf(int offset) {
    var line = 1;
    for (var i = 0; i < offset && i < _text.text.length; i++) {
      if (_text.text.codeUnitAt(i) == 0x0A) line++;
    }
    return line;
  }

  /// 符号键：手机上改配置最缺的就是这些字符。
  void _insert(String s) {
    final sel = _text.selection;
    final text = _text.text;
    if (!sel.isValid) {
      _text.text = '$text$s';
      _text.selection = TextSelection.collapsed(offset: _text.text.length);
      return;
    }
    _text.value = TextEditingValue(
      text: text.replaceRange(sel.start, sel.end, s),
      selection: TextSelection.collapsed(offset: sel.start + s.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lockout = opsLockoutWarning(widget.path);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Flexible(
              child: Text(
                widget.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_dirty)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Text('•', style: TextStyle(fontSize: 22)),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '查找 / 替换',
            onPressed: _blocked != null
                ? null
                : () => setState(() {
                      _showFind = !_showFind;
                      if (!_showFind) _findMsg = null;
                    }),
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            tooltip: '历史版本',
            onPressed: _blocked != null ? null : _history,
            icon: const Icon(Icons.history_rounded),
          ),
          TextButton(
            onPressed: (_blocked == null && _dirty && !_saving) ? _save : null,
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
      body: Column(
        children: [
          if (_blocked != null)
            _Banner(
              icon: Icons.info_outline_rounded,
              color: theme.colorScheme.outline,
              text: _blocked!,
            )
          else if (lockout != null)
            _Banner(
              icon: Icons.warning_amber_rounded,
              color: theme.colorScheme.error,
              text: '$lockout\n保存前会再确认一次。',
            ),
          if (_error != null)
            _Banner(
              icon: Icons.error_outline_rounded,
              color: theme.colorScheme.error,
              text: _error!,
            ),
          if (_showFind) _findBar(theme),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _blocked != null
                    ? const SizedBox.shrink()
                    : Container(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.35),
                        child: TextField(
                          key: const ValueKey('ops-editor-field'),
                          controller: _text,
                          scrollController: _scroll,
                          readOnly: _blocked != null,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          keyboardType: TextInputType.multiline,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            height: 1.35,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(12),
                            hintText: '（空文件）',
                          ),
                        ),
                      ),
          ),
          if (_blocked == null && !_loading) _symbolRow(theme),
        ],
      ),
    );
  }

  Widget _findBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('ops-editor-find'),
                  controller: _find,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: '查找',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _findNext(),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  key: const ValueKey('ops-editor-replace'),
                  controller: _replace,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: '替换为',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton(onPressed: _findNext, child: const Text('下一个')),
              TextButton(
                onPressed: () => _findNext(backwards: true),
                child: const Text('上一个'),
              ),
              TextButton(onPressed: _replaceCurrent, child: const Text('替换')),
              TextButton(onPressed: _replaceAll, child: const Text('全部替换')),
              if (_findMsg != null)
                Expanded(
                  child: Text(
                    _findMsg!,
                    style: theme.textTheme.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 符号键行：`#` `/` `{` 这些在手机键盘上要翻两层，改配置时最烦。
  Widget _symbolRow(ThemeData theme) {
    const keys = <String>[
      '#', '/', '\\', '|', '{', '}', '(', ')', '[', ']', '<', '>',
      '\$', '*', '&', ';', ':', '=', '"', "'", '~', '-', '_', '@',
    ];
    return Container(
      height: 40,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        children: [
          for (final k in keys)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(38, 30),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _insert(k),
                child: Text(
                  k,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: color.withValues(alpha: 0.10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 11.5, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

String _pretty(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

String _prettyTime(DateTime at) {
  final t = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}
