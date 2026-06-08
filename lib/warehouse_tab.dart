import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design_system/app_tokens.dart';
import 'design_system/widgets/app_cards.dart';
import 'novel/core/bookshelf_manager.dart';
import 'novel/core/cache_store.dart';
import 'novel/pages/novel_detail_page.dart';
import 'novel/pages/novel_list_page.dart';
import 'video_module.dart';

class WarehouseTab extends StatefulWidget {
  const WarehouseTab({super.key});

  @override
  State<WarehouseTab> createState() => _WarehouseTabState();
}

class _WarehouseTabState extends State<WarehouseTab>
    with AutomaticKeepAliveClientMixin {
  final WarehouseStore _store = WarehouseStore();

  late Future<List<WarehouseItem>> _bookFuture;
  late Future<List<WarehouseItem>> _comicFuture;
  late Future<List<WarehouseItem>> _videoFuture;
  late Future<List<WarehouseItem>> _musicFuture;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _bookFuture = _loadBooks();
    _comicFuture = _store.load(WarehouseCategory.comics);
    _videoFuture = _store.load(WarehouseCategory.videos);
    _musicFuture = _store.load(WarehouseCategory.music);
  }

  Future<void> _refresh() async {
    setState(_reload);
    await Future.wait([
      _bookFuture.catchError((_) => <WarehouseItem>[]),
      _comicFuture.catchError((_) => <WarehouseItem>[]),
      _videoFuture.catchError((_) => <WarehouseItem>[]),
      _musicFuture.catchError((_) => <WarehouseItem>[]),
    ]);
  }

  Future<List<WarehouseItem>> _loadBooks() async {
    final books = await BookshelfManager.getBookshelf();
    final now = DateTime.now().millisecondsSinceEpoch;

    final liveItems = books.asMap().entries.map((entry) {
      final index = entry.key;
      final book = entry.value;
      return WarehouseItem(
        id: _readString(book, 'id', fallback: 'book_$index'),
        title: _readString(book, 'title', fallback: '未命名书籍'),
        subtitle: _composeBookSubtitle(book),
        coverUrl: _readString(book, 'coverUrl'),
        detailUrl: _readString(book, 'detailUrl'),
        meta: _readString(book, 'intro'),
        category: WarehouseCategory.books,
        sourceLabel: '书架',
        createdAt: now - index,
        raw: book,
      );
    }).toList();

    final storedItems = await _store.load(WarehouseCategory.books);
    return _mergeItems(liveItems, storedItems);
  }

  List<WarehouseItem> _mergeItems(
    List<WarehouseItem> liveItems,
    List<WarehouseItem> storedItems,
  ) {
    final map = <String, WarehouseItem>{};
    for (final item in [...liveItems, ...storedItems]) {
      map.putIfAbsent(item.uniqueKey, () => item);
    }

    final list = map.values.toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  String _composeBookSubtitle(dynamic book) {
    final parts = <String>[
      _readString(book, 'author'),
      _readString(book, 'category'),
      _readString(book, 'status'),
    ].where((e) => e.trim().isNotEmpty).toList();

    return parts.join(' · ');
  }

  String _readString(dynamic target, String field, {String fallback = ''}) {
    try {
      final dynamic value = (target as dynamic)
          .toJson()
          .cast<String, dynamic>()[field];
      if (value == null) return fallback;
      final text = value.toString().trim();
      return text.isEmpty ? fallback : text;
    } catch (_) {
      try {
        final dynamic value = (target as dynamic)
            .toMap()
            .cast<String, dynamic>()[field];
        if (value == null) return fallback;
        final text = value.toString().trim();
        return text.isEmpty ? fallback : text;
      } catch (_) {
        try {
          final dynamic value = (target as dynamic).__getattribute__(field);
          if (value == null) return fallback;
          final text = value.toString().trim();
          return text.isEmpty ? fallback : text;
        } catch (_) {
          try {
            final dynamic value = (target as dynamic)[field];
            if (value == null) return fallback;
            final text = value.toString().trim();
            return text.isEmpty ? fallback : text;
          } catch (_) {
            return fallback;
          }
        }
      }
    }
  }

  Future<void> _showAddDialog(WarehouseCategory category) async {
    final titleController = TextEditingController();
    final subtitleController = TextEditingController();
    final coverController = TextEditingController();
    final detailController = TextEditingController();
    final metaController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Row(
            children: [
              CircleAvatar(
                backgroundColor: category.color.withValues(alpha: 0.12),
                child: Icon(category.icon, color: category.color),
              ),
              const SizedBox(width: 10),
              Text('新增${category.hubLabel}'),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.72,
            ),
            child: SizedBox(
              width: 420,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: titleController,
                        decoration: const InputDecoration(
                          labelText: '名称',
                          hintText: '请输入标题',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return '请输入标题';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: subtitleController,
                        decoration: const InputDecoration(
                          labelText: '副标题',
                          hintText: '作者 / 分类 / 导演 / 艺人',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: coverController,
                        decoration: const InputDecoration(
                          labelText: '封面地址',
                          hintText: 'https://...',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: detailController,
                        decoration: const InputDecoration(
                          labelText: '详情链接',
                          hintText: '可选',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: metaController,
                        decoration: const InputDecoration(
                          labelText: '备注',
                          hintText: '可填写简介、状态等信息',
                        ),
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.save_rounded),
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;

                final item = WarehouseItem(
                  id: '${category.name}_${DateTime.now().millisecondsSinceEpoch}',
                  title: titleController.text.trim(),
                  subtitle: subtitleController.text.trim(),
                  coverUrl: coverController.text.trim(),
                  detailUrl: detailController.text.trim(),
                  meta: metaController.text.trim(),
                  category: category,
                  sourceLabel: '手动收藏',
                  createdAt: DateTime.now().millisecondsSinceEpoch,
                );

                await _store.add(item);

                if (!mounted || !dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                setState(_reload);
                _showSnack('已添加到${category.label}');
              },
              label: const Text('保存收藏'),
            ),
          ],
        );
      },
    );

    titleController.dispose();
    subtitleController.dispose();
    coverController.dispose();
    detailController.dispose();
    metaController.dispose();
  }

  Future<void> _openItem(WarehouseItem item) async {
    if (item.category == WarehouseCategory.books && item.raw != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NovelDetailPage(entryBook: item.raw)),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: item.category.color.withValues(
                        alpha: 0.12,
                      ),
                      child: Icon(
                        item.category.icon,
                        color: item.category.color,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (item.subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    item.subtitle,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
                if (item.meta.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    item.meta,
                    style: TextStyle(color: Colors.grey.shade800, height: 1.45),
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (item.detailUrl.trim().isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: item.detailUrl),
                          );
                          if (!mounted || !sheetContext.mounted) return;
                          Navigator.pop(sheetContext);
                          _showSnack('链接已复制');
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('复制链接'),
                      ),
                    if (item.sourceLabel == '手动收藏')
                      OutlinedButton.icon(
                        onPressed: () async {
                          await _store.remove(item.category, item.uniqueKey);
                          if (!mounted || !sheetContext.mounted) return;
                          Navigator.pop(sheetContext);
                          setState(_reload);
                          _showSnack('已移出${item.category.label}');
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('删除'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _openVideoCenter() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const VideoListPage()),
    );
  }

  void _openNovelLibrary() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NovelListPageWithProvider()),
    );
  }

  void _showHubComingSoon(String title) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$title 会在下方分区持续收纳')));
  }

  Widget _buildTopCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFFE4EAF3)),
        boxShadow: AppTokens.shadowMd(color: AppTokens.primaryBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: AppTokens.emeraldGradient,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: AppTokens.emerald.withValues(alpha: 0.22),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.collections_bookmark_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '内容指挥台',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTokens.textPrimary,
                        fontSize: 25,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.6,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'CONTENT HUB · 首屏压缩',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTokens.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 42,
                height: 42,
                child: IconButton.filledTonal(
                  tooltip: '刷新',
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded, size: 21),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFEDEBFF),
                    foregroundColor: AppTokens.textPrimary,
                    shape: const CircleBorder(),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppTokens.emerald.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppTokens.emerald.withValues(alpha: 0.16),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.bolt_rounded, size: 18, color: AppTokens.emerald),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '内容入口 / 收藏库 / 四页导航统一',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTokens.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildHeaderMetricPill(
                  value: '4',
                  label: '内容入口',
                  icon: Icons.apps_rounded,
                  color: AppTokens.emerald,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildHeaderMetricPill(
                  value: '4',
                  label: '收藏库',
                  icon: Icons.folder_special_rounded,
                  color: AppTokens.primaryBlue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildHeaderMetricPill(
                  value: '书架',
                  label: '自动同步',
                  icon: Icons.sync_rounded,
                  color: AppTokens.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderMetricPill({
    required String value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      height: 58,
      padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTokens.textPrimary,
                  fontSize: 18,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTokens.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContentMatrix() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(
          title: '内容入口 · 优先操作区',
          subtitle: '影视搜索和小说书架放在首屏第一优先级',
          icon: Icons.dashboard_customize_rounded,
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: AppGradientActionCard(
                title: '影视搜索',
                subtitle: '聚合片源 · 播放历史',
                icon: Icons.smart_display_rounded,
                gradient: AppTokens.darkOceanGradient,
                onTap: _openVideoCenter,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppGradientActionCard(
                title: '小说书架',
                subtitle: '书源阅读 · 书架收藏',
                icon: Icons.auto_stories_rounded,
                gradient: AppTokens.sunsetGradient,
                onTap: _openNovelLibrary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: AppGradientActionCard(
                title: '漫画收藏',
                subtitle: '收藏夹 · 手动导入',
                icon: Icons.collections_bookmark_rounded,
                gradient: AppTokens.violetGradient,
                onTap: () => _showHubComingSoon('漫画收藏'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppGradientActionCard(
                title: '音乐收藏',
                subtitle: '歌单 · 历史 · 链接',
                icon: Icons.library_music_rounded,
                gradient: AppTokens.emeraldGradient,
                onTap: () => _showHubComingSoon('音乐收藏'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOverviewRow() {
    return FutureBuilder<List<List<WarehouseItem>>>(
      future: Future.wait([
        _bookFuture.catchError((_) => <WarehouseItem>[]),
        _comicFuture.catchError((_) => <WarehouseItem>[]),
        _videoFuture.catchError((_) => <WarehouseItem>[]),
        _musicFuture.catchError((_) => <WarehouseItem>[]),
      ]),
      builder: (context, snapshot) {
        final groups = snapshot.data ?? const <List<WarehouseItem>>[];
        final total = groups.fold<int>(0, (sum, items) => sum + items.length);
        final recent = groups.expand((items) => items).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final recentTitle = recent.isEmpty
            ? '暂无收藏，先导入一个资源'
            : recent.first.title;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Colors.white, Color(0xFFF8FBFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE7ECF5)),
            boxShadow: AppTokens.shadowSm(color: AppTokens.primaryBlue),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '收藏操作区',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppTokens.textPrimary,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          '最近收藏 / 快速导入 / 分类管理集中处理',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTokens.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTokens.emerald.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      snapshot.connectionState == ConnectionState.done
                          ? '$total 项'
                          : '加载中',
                      style: const TextStyle(
                        color: AppTokens.emerald,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: AppGradientActionCard(
                      title: '最近收藏',
                      subtitle: recentTitle,
                      icon: Icons.history_rounded,
                      gradient: AppTokens.violetGradient,
                      onTap: recent.isEmpty
                          ? null
                          : () => _openItem(recent.first),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppGradientActionCard(
                      title: '快速导入',
                      subtitle: '选择分类添加资源',
                      icon: Icons.add_link_rounded,
                      gradient: AppTokens.sunsetGradient,
                      onTap: _showCategoryPicker,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCategoryPicker() async {
    final category = await showModalBottomSheet<WarehouseCategory>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: WarehouseCategory.values.map((category) {
              return ListTile(
                leading: Icon(category.icon, color: category.color),
                title: Text(category.label),
                onTap: () => Navigator.pop(sheetContext, category),
              );
            }).toList(),
          ),
        );
      },
    );

    if (category != null) {
      await _showAddDialog(category);
    }
  }

  Widget _buildSection({
    required WarehouseCategory category,
    required Future<List<WarehouseItem>> future,
    required String emptyText,
  }) {
    return FutureBuilder<List<WarehouseItem>>(
      future: future,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState != ConnectionState.done;
        final items = snapshot.data ?? const <WarehouseItem>[];

        return Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(category.icon, size: 18, color: category.color),
                    const SizedBox(width: 8),
                    Text(
                      category.hubLabel,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!loading)
                      Text(
                        '${items.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    const Spacer(),
                    IconButton(
                      tooltip: '新增',
                      onPressed: () => _showAddDialog(category),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (loading)
                  const SizedBox(
                    height: 160,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snapshot.hasError)
                  _buildErrorBox()
                else if (items.isEmpty)
                  AppEmptyState(
                    title: '还没有${category.hubLabel}',
                    message: emptyText,
                    icon: category.icon,
                    actionLabel: category == WarehouseCategory.videos
                        ? '打开影视搜索'
                        : category == WarehouseCategory.books
                        ? '打开小说书架'
                        : '添加一个',
                    onAction: category == WarehouseCategory.videos
                        ? _openVideoCenter
                        : category == WarehouseCategory.books
                        ? _openNovelLibrary
                        : () => _showAddDialog(category),
                  )
                else
                  SizedBox(
                    height: 182,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return _WarehouseCard(
                          item: item,
                          onTap: () => _openItem(item),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorBox() {
    return Container(
      height: 160,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4F4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade300),
            const SizedBox(height: 8),
            Text(
              '加载失败',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.red.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F7FB),
        body: SafeArea(
          top: true,
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(
                16,
                14,
                16,
                AppTokens.pageBottomPadding + 32,
              ),
              children: [
                _buildTopCard(),
                const SizedBox(height: 16),
                _buildContentMatrix(),
                const SizedBox(height: 18),
                _buildOverviewRow(),
                const SizedBox(height: 18),
                const _WarehouseSectionHeader(
                  title: '收藏库',
                  subtitle: '我的书架 / 影视收藏 / 漫画收藏 / 音乐收藏',
                ),
                const SizedBox(height: 10),
                _buildSection(
                  category: WarehouseCategory.books,
                  future: _bookFuture,
                  emptyText: '从小说书架同步最近阅读，也可以手动收藏书籍链接',
                ),
                const SizedBox(height: 12),
                _buildSection(
                  category: WarehouseCategory.comics,
                  future: _comicFuture,
                  emptyText: '漫画资源会集中放在这里，方便后续扩展漫画入口',
                ),
                const SizedBox(height: 12),
                _buildSection(
                  category: WarehouseCategory.videos,
                  future: _videoFuture,
                  emptyText: '先去影视搜索发现内容，后续播放历史和收藏会聚合到这里',
                ),
                const SizedBox(height: 12),
                _buildSection(
                  category: WarehouseCategory.music,
                  future: _musicFuture,
                  emptyText: '音乐链接、歌单和历史记录会集中收纳到这里',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum WarehouseCategory { books, comics, videos, music }

extension WarehouseCategoryX on WarehouseCategory {
  String get label {
    switch (this) {
      case WarehouseCategory.books:
        return '书籍';
      case WarehouseCategory.comics:
        return '漫画';
      case WarehouseCategory.videos:
        return '影视';
      case WarehouseCategory.music:
        return '音乐';
    }
  }

  String get hubLabel {
    switch (this) {
      case WarehouseCategory.books:
        return '我的书架';
      case WarehouseCategory.comics:
        return '漫画收藏';
      case WarehouseCategory.videos:
        return '影视收藏';
      case WarehouseCategory.music:
        return '音乐收藏';
    }
  }

  IconData get icon {
    switch (this) {
      case WarehouseCategory.books:
        return Icons.auto_stories_outlined;
      case WarehouseCategory.comics:
        return Icons.collections_bookmark_outlined;
      case WarehouseCategory.videos:
        return Icons.movie_outlined;
      case WarehouseCategory.music:
        return Icons.library_music_outlined;
    }
  }

  Color get color {
    switch (this) {
      case WarehouseCategory.books:
        return Colors.orange;
      case WarehouseCategory.comics:
        return Colors.pink;
      case WarehouseCategory.videos:
        return Colors.indigo;
      case WarehouseCategory.music:
        return Colors.teal;
    }
  }
}

class WarehouseItem {
  const WarehouseItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.detailUrl,
    required this.meta,
    required this.category,
    required this.sourceLabel,
    required this.createdAt,
    this.raw,
  });

  final String id;
  final String title;
  final String subtitle;
  final String coverUrl;
  final String detailUrl;
  final String meta;
  final WarehouseCategory category;
  final String sourceLabel;
  final int createdAt;
  final dynamic raw;

  String get uniqueKey {
    final detail = detailUrl.trim();
    if (detail.isNotEmpty) return '${category.name}_$detail';
    return '${category.name}_${id.trim()}';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'coverUrl': coverUrl,
      'detailUrl': detailUrl,
      'meta': meta,
      'category': category.name,
      'sourceLabel': sourceLabel,
      'createdAt': createdAt,
    };
  }

  factory WarehouseItem.fromJson(Map<String, dynamic> json) {
    final categoryName = json['category']?.toString() ?? 'books';
    final category = WarehouseCategory.values.firstWhere(
      (e) => e.name == categoryName,
      orElse: () => WarehouseCategory.books,
    );

    return WarehouseItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      coverUrl: json['coverUrl']?.toString() ?? '',
      detailUrl: json['detailUrl']?.toString() ?? '',
      meta: json['meta']?.toString() ?? '',
      category: category,
      sourceLabel: json['sourceLabel']?.toString() ?? '手动收藏',
      createdAt: _asInt(
        json['createdAt'],
        DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

class WarehouseStore {
  WarehouseStore({CacheStore? cache})
    : _cache = cache ?? CacheStore(namespace: 'warehouse_center');

  final CacheStore _cache;

  String _key(WarehouseCategory category) => 'items_${category.name}';

  Future<List<WarehouseItem>> load(WarehouseCategory category) async {
    final raw = await _cache.read(_key(category));
    if (raw is! List) return const [];

    final list = <WarehouseItem>[];
    for (final item in raw) {
      if (item is Map) {
        try {
          list.add(WarehouseItem.fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {
          // ignore
        }
      }
    }

    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<void> save(
    WarehouseCategory category,
    List<WarehouseItem> items,
  ) async {
    final normalized = <WarehouseItem>[];
    final seen = <String>{};

    for (final item in items) {
      if (seen.add(item.uniqueKey)) {
        normalized.add(item);
      }
    }

    normalized.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _cache.write(
      _key(category),
      normalized.map((e) => e.toJson()).toList(),
    );
  }

  Future<void> add(WarehouseItem item) async {
    final list = await load(item.category);
    list.removeWhere((e) => e.uniqueKey == item.uniqueKey);
    list.insert(0, item);
    await save(item.category, list);
  }

  Future<void> remove(WarehouseCategory category, String key) async {
    final list = await load(category);
    list.removeWhere((e) => e.uniqueKey == key);
    await save(category, list);
  }
}

class _WarehouseSectionHeader extends StatelessWidget {
  const _WarehouseSectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppTokens.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppTokens.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WarehouseCard extends StatelessWidget {
  const _WarehouseCard({required this.item, required this.onTap});

  final WarehouseItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: SizedBox(
        width: 118,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: item.coverUrl.trim().isEmpty
                    ? _buildFallback()
                    : Image.network(
                        item.coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _buildFallback(),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              item.subtitle.trim().isNotEmpty
                  ? item.subtitle
                  : item.sourceLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallback() {
    return Container(
      color: const Color(0xFFE9ECEF),
      child: Center(
        child: Icon(item.category.icon, size: 32, color: Colors.grey.shade500),
      ),
    );
  }
}

int _asInt(dynamic value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}
