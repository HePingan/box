import 'package:box/features/extensions/plugins/quick_note/data/quick_note_store.dart';
import 'package:box/features/extensions/plugins/quick_note/domain/quick_note.dart';
import 'package:box/features/extensions/plugins/quick_note/presentation/quick_note_page.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 快速便签页：真流程（新建 → 列表 → 编辑 → 删除）跑在内存实现上，
/// 不碰 WebDAV、不碰 shared_preferences。
const _account = RemoteStorageAccount(
  id: 'acc-test',
  label: '测试盘',
  baseUrl: 'https://dav.example.com/dav/',
  username: 'u',
  password: 'p',
);

/// 保存永远失败的实现（验证错误不会被吞成「保存成功」）。
class _FailingStore extends InMemoryQuickNoteStore {
  _FailingStore() : super(accounts: const [_account]);

  @override
  Future<QuickNote> save(
    RemoteStorageAccount account, {
    required String fileName,
    required String body,
  }) async {
    throw Exception('网络不可达');
  }
}

Future<void> _pump(WidgetTester tester, QuickNoteStore store) async {
  debugSetQuickNoteRuntime(store: store);
  await tester.pumpWidget(const MaterialApp(home: QuickNotePage()));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => debugSetQuickNoteRuntime());

  testWidgets('没有远程存储账户时，引导去添加而不是空转', (tester) async {
    await _pump(tester, InMemoryQuickNoteStore());

    expect(find.textContaining('先添加一个账户'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '去添加账户'), findsOneWidget);
    // 没有账户时不该出现「新建便签」——新建了也存不下去
    expect(find.widgetWithText(FloatingActionButton, '新建便签'), findsNothing);
  });

  testWidgets('有账户但没有便签 → 空态，且能新建一条', (tester) async {
    final store = InMemoryQuickNoteStore(accounts: const [_account]);
    await _pump(tester, store);

    expect(find.text('还没有便签'), findsOneWidget);
    expect(find.textContaining('共 0 条'), findsOneWidget);

    await tester.tap(find.widgetWithText(FloatingActionButton, '新建便签'));
    await tester.pumpAndSettle();

    expect(find.text('新建便签'), findsWidgets);
    await tester.enterText(find.byType(TextField), '买牛奶\n顺路取快递');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    // 存进去了：标题来自正文首行
    expect(find.text('买牛奶'), findsOneWidget);
    expect(find.textContaining('共 1 条'), findsOneWidget);
    final notes = await store.list(_account);
    expect(notes.single.name, endsWith('-买牛奶.md'));
    expect(await store.read(_account, notes.single), '买牛奶\n顺路取快递');
  });

  testWidgets('空内容不保存，并把原因写在输入框下面', (tester) async {
    final store = InMemoryQuickNoteStore(accounts: const [_account]);
    await _pump(tester, store);

    await tester.tap(find.widgetWithText(FloatingActionButton, '新建便签'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.textContaining('空便签不保存'), findsOneWidget);
    expect(await store.list(_account), isEmpty);
    // 弹层还在（没有误关，用户输入不会白丢）
    expect(find.widgetWithText(FilledButton, '保存'), findsOneWidget);
  });

  testWidgets('点开能读回正文并覆盖保存，文件名不变', (tester) async {
    final store = InMemoryQuickNoteStore(
      accounts: const [_account],
      seed: {'2026-10-30-2105-买牛奶.md': '买牛奶\n顺路取快递'},
    );
    await _pump(tester, store);

    await tester.tap(find.text('买牛奶'));
    await tester.pumpAndSettle();

    // 编辑态：正文已带出来
    expect(find.text('编辑便签'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, '买牛奶\n顺路取快递');

    await tester.enterText(find.byType(TextField), '买牛奶\n顺路取快递和酸奶');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final notes = await store.list(_account);
    expect(notes, hasLength(1), reason: '编辑是覆盖，不该多出一条');
    expect(notes.single.name, '2026-10-30-2105-买牛奶.md');
    expect(await store.read(_account, notes.single), '买牛奶\n顺路取快递和酸奶');
  });

  testWidgets('删除要二次确认，确认后真的删掉', (tester) async {
    final store = InMemoryQuickNoteStore(
      accounts: const [_account],
      seed: {'2026-10-30-2105-买牛奶.md': '买牛奶'},
    );
    await _pump(tester, store);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('删除便签'), findsOneWidget);
    expect(find.textContaining('远程存储里的文件也会一并删除'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.text('还没有便签'), findsOneWidget);
    expect(await store.list(_account), isEmpty);
  });

  testWidgets('保存失败必须明说，不能假装成功', (tester) async {
    await _pump(tester, _FailingStore());

    await tester.tap(find.widgetWithText(FloatingActionButton, '新建便签'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '一条便签');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.textContaining('保存失败'), findsOneWidget);
    // 列表仍是空态（没有凭空出现一条假条目）
    expect(find.text('还没有便签'), findsOneWidget);
  });

  testWidgets('多账户时顶部可切换，并记住选择', (tester) async {
    const second = RemoteStorageAccount(
      id: 'acc-2',
      label: '备份盘',
      baseUrl: 'https://backup.example.com/dav/',
      username: 'u2',
      password: 'p2',
    );
    final store = InMemoryQuickNoteStore(
      accounts: const [_account, second],
      seed: {'2026-10-30-2105-买牛奶.md': '买牛奶'},
    );
    await _pump(tester, store);

    // 默认用第一个账户，能看到它的便签
    expect(find.text('买牛奶'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('备份盘').last);
    await tester.pumpAndSettle();

    expect(await store.lastAccountId(), 'acc-2');
  });
}
