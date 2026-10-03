import '../models/video_source.dart';

/// 按「历史/续播记录」找回片源对象。
///
/// 为什么不能只比 id：目录 JSON 里**没有 id 字段**（`VideoSource.fromJson` 的
/// 兜底是 `url`），所以源的 id 就是它的接口地址。上游目录改过一次地址，
/// 这条源在本地历史里就再也匹配不上，界面只会说「该视频的片源已失效或被移除」
/// —— 片源其实好得很，是 id 漂了。名字通常不变，兜一层归一化名字匹配能把
/// 这一整类误报救回来。
///
/// 匹配顺序：精确 id → url/detailUrl → 归一化名字（唯一命中才算）。
VideoSource? findVideoSourceForHistory(
  List<VideoSource> sources, {
  required String sourceId,
  String sourceName = '',
}) {
  final id = sourceId.trim();
  if (id.isNotEmpty) {
    for (final source in sources) {
      if (source.id == id) return source;
    }
    for (final source in sources) {
      if (source.url == id || source.detailUrl == id) return source;
    }
  }

  final wanted = normalizeSourceName(sourceName);
  if (wanted.isEmpty) return null;
  VideoSource? hit;
  for (final source in sources) {
    if (normalizeSourceName(source.name) != wanted) continue;
    // 同名多个（目录里偶有重复）时不要乱猜：认第一条之外的就算歧义，交给调用方报错。
    if (hit != null) return null;
    hit = source;
  }
  return hit;
}

/// 归一化片源名：目录里的名字带装饰符（`🎬量子资源`、`-爱奇艺-`），而历史里存的
/// 可能是同一名字的不同写法（emoji 掉了、多了空格或括号）。比较时只保留字母、
/// 数字与中日韩字符，其余（emoji/标点/空白）一律丢弃，并统一小写。
String normalizeSourceName(String raw) {
  final buffer = StringBuffer();
  for (final rune in raw.runes) {
    final ch = String.fromCharCode(rune);
    if (_nameKept.hasMatch(ch)) {
      buffer.write(ch.toLowerCase());
    }
  }
  return buffer.toString();
}

final RegExp _nameKept = RegExp(r'[0-9a-zA-Z\u4e00-\u9fff\u3040-\u30ff]');

/// 归一化剧集名，用于**跨源续播**：新源的剧集地址必然不同，只能比名字。
///
/// 除了丢掉装饰符（`【HD中字】` 这类括号、emoji），还要**吃掉数字的前导零** ——
/// 同一集，不同采集站会写成 `第03集` / `第3集` / `03`，不比归一化就会漏掉。
String normalizeEpisodeName(String raw) {
  final base = normalizeSourceName(raw);
  if (base.isEmpty) return '';
  return base.replaceAllMapped(RegExp(r'0+(\d)'), (m) => m.group(1)!);
}
