// 传输队列落盘（284 P1）：读写往返、坏数据容错、条数上限、清理。

import 'dart:convert';
import 'dart:io';

import 'package:box/features/extensions/plugins/remote_storage/data/transfer_queue_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late TransferQueueStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rs_queue_store_');
    store = TransferQueueStore(dirProvider: () async => dir);
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  File file() => File('${dir.path}/${TransferQueueStore.fileName}');

  test('写读往返：记录原样回来，字段顺序无关', () async {
    await store.save([
      {'kind': 'download', 'accountId': 'a', 'remotePath': '/x/y.mp4', 'totalBytes': 10},
      {'kind': 'upload', 'accountId': 'b', 'remotePath': '/d', 'localPath': '/tmp/f.bin'},
    ]);

    final loaded = await store.load();
    expect(loaded, hasLength(2));
    expect(loaded[0]['remotePath'], '/x/y.mp4');
    expect(loaded[1]['localPath'], '/tmp/f.bin');
  });

  test('没有文件 → 空表（不是错误）', () async {
    expect(await store.load(), isEmpty);
  });

  test('文件坏了（不是 JSON）→ 空表，不抛异常', () async {
    await file().writeAsString('{不是 JSON');
    expect(await store.load(), isEmpty);
  });

  test('JSON 不是数组 → 空表', () async {
    await file().writeAsString(jsonEncode({'ok': true}));
    expect(await store.load(), isEmpty);
  });

  test('数组里混了非对象项 → 那些项被丢掉，正常的留下', () async {
    await file().writeAsString(jsonEncode([
      {'kind': 'download', 'accountId': 'a', 'remotePath': '/p'},
      'garbage',
      42,
    ]));
    final loaded = await store.load();
    expect(loaded, hasLength(1));
    expect(loaded.single['accountId'], 'a');
  });

  test('超过上限只留最新的（新在前）', () async {
    final many = [
      for (var i = 0; i < TransferQueueStore.kMaxPersistedTasks + 25; i++)
        {'kind': 'download', 'accountId': 'a', 'remotePath': '/f$i'},
    ];
    await store.save(many);

    final loaded = await store.load();
    expect(loaded, hasLength(TransferQueueStore.kMaxPersistedTasks));
    expect(loaded.first['remotePath'], '/f0', reason: '保留最新的那批');
  });

  test('clear 之后读到空表', () async {
    await store.save([
      {'kind': 'download', 'accountId': 'a', 'remotePath': '/p'},
    ]);
    await store.clear();
    expect(await store.load(), isEmpty);
  });

  test('写盘不留下 .tmp（写一半被杀也不该污染下次恢复）', () async {
    await store.save([
      {'kind': 'download', 'accountId': 'a', 'remotePath': '/p'},
    ]);
    final leftovers = dir
        .listSync()
        .where((e) => e.path.endsWith('.tmp'))
        .toList(growable: false);
    expect(leftovers, isEmpty);
  });
}
