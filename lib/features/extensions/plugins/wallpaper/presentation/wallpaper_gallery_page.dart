// 动漫壁纸图库：竖屏壁纸墙 + 单张预览 + 保存到相册。
//
// 壁纸是自托管在 box.hpa888.top 的静态文件（见 wallpaper/domain 顶部的说明），
// 每张都预生成了缩略图，所以列表滚动不会整屏拉原图。
//
// 形状与前几个插件一致：数据源、保存动作都可注入，失败**写出原因**。
library;

import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_back_button.dart';
import 'package:box/features/extensions/market/domain/plugin_market_stats.dart'
    show formatPackageSize;

import '../data/wallpaper_api.dart';
import '../domain/wallpaper_item.dart';

WallpaperSource _runtimeSource = WallpaperApi();
WallpaperSaver? _runtimeSaver;

void debugSetWallpaperRuntime({
  WallpaperSource? source,
  WallpaperSaver? saver,
}) {
  _runtimeSource = source ?? WallpaperApi();
  _runtimeSaver = saver;
}

WallpaperSource get debugWallpaperSource => _runtimeSource;

class WallpaperGalleryPage extends StatefulWidget {
  const WallpaperGalleryPage({super.key});

  @override
  State<WallpaperGalleryPage> createState() => _WallpaperGalleryPageState();
}

class _WallpaperGalleryPageState extends State<WallpaperGalleryPage> {
  WallpaperManifest? _manifest;
  bool _loading = true;
  String _error = '';
  String _tag = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final manifest = await _runtimeSource.load();
      if (!mounted) return;
      setState(() {
        _manifest = manifest;
        _loading = false;
        // 之前选的标签在新清单里可能不存在了
        if (_tag.isNotEmpty && !manifest.allTags.contains(_tag)) _tag = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _save(WallpaperItem item) async {
    final manifest = _manifest;
    if (manifest == null) return;
    final saver = _runtimeSaver;
    try {
      if (saver != null) {
        await saver(item);
      } else {
        await saveWallpaperToGallery(item, manifest.baseUrl);
      }
      if (!mounted) return;
      _toast('已保存到相册：${item.title}');
    } catch (e) {
      if (!mounted) return;
      _toast('保存失败：$e');
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _openDetail(WallpaperItem item) {
    final manifest = _manifest;
    if (manifest == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _WallpaperDetailPage(
          item: item,
          baseUrl: manifest.baseUrl,
          source: manifest.source,
          onSave: () => _save(item),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final manifest = _manifest;
    final items = manifest?.filtered(_tag) ?? const <WallpaperItem>[];
    return Scaffold(
      backgroundColor: AppTokens.background,
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
                    '动漫壁纸',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (manifest != null)
                    Text(
                      '${items.length} 张',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTokens.textSecondary,
                      ),
                    ),
                  IconButton(
                    tooltip: '刷新',
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh, size: 20),
                  ),
                ],
              ),
            ),
            if (manifest != null && manifest.allTags.isNotEmpty)
              _tagBar(manifest.allTags),
            Expanded(child: _body(items)),
          ],
        ),
      ),
    );
  }

  Widget _tagBar(List<String> tags) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final tag in <String>['', ...tags])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(tag.isEmpty ? '全部' : tag),
                selected: _tag == tag,
                onSelected: (_) => setState(() => _tag = tag),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body(List<WallpaperItem> items) {
    if (_loading && _manifest == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.image_not_supported_outlined,
                  size: 40, color: AppTokens.rose),
              const SizedBox(height: 12),
              Text(_error, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    final manifest = _manifest;
    if (manifest == null || manifest.items.isEmpty) {
      return Center(
        child: Text('清单里还没有壁纸', style: TextStyle(color: AppTokens.textSecondary)),
      );
    }
    if (items.isEmpty) {
      return Center(
        child: Text('这个标签下没有壁纸',
            style: TextStyle(color: AppTokens.textSecondary)),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.62,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
          return _WallpaperCard(
            item: item,
            baseUrl: manifest.baseUrl,
            onTap: () => _openDetail(item),
          );
        },
      ),
    );
  }
}

class _WallpaperCard extends StatelessWidget {
  const _WallpaperCard({
    required this.item,
    required this.baseUrl,
    required this.onTap,
  });

  final WallpaperItem item;
  final String baseUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final url = item.thumbUrl(baseUrl);
    return Material(
      color: AppTokens.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              url,
              fit: BoxFit.cover,
              // 缩略图很小，但弱网下仍会给个可见的占位，而不是黑块
              loadingBuilder: (ctx, child, progress) => progress == null
                  ? child
                  : Container(
                      color: const Color(0xFFE5E7EB),
                      alignment: Alignment.center,
                      child: const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
              errorBuilder: (ctx, error, stack) => Container(
                color: const Color(0xFFE5E7EB),
                alignment: Alignment.center,
                child: Icon(Icons.broken_image_outlined,
                    color: AppTokens.textTertiary),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 16, 10, 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xCC000000)],
                  ),
                ),
                child: Text(
                  item.title.isEmpty ? item.id : item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WallpaperDetailPage extends StatefulWidget {
  const _WallpaperDetailPage({
    required this.item,
    required this.baseUrl,
    required this.source,
    required this.onSave,
  });

  final WallpaperItem item;
  final String baseUrl;
  final String source;
  final Future<void> Function() onSave;

  @override
  State<_WallpaperDetailPage> createState() => _WallpaperDetailPageState();
}

class _WallpaperDetailPageState extends State<_WallpaperDetailPage> {
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final size = formatPackageSize(item.bytes);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(item.title.isEmpty ? item.id : item.title),
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              maxScale: 4,
              child: Center(
                child: Image.network(
                  item.fullUrl(widget.baseUrl),
                  fit: BoxFit.contain,
                  loadingBuilder: (ctx, child, progress) => progress == null
                      ? child
                      : const Center(child: CircularProgressIndicator()),
                  errorBuilder: (ctx, error, stack) => const Center(
                    child: Text(
                      '这张图加载失败，检查网络后重试',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            color: AppTokens.surface,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    if (item.resolutionText.isNotEmpty) item.resolutionText,
                    if (size.isNotEmpty) size,
                    ...item.tags,
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: AppTokens.textSecondary),
                ),
                if (widget.source.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.source,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTokens.textTertiary,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded, size: 18),
                    label: Text(_saving ? '正在保存…' : '保存到相册'),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '保存后在系统相册/壁纸设置里选它即可。',
                  style: TextStyle(fontSize: 11, color: AppTokens.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
