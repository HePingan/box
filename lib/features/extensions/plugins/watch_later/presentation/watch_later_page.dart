// 影视「稍后看」：把想看的片子存进远程存储，点开直接播。
//
// 存哪定的是远程存储（`box-watchlist/watch-later.json`），与快速便签同一套理由：
// 换手机还在，用户能在远程存储浏览器里看到/备份这个清单。
//
// 形状与 quick_note / net_diag 一致：存储与「播放入口」都可注入，
// 失败**写出原因**，不表现成「一直在转圈」。
library;

import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_back_button.dart';
import 'package:box/video/video_compat_pages.dart';

import '../../remote_storage/domain/remote_storage_models.dart';
import '../../remote_storage/presentation/remote_storage_page.dart';
import '../data/watch_later_store.dart';
import '../domain/watch_later_item.dart';

/// 页面用的存储实例（测试可替换）。
WatchLaterStore _runtimeStore = WebdavWatchLaterStore();

void debugSetWatchLaterRuntime({WatchLaterStore? store}) {
  _runtimeStore = store ?? WebdavWatchLaterStore();
}

WatchLaterStore get debugWatchLaterStore => _runtimeStore;

class WatchLaterPage extends StatefulWidget {
  const WatchLaterPage({super.key, this.initialPayload = '', this.onPlay});

  /// 插件 payload：可以直接带一个「要加入的地址」（纯 URL 或
  /// `{"url":…,"title":…}`），进来就把添加弹层填好。
  final String initialPayload;

  /// 播放入口（测试接缝）：默认推到影视播放页。
  final void Function(WatchLaterItem item)? onPlay;

  @override
  State<WatchLaterPage> createState() => _WatchLaterPageState();
}

class _WatchLaterPageState extends State<WatchLaterPage> {
  List<RemoteStorageAccount> _accounts = const [];
  RemoteStorageAccount? _account;
  List<WatchLaterItem> _items = const [];
  bool _loading = true;
  bool _busy = false;
  String _error = '';

