// 列表缩略图的磁盘缓存（内存 LRU + 应用临时目录）。
//
// 为什么必须有磁盘缓存：缩略图**只能整张取回来**再降采样解码（JPEG/PNG 要完整
// 文件才能解），所以每张缩略图的网络代价等于原图。没有磁盘缓存的话，滚出去再滚
// 回来、进子目录再返回，都会重新下载一遍——用户流量白烧，体验还慢。
//
// 放在临时目录（getTemporaryDirectory）而不是应用数据目录：这是**缓存**，系统
// 空间紧张时可以回收，丢了也只是重新下载一次。
//
// 文件名用缓存键的 sha1：键里有路径（可能含中文、斜杠、长度不限），直接做文件名
// 不安全也不合法。

import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'package:box/utils/app_logger.dart';
import 'package:box/utils/log_channels.dart';

import '../domain/remote_storage_models.dart';

/// 缩略图缓存占用（283 D3）。
class ThumbnailCacheUsage {
  const ThumbnailCacheUsage({
    required this.files,
    required this.bytes,
    required this.memoryCount,
  });

  final int files;
  final int bytes;

  /// 内存里缓存的张数（不占磁盘，但也是"缓存"的一部分）。
  final int memoryCount;

  bool get isEmpty => files == 0 && memoryCount == 0;
}

class RemoteThumbnailCache {
  RemoteThumbnailCache({
    Directory? root,
    this.maxBytes = kThumbnailDiskMaxBytes,
    this.maxFiles = kThumbnailDiskMaxFiles,
    this.memoryEntries = kThumbnailMemoryEntries,
  }) : _rootOverride = root;

  /// 注入用（测试给临时目录）；生产为 null，落到临时目录下的子目录。
  final Directory? _rootOverride;
  final int maxBytes;
  final int maxFiles;
  final int memoryEntries;

  Directory? _root;
  bool _pruning = false;

  /// 内存 LRU：LinkedHashMap 的插入顺序即访问顺序（读到时先删再插实现"提级"）。
  final LinkedHashMap<String, Uint8List> _memory = LinkedHashMap();

  int get memoryCount => _memory.length;

  /// 内存里当前有哪些键（最久未使用的在前）——LRU 行为可观测，测试与排查都用它。
  List<String> get memoryKeys => _memory.keys.toList();

