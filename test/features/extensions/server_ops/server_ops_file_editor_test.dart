// 文件编辑页的行为：保存的顺序（先备份再上传）、三种"不给编辑"的判定、
// 锁门名单的确认、以及"期间被别人改过"的提示。
//
// 假服务只覆盖用到的那几个方法 —— 断言的是"我们发出去的指令对不对"，
// 真机上键盘与滚动手感只能在真机看。

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/webdav_client.dart';
import 'package:box/features/extensions/plugins/server_ops/file_editor_page.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_files_service.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_text_edit.dart';

class _FakeFiles extends ServerOpsFilesService {
  _FakeFiles(this.content, {this.statSeq = const <RemoteStorageEntry?>[]})
      : super(settings: const ServerOpsSettings());

  final Uint8List content;

  /// 依次返回的 stat（第一次是打开，第二次是保存前的比对）；用完就重复最后一个。
  final List<RemoteStorageEntry?> statSeq;

  final List<String> calls = <String>[];
  Uint8List? savedBytes;
  int statCount = 0;

  @override
  Future<RemoteStorageEntry?> statFor(String path) async {
    calls.add('stat');
    final entry = statSeq.isEmpty
        ? RemoteStorageEntry(
            name: ServerOpsFilesService.basename(path),
            path: path,
            isDirectory: false,
            size: content.length,
            modifiedAt: DateTime(2026, 9, 26, 14, 0, 0),
          )
        : statSeq[statCount < statSeq.length ? statCount : statSeq.length - 1];
    statCount++;
    return entry;
  }

  @override
  Future<ReadUpTo> readUpTo(String path, int maxBytes) async => ReadUpTo(
        bytes: content,
        truncated: content.length > maxBytes,
        totalLength: content.length,
      );

  @override
  Future<String> backupBeforeSave(
    String path, {
    int keep = kOpsBackupKeep,
    DateTime? now,
  }) async {
    calls.add('backup');
    return opsBackupName(path, now ?? DateTime(2026, 9, 26, 15, 0, 1));
  }

  @override
  Future<void> saveText(String path, Uint8List bytes) async {
    calls.add('save');
    savedBytes = bytes;
  }

  @override
  Future<void> saveTextAtomic(String path, Uint8List bytes) async {
    // 编辑器走的是"临时名 + MOVE"那条；这条测试只关心"备份早于落盘"，
    // 抗断网的语义由 server_ops_save_test.dart 单独断言。
    calls.add('save');
    savedBytes = bytes;
  }

  @override
  Future<List<RemoteStorageEntry>> listBackups(String path) async =>
      const <RemoteStorageEntry>[];
}

Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

