import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/app_tokens.dart';
import '../../design_system/widgets/empty_error_states.dart';
import '../core/models.dart';
import '../core/offline_book_info.dart';
import '../core/offline_cache_service.dart';
import '../novel_module.dart';
import 'novel_detail_page.dart';

/// 离线缓存管理页面
///
/// 展示所有已标记离线缓存的书籍及其缓存状态（章节数、估算大小），
/// 支持单个/批量删除缓存、刷新统计。
class OfflineCacheManagePage extends StatefulWidget {
  const OfflineCacheManagePage({super.key});

  @override
  State<OfflineCacheManagePage> createState() => _OfflineCacheManagePageState();
}

class _OfflineCacheManagePageState extends State<OfflineCacheManagePage> {
  List<OfflineBookInfo> _books = [];
  bool _loading = true;

  OfflineCacheService get _service => OfflineCacheService(
        cache: NovelModule.repository.cache,
        repository: NovelModule.repository,
      );

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final books = await _service.getOfflineBookInfos();
      if (mounted) {
        setState(() {
          _books = books;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmClearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除全部缓存'),
        content: const Text('将清除所有离线标记和已缓存的章节数据，确定继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTokens.danger),
            child: const Text('清除全部'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _service.clearAllWithChapters();
      if (mounted) setState(() => _books = []);
    }
  }

  Future<void> _removeBook(OfflineBookInfo book) async {
    await _service.unmarkOfflineById(book.id);
    await _service.clearCacheById(book.id);
    if (mounted) {
      setState(() => _books.removeWhere((b) => b.id == book.id));
    }
  }

  void _openDetail(OfflineBookInfo book) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NovelDetailPage(
          entryBook: NovelBook(
            id: book.id,
            title: book.title ?? '未知',
            author: book.author ?? '',
            intro: '',
            coverUrl: book.coverUrl ?? '',
            detailUrl: book.id,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('离线缓存管理'),
        leading: const BackButton(),
        actions: [
          if (_books.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              tooltip: '刷新统计',
              onPressed: _loading ? null : _loadData,
            ),
            IconButton(
              icon: Icon(
                Icons.delete_sweep_rounded,
                size: 20,
                color: AppTokens.danger,
              ),
              tooltip: '清除全部',
              onPressed: _loading ? null : _confirmClearAll,
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_books.isEmpty) {
      return const EmptyStateView(
        icon: Icons.download_rounded,
        title: '暂无离线缓存',
        subtitle: '在书架中长按书籍选择"离线缓存"',
      );
    }

    final totalCached = _books.fold<int>(
        0, (sum, b) => sum + (b.cachedChapters > 0 ? b.cachedChapters : 0));
    final totalBooks = _books.length;
    final totalSize = _books.fold<int>(0, (sum, b) => sum + b.estimatedBytes);

    return Column(
      children: [
        // 统计栏
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTokens.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTokens.divider),
          ),
          child: Row(
            children: [
              Icon(Icons.storage_rounded, size: 18, color: AppTokens.violet),
              const SizedBox(width: 8),
              Text(
                '共 $totalBooks 本',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '缓存 $totalCached 章',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTokens.textSecondary,
                ),
              ),
              if (totalSize > 0) ...[
                const SizedBox(width: 12),
                Text(
                  _formatSize(totalSize),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTokens.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        // 书籍列表
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadData,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: _books.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, index) => _buildBookTile(_books[index]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBookTile(OfflineBookInfo book) {
    final isCounted = book.cachedChapters >= 0;
    final isFullyCached =
        book.cachedChapters > 0 && book.cachedChapters >= book.totalChapters;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppTokens.divider),
      ),
      color: AppTokens.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetail(book),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 封面
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 48,
                  height: 64,
                  child: book.coverUrl != null && book.coverUrl!.isNotEmpty
                      ? Image.network(
                          book.coverUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _coverPlaceholder(),
                          loadingBuilder: (_, child, progress) =>
                              progress == null ? child : _coverPlaceholder(),
                        )
                      : _coverPlaceholder(),
                ),
              ),
              const SizedBox(width: 12),
              // 文字信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title ?? '未知书名',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      book.author ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTokens.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildCacheStatusLine(book, isCounted, isFullyCached),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 操作按钮
              SizedBox(
                height: 32,
                child: TextButton(
                  onPressed: () => _removeBook(book),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTokens.danger,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: Size.zero,
                    textStyle: const TextStyle(fontSize: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                          color: AppTokens.danger.withValues(alpha: 0.3)),
                    ),
                  ),
                  child: const Text('清除'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCacheStatusLine(
    OfflineBookInfo book,
    bool isCounted,
    bool isFullyCached,
  ) {
    if (!isCounted) {
      return Row(
        children: [
          Icon(Icons.hourglass_empty_rounded,
              size: 12, color: AppTokens.textTertiary),
          const SizedBox(width: 4),
          Text(
            '加载状态中…',
            style: TextStyle(fontSize: 11, color: AppTokens.textTertiary),
          ),
        ],
      );
    }

    if (book.cachedChapters == 0) {
      return Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 12, color: AppTokens.amber),
          const SizedBox(width: 4),
          Text(
            '等待缓存…',
            style: TextStyle(fontSize: 11, color: AppTokens.amber),
          ),
        ],
      );
    }

    final color = isFullyCached ? AppTokens.emerald : AppTokens.primaryBlue;
    return Row(
      children: [
        Icon(
          isFullyCached
              ? Icons.download_done_rounded
              : Icons.downloading_rounded,
          size: 12,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          '${book.cachedChapters}/${book.totalChapters} 章',
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600),
        ),
        if (book.estimatedBytes > 0) ...[
          const SizedBox(width: 6),
          Text(
            _formatSize(book.estimatedBytes),
            style: TextStyle(fontSize: 10, color: AppTokens.textTertiary),
          ),
        ],
      ],
    );
  }

  Widget _coverPlaceholder() {
    return Container(
      color: AppTokens.surfaceMuted,
      child: Icon(Icons.book_rounded, size: 24, color: AppTokens.textTertiary),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
