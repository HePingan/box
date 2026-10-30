/// 动漫壁纸：清单模型与解析（纯函数，可单测）。
///
/// 壁纸是**自托管**的静态资源（`box.hpa888.top/updates/box/media/wallpapers/`），
/// 清单是一个 JSON：`{version, updatedAt, baseUrl, source, items:[…]}`。
///
/// 为什么自托管而不是实时调第三方随机图 API：
/// 1. 第三方随机接口给什么就是什么，质量、比例、内容都不可控（还会遇到图站被墙）；
/// 2. 自托管后每张图都经过人工筛（比例、清晰度、可用性），缩略图也是预生成的；
/// 3. App 端只依赖自己域名，不会被上游限流或下线拖死。
library;

import 'dart:convert';

/// 清单里 `file`/`thumb` 允许两种写法：相对文件名（拼 [baseUrl]）或完整 URL。
String joinWallpaperUrl(String baseUrl, String file) {
  final f = file.trim();
  if (f.isEmpty) return '';
  final lower = f.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) return f;
  final base = baseUrl.trim();
  if (base.isEmpty) return f;
  return base.endsWith('/') ? '$base$f' : '$base/$f';
}

class WallpaperItem {
  const WallpaperItem({
    required this.id,
    required this.title,
    required this.file,
    required this.thumb,
    this.tags = const [],
    this.width = 0,
    this.height = 0,
    this.bytes = 0,
  });

  final String id;
  final String title;
  final String file;
  final String thumb;
  final List<String> tags;
  final int width;
  final int height;
  final int bytes;

  String thumbUrl(String baseUrl) => joinWallpaperUrl(baseUrl, thumb);

  String fullUrl(String baseUrl) => joinWallpaperUrl(baseUrl, file);

  /// 「1896 × 2560」，未知时返回空串（宁可不显示，也不显示 0 × 0）。
  String get resolutionText =>
      (width > 0 && height > 0) ? '$width × $height' : '';

  /// 竖屏比例是否适合手机（仅用于展示排序/提示，不做过滤）。
  double get aspectRatio => (width > 0 && height > 0) ? height / width : 0;

  static WallpaperItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final file = (raw['file'] ?? '').toString().trim();
    if (file.isEmpty) return null;
    final id = (raw['id'] ?? '').toString().trim();
    final thumb = (raw['thumb'] ?? '').toString().trim();
    final tagsRaw = raw['tags'];
    final tags = <String>[
      if (tagsRaw is List)
        for (final t in tagsRaw)
          if (t.toString().trim().isNotEmpty) t.toString().trim(),
    ];
    return WallpaperItem(
      id: id.isEmpty ? file : id,
      title: (raw['title'] ?? '').toString().trim(),
      file: file,
      thumb: thumb.isEmpty ? file : thumb,
      tags: tags,
      width: int.tryParse('${raw['width'] ?? 0}') ?? 0,
      height: int.tryParse('${raw['height'] ?? 0}') ?? 0,
      bytes: int.tryParse('${raw['bytes'] ?? 0}') ?? 0,
    );
  }
}

class WallpaperManifest {
  const WallpaperManifest({
    required this.baseUrl,
    required this.items,
    this.version = 1,
    this.source = '',
    this.updatedAt = '',
  });

  final String baseUrl;
  final List<WallpaperItem> items;
  final int version;
  final String source;
  final String updatedAt;

  /// 清单里出现过的全部标签（去重、保持出现顺序），给筛选条用。
  List<String> get allTags {
    final seen = <String>{};
    final out = <String>[];
    for (final item in items) {
      for (final tag in item.tags) {
        if (seen.add(tag)) out.add(tag);
      }
    }
    return out;
  }

  /// 按标签筛选；[tag] 为空表示全部。
  List<WallpaperItem> filtered(String tag) {
    if (tag.isEmpty) return items;
    return [for (final i in items) if (i.tags.contains(tag)) i];
  }
}

class WallpaperManifestException implements Exception {
  const WallpaperManifestException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 解析清单。坏数据抛 [WallpaperManifestException]（带人话原因），
/// 但单条坏条目只跳过，不连累整张清单。
WallpaperManifest parseWallpaperManifest(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    throw const WallpaperManifestException('壁纸清单为空');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    throw const WallpaperManifestException('壁纸清单不是合法 JSON');
  }
  if (decoded is! Map) {
    throw const WallpaperManifestException('壁纸清单格式不对（应为对象）');
  }
  final list = decoded['items'];
  if (list is! List) {
    throw const WallpaperManifestException('壁纸清单缺少 items 数组');
  }
  final items = <WallpaperItem>[];
  for (final entry in list) {
    final item = WallpaperItem.fromJson(entry);
    if (item != null) items.add(item);
  }
  return WallpaperManifest(
    baseUrl: (decoded['baseUrl'] ?? '').toString(),
    items: items,
    version: int.tryParse('${decoded['version'] ?? 1}') ?? 1,
    source: (decoded['source'] ?? '').toString(),
    updatedAt: (decoded['updatedAt'] ?? '').toString(),
  );
}
