// 服务器运维插件：本机"下载缓存"管理（A8 下载残留清理）。
//
// 为什么要单独管一个子目录：
//   * 以前下载一律写 `getTemporaryDirectory()/原名`，同名覆盖、旧文件长期留着，
//     手机上表现为"空间莫名变少"；直接清空整个临时目录又会误删别的插件的文件。
//   * 所以下载统一落 `getTemporaryDirectory()/server_ops_downloads/`，清理入口
//     只动这个子目录。
//
// 与 host 页的「清缓存」区分：那份清的是**快照与历史**（shared_preferences），
// 这份清的是**本机下载的文件**（临时目录）。两者互不影响。
//
// [ServerOpsDownloadCache] 只依赖一个"给临时根目录"的函数，单测注入临时目录即可，
// 不碰 path_provider 的平台通道。

import 'dart:io';

import 'package:path_provider/path_provider.dart';

class ServerOpsDownloadCache {
  ServerOpsDownloadCache({Future<Directory> Function()? tempDirProvider})
      : _tempDir = tempDirProvider ?? getTemporaryDirectory;

  /// 下载落盘用的子目录名（临时目录下）。
  static const String subdirName = 'server_ops_downloads';

  final Future<Directory> Function() _tempDir;

  /// 下载缓存目录（不存在则创建）。
  Future<Directory> directory() async {
    final base = await _tempDir();
    final dir = Directory('${base.path}/$subdirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 准备下载目标文件：**先删掉同名旧文件**再返回路径。
  ///
  /// 为什么必须删：旧文件可能是上一次下了一半的残留，被应用打开时会看到
  /// "能打开但内容是坏的"包；删掉后由本次下载从头写。
  Future<File> prepare(String name) async {
    final dir = await directory();
    final dest = File('${dir.path}/$name');
    if (await dest.exists()) {
      await dest.delete();
    }
    return dest;
  }

  /// 清空下载缓存（删掉整个子目录再重建），返回释放的字节数（用于提示）。
  Future<int> clear() async {
    final dir = await directory();
    var bytes = 0;
    if (await dir.exists()) {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          bytes += await entity.length();
        }
      }
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
    return bytes;
  }
}