  /// 收集缓存目录下的全部文件（含作用域子目录；作用域只有一层）。
  ///
  /// 占用统计与修剪都必须走这里：只扫根目录的话，加了作用域之后
  /// 子目录里的图既不计入占用、也不会被淘汰——32MB 上限直接失效。
  Future<List<File>> _collectFiles(Directory dir) async {
    final files = <File>[];
    if (!await dir.exists()) return files;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) {
        files.add(entity);
      } else if (entity is Directory) {
        await for (final child in entity.list(followLinks: false)) {
          if (child is File) files.add(child);
        }
      }
    }
    return files;
  }

  Future<Directory> _dir() async {
    final cached = _root;
    if (cached != null) return cached;
    // 注入 root 时不碰 path_provider（单测直接构造即可，不需要平台通道）。
    final base =
        _rootOverride ??
        Directory('${(await getTemporaryDirectory()).path}/box_thumbs');
    if (!await base.exists()) await base.create(recursive: true);
    _root = base;
    return base;
  }

  /// 缓存键 → 文件名（sha1 十六进制，按 UTF-8 编码取摘要）。
  static String fileNameFor(String key) =>
      '${sha1.convert(utf8.encode(key))}.bin';

  /// 账户作用域 → 子目录名。
  ///
  /// 为什么要目录而不是把账户 id 编进文件名：磁盘文件名是键的 sha1（键里有中文
  /// 路径、斜杠、任意长度，只能取摘要），**从文件名反推不出账户**。删账户时想清掉
  /// 它留下的图，作用域就必须落在目录结构上，而不是文件名里。
  static String scopeDirName(String scope) =>
      sha1.convert(utf8.encode(scope)).toString();

  /// 键在磁盘上的位置：有作用域进子目录，无作用域直接落根目录（测试/无账户场景）。
  Future<File> _fileFor(String key, String? scope) async {
    final root = await _dir();
    if (scope == null || scope.isEmpty) {
      return File('${root.path}/${fileNameFor(key)}');
    }
    return File('${root.path}/${scopeDirName(scope)}/${fileNameFor(key)}');
  }

  /// 取：内存命中直接返回；否则读磁盘并把结果提进内存。
  ///
  /// [scope] 见 [_fileFor]；内存里始终用完整键（跨作用域也唯一）。
  Future<Uint8List?> get(String key, {String? scope}) async {
    final hit = _memory.remove(key);
    if (hit != null) {
      _memory[key] = hit;
      return hit;
    }
    try {
      final file = await _fileFor(key, scope);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      _remember(key, bytes);
      return bytes;
    } on FileSystemException catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '缩略图磁盘缓存读取失败: $e',
        level: LogLevel.debug,
      );
      return null;
    }
  }

  /// 存：内存 + 磁盘。磁盘写失败不影响本次显示（内存里已经有了）。
  Future<void> put(String key, Uint8List bytes, {String? scope}) async {
    if (bytes.isEmpty) return;
    _remember(key, bytes);
    try {
      final file = await _fileFor(key, scope);
      if (!await file.parent.exists()) await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: false);
      unawaitedPrune();
    } on FileSystemException catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '缩略图磁盘缓存写入失败: $e',
        level: LogLevel.debug,
      );
    }
  }

  void _remember(String key, Uint8List bytes) {
    _memory.remove(key);
    _memory[key] = bytes;
    while (_memory.length > memoryEntries) {
      _memory.remove(_memory.keys.first);
    }
  }

  /// 当前占用：磁盘文件数 + 总字节（外加内存张数）。
  ///
  /// 为什么要这个：缓存是"看不见的磁盘占用"。用户看到设置里有一个开关、
  /// 一个占用数字、一个清空按钮，才知道那 32MB 去哪了、能不能回收。
  Future<ThumbnailCacheUsage> usage() async {
    var files = 0;
    var bytes = 0;
    try {
      for (final file in await _collectFiles(await _dir())) {
        files += 1;
        bytes += await file.length();
      }
    } on FileSystemException catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '缩略图缓存占用统计失败: $e',
        level: LogLevel.debug,
      );
    }
    return ThumbnailCacheUsage(
      files: files,
      bytes: bytes,
      memoryCount: _memory.length,
    );
  }

  /// 只清内存（账户切换等场景）；磁盘缓存跨会话复用。
  void clearMemory() => _memory.clear();

  /// 清掉某个账户作用域下的缩略图（删账户时调用），返回清掉的**磁盘文件数**。
  ///
  /// 内存里的键保留了完整键（`thumbnailCacheKey` 以账户 id 开头，EXIF 变体是
  /// `...|exif`），按前缀过滤即可；磁盘靠作用域目录。返回值只数磁盘文件——
  /// "清了多少张图"对调用方才有意义，内存条目是顺带清掉的（它们本来就会被 LRU 淘汰）。
  Future<int> clearScope(String scope) async {
    final prefix = '$scope|';
    final keys = _memory.keys.where((k) => k.startsWith(prefix)).toList();
    for (final key in keys) {
      _memory.remove(key);
    }
    var removed = 0;
    try {
      final dir = Directory(
        '${(await _dir()).path}/${scopeDirName(scope)}',
      );
      if (await dir.exists()) {
        removed = (await _collectFiles(dir)).length;
        await dir.delete(recursive: true);
      }
    } on FileSystemException catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '清理账户缩略图失败（$scope）: $e',
        level: LogLevel.debug,
      );
    }
    return removed;
  }

  /// 清内存 + 磁盘（设置里的"清空缩略图缓存"）。
  Future<void> clear() async {
    _memory.clear();
    try {
      final dir = await _dir();
      if (await dir.exists()) await dir.delete(recursive: true);
      _root = null;
    } on FileSystemException catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '缩略图缓存清空失败: $e',
        level: LogLevel.warn,
      );
    }
  }

  /// 修剪：超过字节/文件数上限时按"最久未修改"先删。
  ///
  /// 不在 put 里 await（不阻塞 UI），但同一时刻只跑一个修剪任务。
  void unawaitedPrune() {
    if (_pruning) return;
    _pruning = true;
    Future<void>(() async {
      try {
        await prune();
      } finally {
        _pruning = false;
      }
    });
  }

  /// 供测试直接 await 的修剪实现。
  Future<void> prune() async {
    try {
      final files = await _collectFiles(await _dir());
      var total = 0;
      for (final file in files) {
        total += await file.length();
      }
      if (files.length <= maxFiles && total <= maxBytes) return;
      files.sort(
        (a, b) => (a.statSync().modified).compareTo(b.statSync().modified),
      );
      var remaining = files.length;
      for (final file in files) {
        if (remaining <= maxFiles && total <= maxBytes) break;
        try {
          final size = file.statSync().size;
          await file.delete();
          total -= size;
          remaining -= 1;
        } on FileSystemException {
          // 单个文件删不掉就跳过，别让修剪本身变成错误来源。
        }
      }
    } on FileSystemException catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '缩略图缓存修剪失败: $e',
        level: LogLevel.debug,
      );
    }
  }
}
