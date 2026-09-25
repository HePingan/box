// 系统分享进来的文件（286 P3）。
//
// 零 dart:io / Flutter 依赖：解析用例可以直接跑（同 monitor_models 的规矩）。
//
// 数据来自原生侧：`content://` 内容已被复制到应用缓存目录，这里拿到的是
// 真实路径 + 显示名 + 字节数 + mime。原生侧已经清洗过文件名与大小上限，
// 这里仍按"坏数据一律不采信"的惯例再挡一遍——跨进程传过来的结构不能假设可信。
library;

class SharedInboxFile {
  const SharedInboxFile({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.mimeType,
  });

  /// 缓存目录里的绝对路径（原生复制出来的中转文件）。
  final String path;

  /// 显示名（已清洗，不含路径分隔符）。
  final String name;

  final int sizeBytes;

  /// `image/jpeg`、`video/mp4` …… 拿不到时为空串。
  final String mimeType;

  static SharedInboxFile? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path'];
    final name = raw['name'];
    if (path is! String || path.isEmpty) return null;
    if (name is! String || name.isEmpty) return null;
    final size = raw['sizeBytes'];
    final mime = raw['mimeType'];
    return SharedInboxFile(
      path: path,
      name: name,
      sizeBytes: size is int ? (size < 0 ? 0 : size) : 0,
      mimeType: mime is String ? mime : '',
    );
  }

  /// 解析原生传来的列表。非列表 → 空；单条坏数据跳过（不整份作废：
  /// 分享 10 张图里有一张读不出来，剩下 9 张仍然该能传）。
  static List<SharedInboxFile> parseList(Object? raw) {
    if (raw is! List) return const <SharedInboxFile>[];
    final out = <SharedInboxFile>[];
    for (final item in raw) {
      final file = tryParse(item);
      if (file != null) out.add(file);
    }
    return out;
  }

  /// 是否视频（决定界面上用哪种图标/是否提示"大文件建议 Wi-Fi"）。
  bool get isVideo => mimeType.startsWith('video/');

  @override
  String toString() => 'SharedInboxFile($name, $sizeBytes, $mimeType)';
}