Future<void> pumpEditor(
  WidgetTester tester, {
  required String path,
  required Uint8List content,
  List<RemoteStorageEntry?> statSeq = const <RemoteStorageEntry?>[],
}) async {
  final service = _FakeFiles(content, statSeq: statSeq);
  await tester.pumpWidget(
    MaterialApp(
      home: OpsFileEditorPage(
        service: service,
        path: path,
        name: ServerOpsFilesService.basename(path),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  // 让测试拿到那个假服务
  _lastService = service;
}

_FakeFiles? _lastService;

void main() {
  tearDown(() => _lastService = null);

  testWidgets('改完保存：先备份、再上传，且按原文件的结尾换行回写', (tester) async {
    await pumpEditor(tester, path: '/etc/hosts', content: bytesOf('# hosts\n'));

    expect(find.text('hosts'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('ops-editor-field')),
      '# hosts\n1.2.3.4 foo',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final service = _lastService!;
    expect(service.calls.contains('save'), isTrue, reason: '应该真的上传了');
    expect(
      service.calls.indexOf('backup') < service.calls.indexOf('save'),
      isTrue,
      reason: '备份必须在上传之前 —— 没有后路的写入不做',
    );
    expect(utf8.decode(service.savedBytes!), '# hosts\n1.2.3.4 foo\n',
        reason: '原文件结尾有换行，回写时要保留');
  });

  testWidgets('二进制文件：只读，并说明为什么不给编辑', (tester) async {
    await pumpEditor(
      tester,
      path: '/root/a.bin',
      content: Uint8List.fromList(<int>[1, 2, 0, 3, 4]),
    );

    expect(find.textContaining('二进制'), findsOneWidget);
    final save = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '保存'),
    );
    expect(save.onPressed, isNull, reason: '不能编辑就不能有保存入口');
  });

  testWidgets('不是 UTF-8：只读（免得存回去变乱码）', (tester) async {
    await pumpEditor(
      tester,
      path: '/etc/legacy.conf',
      content: Uint8List.fromList(<int>[0xC4, 0xE3, 0xBA, 0xC3]),
    );

    expect(find.textContaining('不是 UTF-8'), findsOneWidget);
  });

  testWidgets('超过编辑上限：只读，并说明上限', (tester) async {
    final big = Uint8List(kOpsEditMaxBytes + 10)..fillRange(0, kOpsEditMaxBytes + 10, 65);
    await pumpEditor(tester, path: '/var/log/big.log', content: big);

    expect(find.textContaining('超过编辑上限'), findsOneWidget);
  });

  testWidgets('会把自己锁在门外的文件：保存前要确认，点「先不改」就不上传', (tester) async {
    await pumpEditor(
      tester,
      path: '/etc/ssh/sshd_config',
      content: bytesOf('Port 22\n'),
    );

    // 顶栏一直挂着提醒（不是等到保存才说）
    expect(find.textContaining('SSH 的配置'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('ops-editor-field')),
      'Port 2222\n',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('保存前确认'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '先不改'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(_lastService!.calls.contains('save'), isFalse, reason: '取消了就不该上传');

    // 再来一次，这次确认保存
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, '仍要保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_lastService!.calls.contains('save'), isTrue);
  });

  testWidgets('期间被服务器上的人改过：覆盖前问一句，取消就不上传', (tester) async {
    await pumpEditor(
      tester,
      path: '/etc/hosts',
      content: bytesOf('a\n'),
      statSeq: <RemoteStorageEntry?>[
        RemoteStorageEntry(
          name: 'hosts',
          path: '/etc/hosts',
          isDirectory: false,
          size: 2,
          modifiedAt: DateTime(2026, 9, 26, 14, 0, 0),
        ),
        RemoteStorageEntry(
          name: 'hosts',
          path: '/etc/hosts',
          isDirectory: false,
          size: 99,
          modifiedAt: DateTime(2026, 9, 26, 14, 30, 0),
        ),
      ],
    );

    await tester.enterText(
      find.byKey(const ValueKey('ops-editor-field')),
      'b\n',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('这台上的文件已经变了'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_lastService!.calls.contains('save'), isFalse);
  });

  testWidgets('查找 / 替换：全部替换会报出替换了几处', (tester) async {
    await pumpEditor(
      tester,
      path: '/etc/hosts',
      content: bytesOf('foo a\nfoo b\n'),
    );

    await tester.tap(find.byTooltip('查找 / 替换'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('ops-editor-find')), 'foo');
    await tester.enterText(
      find.byKey(const ValueKey('ops-editor-replace')),
      'bar',
    );
    await tester.tap(find.widgetWithText(TextButton, '全部替换'));
    await tester.pump();

    expect(find.text('已替换 2 处'), findsOneWidget);
  });

  testWidgets('符号键：点一下就把字符插进正文', (tester) async {
    await pumpEditor(tester, path: '/etc/hosts', content: bytesOf('abc'));

    final field = find.byKey(const ValueKey('ops-editor-field'));
    await tester.enterText(field, 'abc');
    await tester.pump();
    // 光标放到末尾，点 '#' 应该追加
    await tester.tap(find.text('#'));
    await tester.pump();

    final widget = tester.widget<TextField>(field);
    expect(widget.controller!.text, contains('#'));
  });
}