  WatchLaterStore get _store => _runtimeStore;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final accounts = await _store.accounts();
      if (!mounted) return;
      if (accounts.isEmpty) {
        setState(() {
          _accounts = const [];
          _account = null;
          _items = const [];
          _loading = false;
        });
        return;
      }
      final lastId = await _store.lastAccountId();
      final picked = accounts.firstWhere(
        (a) => a.id == lastId,
        orElse: () => accounts.first,
      );
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _account = picked;
      });
      await _load();
      await _maybeOpenFromPayload();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '账户读取失败：$e';
        _loading = false;
      });
    }
  }

  /// payload 带了地址 → 把添加弹层填好（不直接落库：用户可能点错链接）。
  Future<void> _maybeOpenFromPayload() async {
    final parsed = parseWatchLaterPayload(widget.initialPayload);
    if (parsed == null || !mounted) return;
    await _openAddSheet(prefillUrl: parsed.url, prefillTitle: parsed.title);
  }

  Future<void> _load() async {
    final account = _account;
    if (account == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final items = await _store.load(account);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '清单读取失败：${_describe(e)}';
        _loading = false;
      });
    }
  }

  Future<void> _switchAccount(RemoteStorageAccount account) async {
    setState(() => _account = account);
    await _store.rememberAccount(account.id);
    await _load();
  }

  Future<void> _openAddSheet({String prefillUrl = '', String prefillTitle = ''}) async {
    final result = await showModalBottomSheet<({String url, String title})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AddWatchLaterSheet(
        initialUrl: prefillUrl,
        initialTitle: prefillTitle,
      ),
    );
    if (result == null) return;
    await _add(result.url, result.title);
  }

  Future<void> _add(String url, String title) async {
    final account = _account;
    if (account == null) return;
    final now = DateTime.now();
    final item = WatchLaterItem(
      url: url,
      title: title.trim().isEmpty ? watchLaterTitleFromUrl(url) : title.trim(),
      sourceName: watchLaterHostOf(url),
      addedAtMs: now.millisecondsSinceEpoch,
    );
    final existed = _items.any((e) => e.url == url);
    final next = addWatchLater(_items, item);
    setState(() => _busy = true);
    try {
      await _store.save(account, next);
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(existed ? '已在清单里，已移到最前' : '已加入稍后看');
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('保存失败：${_describe(e)}');
    }
  }

  Future<void> _confirmDelete(WatchLaterItem item) async {
    final account = _account;
    if (account == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从稍后看移除'),
        content: Text('将移除「${item.title}」，远程存储里的清单会同步更新。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTokens.rose),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _store.save(account, removeWatchLater(_items, item.url));
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('已移除');
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('移除失败：${_describe(e)}');
    }
  }

  void _play(WatchLaterItem item) {
    final handler = widget.onPlay;
    if (handler != null) {
      handler(item);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerPage(url: item.url, title: item.title),
      ),
    );
  }

  String _describe(Object e) {
    final text = e.toString();
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.background,
      floatingActionButton: _account == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : () => _openAddSheet(),
              icon: const Icon(Icons.add),
              label: const Text('加入稍后看'),
            ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  AppBackButton(onPressed: () => Navigator.maybePop(context)),
                  const SizedBox(width: 8),
                  const Text(
                    '稍后看',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (_loading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_error.isNotEmpty) {
      return _ErrorBlock(message: _error, onRetry: _boot);
    }
    if (_accounts.isEmpty) {
      return _NoAccountBlock(onAdd: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RemoteStoragePage()),
        );
        await _boot();
      });
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _headerCard(),
          const SizedBox(height: 12),
          if (_loading && _items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_items.isEmpty)
            _EmptyBlock(onCreate: () => _openAddSheet())
          else
            for (final item in _items) ...[
              _ItemCard(
                item: item,
                busy: _busy,
                onTap: () => _play(item),
                onDelete: () => _confirmDelete(item),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  Widget _headerCard() {
    final account = _account;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTokens.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_accounts.length > 1)
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: account?.id,
                items: [
                  for (final a in _accounts)
                    DropdownMenuItem(
                      value: a.id,
                      child: Text(
                        a.label.isEmpty ? a.displayHost : a.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) {
                  if (id == null) return;
                  _switchAccount(_accounts.firstWhere((a) => a.id == id));
                },
              ),
            )
          else
            Text(
              account == null
                  ? ''
                  : (account.label.isEmpty ? account.displayHost : account.label),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          const SizedBox(height: 4),
          Text(
            '清单存在远程存储的 $kWatchLaterPath，共 ${_items.length} 条',
            style: TextStyle(fontSize: 12, color: AppTokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.busy,
    required this.onTap,
    required this.onDelete,
  });

  final WatchLaterItem item;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final when = item.addedAt;
    final timeText = when == null
        ? ''
        : ' · 添加于 ${when.month.toString().padLeft(2, '0')}-'
            '${when.day.toString().padLeft(2, '0')} '
            '${when.hour.toString().padLeft(2, '0')}:'
            '${when.minute.toString().padLeft(2, '0')}';
    return Material(
      color: AppTokens.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: busy ? null : onTap,
        onLongPress: busy ? null : onDelete,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTokens.cardBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.play_circle_outline, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.sourceName.isEmpty ? watchLaterHostOf(item.url) : item.sourceName}$timeText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '移除',
                onPressed: busy ? null : onDelete,
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: AppTokens.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddWatchLaterSheet extends StatefulWidget {
  const _AddWatchLaterSheet({
    required this.initialUrl,
    required this.initialTitle,
  });

  final String initialUrl;
  final String initialTitle;

  @override
  State<_AddWatchLaterSheet> createState() => _AddWatchLaterSheetState();
}

class _AddWatchLaterSheetState extends State<_AddWatchLaterSheet> {
  late final TextEditingController _url;
  late final TextEditingController _title;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.initialUrl);
    _title = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _url.text.trim();
    if (url.isEmpty) {
      setState(() => _error = '先填播放地址（影视页/云播页的链接都行）');
      return;
    }
    if (!isPlayableWatchLaterUrl(url)) {
      setState(() => _error = '只支持 http/https 地址');
      return;
    }
    Navigator.pop(context, (url: url, title: _title.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '加入稍后看',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '粘贴影视页或云播页地址；标题留空会从地址里推一个',
              style: TextStyle(fontSize: 12, color: AppTokens.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '播放地址',
                hintText: 'https://…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: '标题（可空）',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _error,
                style: const TextStyle(color: AppTokens.rose, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _submit,
                    child: const Text('保存'),
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

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.movie_outlined, size: 40, color: AppTokens.textTertiary),
          const SizedBox(height: 10),
          Text('还没有想看的', style: TextStyle(color: AppTokens.textSecondary)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onCreate, child: const Text('加一条')),
        ],
      ),
    );
  }
}

class _NoAccountBlock extends StatelessWidget {
  const _NoAccountBlock({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_outlined, size: 44, color: AppTokens.textTertiary),
            const SizedBox(height: 12),
            const Text(
              '稍后看清单存在远程存储里，先添加一个账户',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              '支持 WebDAV（群晖 / Nextcloud / 坚果云等）',
              style: TextStyle(fontSize: 12, color: AppTokens.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onAdd, child: const Text('去添加账户')),
          ],
        ),
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 40, color: AppTokens.rose),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
