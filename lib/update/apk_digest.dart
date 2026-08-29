import 'dart:io';

import 'package:crypto/crypto.dart';

/// 收集分块摘要结果的最小 sink。
///
/// 不用 `package:convert` 的 `AccumulatorSink`：那个包在本工程只是 transitive
/// 依赖，直接 import 属于未声明依赖，升级时会莫名断掉。这里几行就够。
class _DigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value {
    final v = _value;
    if (v == null) throw StateError('摘要尚未完成');
    return v;
  }

  @override
  void add(Digest data) => _value = data;

  @override
  void close() {}
}

/// 流式计算文件 SHA-256。
///
/// 为什么不用 `file.readAsBytes()`：更新包实测 57MB（后台 fileSize=59992363），
/// 一次性读入就要分配 57MB 连续内存，低端机上会被系统直接杀掉。更糟的是失败
/// 发生在「下载已完成 100%」之后，用户看到的是「下满了然后崩」，很难自查。
///
/// 分块读取把峰值内存压到 [chunkSize] 量级（默认 64KB）。
///
/// [onChunk] 仅供测试断言「确实在分块」，生产代码不需要传。
Future<String> sha256OfFile(
  File file, {
  int chunkSize = 64 * 1024,
  void Function(int chunkLength)? onChunk,
}) async {
  if (!await file.exists()) {
    throw Exception('待校验文件不存在: ${file.path}');
  }

  final output = _DigestSink();
  final input = sha256.startChunkedConversion(output);

  try {
    await for (final chunk in file.openRead()) {
      // openRead 自己决定实际块大小，这里按 chunkSize 再切一次，
      // 保证峰值内存有确定上限，不受平台缓冲策略影响。
      var offset = 0;
      while (offset < chunk.length) {
        final end = (offset + chunkSize) > chunk.length
            ? chunk.length
            : offset + chunkSize;
        final slice = chunk.sublist(offset, end);
        onChunk?.call(slice.length);
        input.add(slice);
        offset = end;
      }
    }
  } finally {
    input.close();
  }

  return output.value.toString();
}
