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

  /// 是否图片。
  bool get isImage => mimeType.startsWith('image/');

  /// 是否分享来的纯文本/链接（287 D3：原生把它落成了 .txt）。
  bool get isText => mimeType.startsWith('text/');

  @override
  String toString() => 'SharedInboxFile($name, $sizeBytes, $mimeType)';
}

/// 没收到的一条分享，以及为什么（287 P2）。
///
/// 以前原生只把**成功那批**交给 Dart，界面就说"收到 20 个"——分享里其实有 25 个
/// 的时候用户永远看不出来（静默截断）。现在每个没收到的都带名字与原因。
class SkippedShare {
  const SkippedShare({required this.name, required this.reason});

  /// 原始显示名（可能为空 → 展示时给占位）。
  final String name;

  /// 原因代号：`tooMany` / `tooLarge` / `unreadable` / `unsupported` / 其它。
  final String reason;

  static SkippedShare? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final reason = raw['reason'];
    if (reason is! String || reason.isEmpty) return null;
    final name = raw['name'];
    return SkippedShare(
      name: name is String ? name : '',
      reason: reason,
    );
  }

  String get displayName => name.isEmpty ? '未命名文件' : name;

  String get reasonLabel => shareSkipReasonLabel(reason);

  @override
  String toString() => 'SkippedShare($displayName, $reason)';
}

/// 原因代号 → 中文。认识的全写清，不认识的也给一句能看的话。
String shareSkipReasonLabel(String reason) {
  switch (reason) {
    case 'tooMany':
      return '超过单次数量上限';
    case 'tooLarge':
      return '超过单文件大小上限';
    case 'unreadable':
      return '读不出来';
    case 'unsupported':
      return '类型不支持';
    default:
      return '没有收到';
  }
}

/// 一次分享的整包：收到哪些文件 + 诚实计数。
///
/// 解析同时认两种形状：
///   * **新形状**（287）：`{files: [...], total: 25, received: 20, skipped: [...]}`；
///   * **旧形状**（286 的包）：一个裸列表 `[...]` → 当成 total == received、无丢失。
/// 这样新装的包读老原生、或反过来，都不会炸。
class ShareInboxBatch {
  const ShareInboxBatch({
    required this.files,
    required this.total,
    required this.skipped,
  });

  static const ShareInboxBatch empty = ShareInboxBatch(
    files: <SharedInboxFile>[],
    total: 0,
    skipped: <SkippedShare>[],
  );

  final List<SharedInboxFile> files;

  /// 这次分享里**一共**几个（含没收到的）。
  final int total;

  final List<SkippedShare> skipped;

  /// 实际收到几个。
  int get received => files.length;

  bool get isEmpty => files.isEmpty && skipped.isEmpty;

  /// 有没有"丢了东西"：收到了 20 个但分享里有 25 个，或者有明确的跳过记录。
  bool get hasLosses => skipped.isNotEmpty || total > received;

  /// 一句话说清"分享几个、收到几个、丢了什么"。
  ///
  /// 没有丢失时只说收到几个（别给用户制造无谓的疑问）。
  String get summaryLabel {
    if (!hasLosses) return '收到 $received 个分享文件';
    final buffer = StringBuffer('分享 $total 个，收到 $received 个');
    if (skipped.isNotEmpty) {
      final counts = <String, int>{};
      for (final item in skipped) {
        counts[item.reasonLabel] = (counts[item.reasonLabel] ?? 0) + 1;
      }
      final parts = counts.entries
          .map((entry) => '${entry.value} 个${entry.key}')
          .toList();
      buffer.write('（${parts.join('、')}）');
    }
    return buffer.toString();
  }

  /// 容错解析：结构不对就当空（不整份作废的原则只作用于单条）。
  static ShareInboxBatch parse(Object? raw) {
    if (raw is List) {
      // 旧形状：裸列表。
      final files = SharedInboxFile.parseList(raw);
      return ShareInboxBatch(
        files: files,
        total: files.length,
        skipped: const <SkippedShare>[],
      );
    }
    if (raw is! Map) return empty;

    final files = SharedInboxFile.parseList(raw['files']);
    final skipped = <SkippedShare>[];
    final rawSkipped = raw['skipped'];
    if (rawSkipped is List) {
      for (final item in rawSkipped) {
        final parsed = SkippedShare.tryParse(item);
        if (parsed != null) skipped.add(parsed);
      }
    }

    final rawTotal = raw['total'];
    var total = rawTotal is int && rawTotal >= 0 ? rawTotal : files.length;
    // 计数不能自相矛盾：总数至少是"收到的 + 明确跳过的"。
    final floor = files.length + skipped.length;
    if (total < floor) total = floor;

    return ShareInboxBatch(files: files, total: total, skipped: skipped);
  }
}
