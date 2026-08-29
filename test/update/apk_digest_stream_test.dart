import 'dart:io';
import 'dart:typed_data';

import 'package:box/update/apk_digest.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// A1 回归：APK 校验必须流式读取，不能把整包读进内存。
///
/// 真实数据：后台 check 接口返回 fileSize=59992363（57.2MB）。
/// 旧实现是 `File(savePath).readAsBytes()` —— 一次性分配 57MB，
/// 低端机上会被系统杀掉，失败点还在「下载 100% 之后」。
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('apk_digest_test_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  File writeFile(String name, List<int> bytes) {
    final f = File(p.join(tmp.path, name));
    f.writeAsBytesSync(bytes);
    return f;
  }

  test('流式摘要与一次性读取结果一致', () async {
    // 覆盖多种长度，确保分块边界没算错。
    for (final size in <int>[0, 1, 1023, 1024, 1025, 65536, 65537, 200000]) {
      final bytes = Uint8List.fromList(
        List<int>.generate(size, (i) => (i * 31 + 7) & 0xFF),
      );
      final f = writeFile('probe_$size.bin', bytes);

      final streamed = await sha256OfFile(f);
      final oneShot = sha256.convert(bytes).toString();

      expect(
        streamed,
        oneShot,
        reason: 'size=$size 时流式摘要与整体摘要不一致',
      );
    }
  });

  test('分块大小不影响结果', () async {
    final bytes = Uint8List.fromList(
      List<int>.generate(300000, (i) => (i * 17) & 0xFF),
    );
    final f = writeFile('chunk.bin', bytes);
    final expected = sha256.convert(bytes).toString();

    for (final chunk in <int>[1, 512, 4096, 1 << 20]) {
      expect(
        await sha256OfFile(f, chunkSize: chunk),
        expected,
        reason: 'chunkSize=$chunk 时结果不一致',
      );
    }
  });

  test('单次读取的块不超过设定上限', () async {
    // 这是 A1 的核心断言：验证真的在分块，而不是偷偷整体读完。
    // 57MB 包如果一次性读入就会分配 57MB，这里用计数器证明没有。
    final bytes = Uint8List.fromList(List<int>.filled(500000, 0xAB));
    final f = writeFile('bounded.bin', bytes);

    var maxChunk = 0;
    await sha256OfFile(
      f,
      chunkSize: 8192,
      onChunk: (n) => maxChunk = n > maxChunk ? n : maxChunk,
    );

    expect(maxChunk, lessThanOrEqualTo(8192), reason: '出现超过上限的整块读取');
    expect(maxChunk, greaterThan(0), reason: '未真正读到数据');
  });

  test('文件不存在时抛异常而不是返回错误摘要', () async {
    final missing = File(p.join(tmp.path, 'nope.apk'));
    expect(() => sha256OfFile(missing), throwsA(isA<Exception>()));
  });
}
