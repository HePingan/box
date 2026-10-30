/// 影视「稍后看」的领域模型与清单序列化（纯函数，可单测）。
///
/// 清单是远程存储里的**一个 JSON 文件** `box-watchlist/watch-later.json`：
///
/// ```json
/// {"version":1,"items":[{"url":"…","title":"…","sourceName":"…","addedAt":1761…,"note":""}]}
/// ```
///
/// 为什么是一个文件而不是一条一个文件：稍后看是**列表**，要按添加时间倒序展示、
/// 要能整体增删。一个文件 = 一次读、一次写；一条一个文件则每次列表都要列目录 +
/// 逐条读内容（WebDAV 没有批量读）。代价是两台设备同时写会互相覆盖 —— 记录在案，
/// 单用户场景可接受。
library;

import 'dart:convert';

/// 清单文件名（相对账户 baseUrl）。
const String kWatchLaterPath = 'box-watchlist/watch-later.json';

/// 清单版本，便于以后迁移字段。
const int kWatchLaterVersion = 1;

class WatchLaterItem {
  const WatchLaterItem({
    required this.url,
    required this.title,
    this.sourceName = '',
    this.addedAtMs = 0,
    this.note = '',
  });

  /// 播放地址（也可能是云播页地址，播放器会自己解析）。**同时是唯一键**：
  /// 同一地址重复添加不该出现两条。
  final String url;
  final String title;

  /// 来源站点/来源名，仅用于展示。
  final String sourceName;

  /// 添加时间（毫秒时间戳）。0 表示历史数据没带。
  final int addedAtMs;

  final String note;

  DateTime? get addedAt => addedAtMs <= 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(addedAtMs);

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        if (sourceName.isNotEmpty) 'sourceName': sourceName,
        'addedAt': addedAtMs,
        if (note.isNotEmpty) 'note': note,
      };

  static WatchLaterItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final url = (raw['url'] ?? '').toString().trim();
    if (!isPlayableWatchLaterUrl(url)) return null;
    final title = (raw['title'] ?? '').toString().trim();
    return WatchLaterItem(
      url: url,
      title: title.isEmpty ? watchLaterTitleFromUrl(url) : title,
      sourceName: (raw['sourceName'] ?? '').toString().trim(),
      addedAtMs: int.tryParse('${raw['addedAt'] ?? 0}') ?? 0,
      note: (raw['note'] ?? '').toString().trim(),
    );
  }

  WatchLaterItem copyWith({String? title, String? sourceName, int? addedAtMs}) =>
      WatchLaterItem(
        url: url,
        title: title ?? this.title,
        sourceName: sourceName ?? this.sourceName,
        addedAtMs: addedAtMs ?? this.addedAtMs,
        note: note,
      );

  @override
  String toString() => 'WatchLaterItem($url, title=$title)';
}

/// 只接受 http(s)：清单来自外部（远程存储里任何人可写的文件、市场插件 payload），
/// 不能成为 `file://`、`javascript:` 这类地址的入口。
bool isPlayableWatchLaterUrl(String url) {
  final text = url.trim();
  final lower = text.toLowerCase();
  if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
    return false;
  }
  return text.length > (lower.startsWith('https://') ? 8 : 7);
}

/// 没给标题时从地址里推一个：取最后一段路径（去掉扩展名与查询串），
/// 推不出来就用主机名 —— 总比列表里一排「未命名」强。
String watchLaterTitleFromUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return '未命名';
  final segments = uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
  if (segments.isNotEmpty) {
    // Uri.pathSegments **已经解码**过；再 decodeComponent 一次会在中文路径上抛
    // 「Illegal percent encoding」（实测：`https://a.com/movie/流浪地球.mp4`）。
    // 只在明显还是百分号编码（含 '%'）时才补一次，且失败就用手上的原值。
    var last = segments.last;
    if (last.contains('%')) {
      try {
        last = Uri.decodeComponent(last);
      } catch (_) {
        // 保持原样：宁可标题里带 %E4%B8 也不要在加载清单时抛异常
      }
    }
    // 影视站常见 .m3u8/.mp4 后缀，标题里不需要
    last = last.replaceFirst(RegExp(r'\.(m3u8|mp4|flv|mkv|ts)$', caseSensitive: false), '');
    last = last.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    if (last.isNotEmpty) return last;
  }
  return uri.host.isNotEmpty ? uri.host : '未命名';
}

/// 解析清单文档；坏数据不抛异常（远程存储里的文件可能被别的工具改坏）。
List<WatchLaterItem> parseWatchLaterDoc(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return const [];
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    return const [];
  }
  final list = switch (decoded) {
    List<Object?> l => l,
    Map<String, dynamic> m when m['items'] is List => m['items'] as List<Object?>,
    _ => const <Object?>[],
  };
  final items = <WatchLaterItem>[];
  final seen = <String>{};
  for (final raw in list) {
    final item = WatchLaterItem.fromJson(raw);
    if (item == null) continue;
    if (!seen.add(item.url)) continue; // 去重：同一地址只留第一条
    items.add(item);
  }
  sortWatchLater(items);
  return items;
}

/// 序列化成清单文档。
String encodeWatchLaterDoc(List<WatchLaterItem> items) => jsonEncode({
      'version': kWatchLaterVersion,
      'items': [for (final i in items) i.toJson()],
    });

/// 按添加时间倒序（没有时间的排后面，再按标题稳定排序避免抖动）。
void sortWatchLater(List<WatchLaterItem> items) {
  items.sort((a, b) {
    final byTime = b.addedAtMs.compareTo(a.addedAtMs);
    if (byTime != 0) return byTime;
    return a.title.compareTo(b.title);
  });
}

/// 添加（同地址已存在则更新标题并提到最前）；返回新列表，不改入参。
List<WatchLaterItem> addWatchLater(
  List<WatchLaterItem> current,
  WatchLaterItem item,
) {
  final rest = current.where((e) => e.url != item.url).toList();
  final merged = <WatchLaterItem>[item, ...rest];
  sortWatchLater(merged);
  return merged;
}

/// 删除；返回新列表。
List<WatchLaterItem> removeWatchLater(
  List<WatchLaterItem> current,
  String url,
) =>
    current.where((e) => e.url != url).toList();

/// 从插件 payload 里取「要加入的地址」。
///
/// 支持两种写法（与 openMusic 的 payload 习惯一致）：
/// ```text
/// https://example.com/v/123          // 整串当 URL
/// {"url":"https://…","title":"…"}    // 带标题
/// ```
/// 解析不出来返回 null（调用方当「没给参数」处理，不当错误）。
({String url, String title})? parseWatchLaterPayload(String? payload) {
  final text = (payload ?? '').trim();
  if (text.isEmpty) return null;
  if (text.startsWith('{')) {
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final url = (decoded['url'] ?? decoded['link'] ?? decoded['href'] ?? '')
        .toString()
        .trim();
    if (!isPlayableWatchLaterUrl(url)) return null;
    final title = (decoded['title'] ?? decoded['name'] ?? '').toString().trim();
    return (url: url, title: title);
  }
  if (!isPlayableWatchLaterUrl(text)) return null;
  return (url: text, title: '');
}

/// 展示用主机名（卡片副标题）。
String watchLaterHostOf(String url) {
  final uri = Uri.tryParse(url.trim());
  final host = uri?.host ?? '';
  return host.isEmpty ? url : host;
}
