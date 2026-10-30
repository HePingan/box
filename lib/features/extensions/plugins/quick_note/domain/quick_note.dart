/// 快速便签的领域模型与命名规则（纯函数，便于单测）。
///
/// 便签本体存在**远程存储**（WebDAV）的一个固定目录里，一条便签 = 一个 `.md`
/// 文件：
///
/// - 好处：用户在远程存储浏览器里也能看到/备份/批量导出它们，App 卸载也不丢；
/// - 代价：列表要联网，而 WebDAV 没有「批量读内容」的接口。所以**文件名里带标题
///   slug** —— 列表只凭文件名就能显示标题，不必为每条便签各拉一次体积。
///
/// 文件名格式固定为 `<yyyy-MM-dd-HHmm>-<标题 slug>.md`：前缀即时间戳，按文件名
/// 倒序就是「最新在前」，不用依赖服务端返回 modifiedAt（部分 WebDAV 实现不返回）。
library;

/// 便签目录（相对账户 baseUrl）。
const String kQuickNoteDir = 'box-notes';

/// 便签扩展名。用 `.md` 而不是 `.txt`：远程存储浏览器里有语法高亮预览，
/// 而内容是纯文本，两种都能打开。
const String kQuickNoteExtension = '.md';

/// 文件名里标题部分的最大字符数（太长在远程存储里难认，也易触服务端长度限制）。
const int kQuickNoteTitleMaxChars = 24;

/// 一条便签。
class QuickNote {
  const QuickNote({
    required this.name,
    required this.path,
    required this.title,
    this.body = '',
    this.modifiedAt,
    this.size = 0,
  });

  /// 文件名（含扩展名），如 `2026-10-30-2115-买牛奶.md`。
  final String name;

  /// 相对账户 baseUrl 的路径，如 `box-notes/2026-10-30-2115-买牛奶.md`。
  final String path;

  /// 展示用标题（由文件名推导；打开后可用正文首行覆盖）。
  final String title;

  /// 正文。列表态为空串（不预取），打开某条时才拉。
  final String body;

  final DateTime? modifiedAt;
  final int size;

  bool get hasBody => body.trim().isNotEmpty;

  QuickNote copyWith({String? title, String? body, int? size, DateTime? modifiedAt}) {
    return QuickNote(
      name: name,
      path: path,
      title: title ?? this.title,
      body: body ?? this.body,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      size: size ?? this.size,
    );
  }

  @override
  String toString() => 'QuickNote($path, title=$title, size=$size)';
}

/// 标题 → 文件名安全片段：去掉路径分隔符与常见非法字符，空白折叠成 `-`。
///
/// 刻意**保留中文**：便签是给人看的，转拼音或丢弃非 ASCII 会让文件名失去意义。
String quickNoteSlug(String title) {
  final cleaned = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  final chars = cleaned.runes.toList();
  if (chars.length <= kQuickNoteTitleMaxChars) return cleaned;
  return String.fromCharCodes(chars.take(kQuickNoteTitleMaxChars));
}

String _two(int v) => v.toString().padLeft(2, '0');

/// 时间前缀：`yyyy-MM-dd-HHmm`。
String quickNoteStamp(DateTime at) =>
    '${at.year}-${_two(at.month)}-${_two(at.day)}-${_two(at.hour)}${_two(at.minute)}';

/// 生成文件名；[existing] 里已有同名时追加 `-2`、`-3`…（同分钟内连写多条很常见）。
String buildQuickNoteFileName({
  required String title,
  DateTime? at,
  Set<String> existing = const {},
}) {
  final stamp = quickNoteStamp(at ?? DateTime.now());
  final slug = quickNoteSlug(title.trim());
  final base = slug.isEmpty ? '便签' : slug;
  var candidate = '$stamp-$base$kQuickNoteExtension';
  var n = 2;
  while (existing.contains(candidate)) {
    candidate = '$stamp-$base-$n$kQuickNoteExtension';
    n += 1;
    if (n > 999) break; // 兜底：别在病态数据上死循环
  }
  return candidate;
}

/// 正文 → 标题：取第一段非空文本的首行，按上限截断。
String quickNoteTitleFromBody(String body, {String fallback = '无标题'}) {
  for (final raw in body.split('\n')) {
    final line = raw.trim().replaceFirst(RegExp(r'^#{1,6}\s*'), '');
    if (line.isEmpty) continue;
    final chars = line.runes.toList();
    final text = chars.length <= kQuickNoteTitleMaxChars
        ? line
        : String.fromCharCodes(chars.take(kQuickNoteTitleMaxChars));
    return text.isEmpty ? fallback : text;
  }
  return fallback;
}

/// 文件名 → 标题：去掉扩展名与时间前缀，`-` 还原成空格。
///
/// 注意 `-` 还原是**有损**的（标题里本来就有的连字符会变成空格），这只影响列表
/// 展示；打开便签后标题会用正文首行重新算。
String quickNoteTitleFromFileName(String fileName) {
  var text = fileName;
  final lower = text.toLowerCase();
  // 与 isQuickNoteFileName 保持同一口径：.txt 也算便签，所以也要去扩展名
  for (final ext in const [kQuickNoteExtension, '.txt']) {
    if (lower.endsWith(ext)) {
      text = text.substring(0, text.length - ext.length);
      break;
    }
  }
  final stamp = RegExp(r'^\d{4}-\d{2}-\d{2}-\d{4}-');
  text = text.replaceFirst(stamp, '');
  text = text.replaceAll('-', ' ').trim();
  return text.isEmpty ? '无标题' : text;
}

/// 只看扩展名判断是不是便签（目录里可能混进用户的其它文件）。
bool isQuickNoteFileName(String fileName) {
  final lower = fileName.toLowerCase();
  return lower.endsWith(kQuickNoteExtension) || lower.endsWith('.txt');
}

/// 列表排序：文件名倒序（= 时间倒序），无需依赖服务端 modifiedAt。
int compareQuickNoteNames(String a, String b) => b.compareTo(a);

/// 人类可读大小（便签都很小，只到 KB 就够）。
String formatQuickNoteSize(int bytes) {
  if (bytes <= 0) return '空';
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
}
