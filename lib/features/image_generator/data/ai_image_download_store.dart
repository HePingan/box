import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// AI 生图「下载到本地」落盘目录的管理。
///
/// 为什么需要它：下载流程把原图写到 `应用文档目录/box_downloads/ai_img_*.png`，
/// 再交给「保存到相册 / 分享」这两个动作。[Gal.putImage] 只是把文件**复制**进
/// 系统相册（MediaStore），源文件仍在应用私有目录里 —— 于是每下载一次就永久留一份。
/// 用户看不到它，设置里的「清理缓存」也清不到它（那不是缓存，是文档目录），
/// 只有卸载应用才会消失。
///
/// 这里把它收成一条明确的生命周期：
///   * 落盘统一走 [create]（文件名单调递增，不会同名覆盖）；
///   * 动作结束后走 [deleteQuietly] 删掉非用户可见的那份；
///   * 每次落盘顺手 [prune]，兜住「删失败 / 进程被杀」留下的残骸。
class AiImageDownloadStore {
  AiImageDownloadStore({Future<Directory> Function()? dirProvider})
    : _dirProvider = dirProvider ?? getApplicationDocumentsDirectory;

  /// 目录名保持不变：老版本留下的文件仍在同一处，[prune] 能一并收掉。
  static const String subdirName = 'box_downloads';

  /// 残骸上限：超过就删到 60%。宁可多留一点，也别每次下载都全扫一遍。
  static const int maxFiles = 40;
  static const int maxBytes = 80 * 1024 * 1024;

  /// [prune] 触发时保留的比例。
  static const double keepRatio = 0.6;

  final Future<Directory> Function() _dirProvider;

  Future<Directory> directory() async {
    final base = await _dirProvider();
    final dir = Directory('${base.path}/$subdirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 在 [box_downloads] 下新建一个空文件。
  ///
  /// 前缀保持老版本的 `ai_img_` / `ai_original_`，这样同一目录里混着旧文件时
  /// 命名习惯一致，[prune] 也不用挑名字。
  Future<File> create({String prefix = 'ai_img_', String suffix = '.png'}) async {
    final dir = await directory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final file = File('${dir.path}/$prefix$stamp$suffix');
    await file.create(recursive: true);
    return file;
  }

  /// 删除一份不再需要留在应用私有目录里的文件。
  ///
  /// 失败不抛：调用点在「已保存到相册」之后，删残留失败不该把成功说成失败。
  Future<void> deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // 已删 / 被占用：都不该让用户看到失败。
    }
  }

  /// 清空整个目录，返回释放的字节数（设置页「清理缓存」用）。
  ///
  /// 和 [prune] 的区别：prune 是「超限才收一部分」，这是用户主动要求全清。
  Future<int> clear() async {
    final dir = await directory();
    var freed = 0;
    await for (final item in dir.list()) {
      if (item is! File) continue;
      try {
        final size = await item.length();
        await item.delete();
        freed += size;
      } on FileSystemException {
        // 占用中 / 已删：跳过，别让一次清理卡在半路。
      }
    }
    return freed;
  }

  /// 把目录收在上限内（按修改时间，先删最旧），返回释放的字节数。
  Future<int> prune() async {
    final dir = await directory();
    final entries = <({File file, int size, DateTime modified})>[];
    await for (final item in dir.list()) {
      if (item is! File) continue;
      try {
        final stat = await item.stat();
        entries.add((file: item, size: stat.size, modified: stat.modified));
      } on FileSystemException {
        // 刚被别人删掉：跳过。
      }
    }

    var totalBytes = entries.fold<int>(0, (sum, e) => sum + e.size);
    if (entries.length <= maxFiles && totalBytes <= maxBytes) return 0;

    entries.sort((a, b) => a.modified.compareTo(b.modified));
    final fileFloor = (maxFiles * keepRatio).floor();
    final byteFloor = (maxBytes * keepRatio).floor();

    var remaining = entries.length;
    var freed = 0;
    for (final e in entries) {
      if (remaining <= fileFloor && totalBytes <= byteFloor) break;
      try {
        await e.file.delete();
        remaining -= 1;
        totalBytes -= e.size;
        freed += e.size;
      } on FileSystemException {
        // 占用中：下一轮再收。
      }
    }
    return freed;
  }
}
