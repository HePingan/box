import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/watch_later/data/watch_later_store.dart';
import 'package:box/features/extensions/plugins/watch_later/domain/watch_later_item.dart';
import 'package:box/features/extensions/plugins/watch_later/presentation/watch_later_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 稍后看页面的真流程：添加 → 去重 → 删除 → 点开播放，全部跑在内存实现上。
const _account = RemoteStorageAccount(
  id: 'acc-wl',
  label: '测试盘',
  baseUrl: 'https://dav.example.com/dav/',
  username: 'u',
  password: 'p',
);

Future<void> _pump(
  WidgetTester tester,
  WatchLaterStore store, {
  String payload = '',
  void Function(WatchLaterItem)? onPlay,
}) async {
  debugSetWatchLaterRuntime(store: store);
  await tester.pumpWidget(
    MaterialApp(
      home: WatchLaterPage(initialPayload: payload, onPlay: onPlay),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => debugSetWatchLaterRuntime());

  testWidgets('没有远程存储账户 → 引导去添加，且没有「加入」按钮', (tester) async {
    await _pump(tester, InMemoryWatchLaterStore());

    expect(find.textContaining('先添加一个账户'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '去添加账户'), findsOneWidget);
    expect(find.widgetWithText(FloatingActionButton, '加入稍后看'), findsNothing);
  });

  testWidgets('空清单 → 加一条，标题从地址推导并落库', (tester) async {
    final store = InMemoryWatchLaterStore(accounts: const [_account]);
    await _pump(tester, store);

    expect(find.text('还没有想看的'), findsOneWidget);
    expect(find.textContaining('共 0 条'), findsOneWidget);

    await tester.tap(find.widgetWithText(FloatingActionButton, '加入稍后看'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '播放地址'),
      'https://v.qq.com/x/cover/abc/流浪地球.mp4',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('流浪地球'), findsOneWidget);
    expect(find.textContaining('共 1 条'), findsOneWidget);

    final items = await store.load(_account);
    expect(items.single.url, 'https://v.qq.com/x/cover/abc/流浪地球.mp4');
    expect(items.single.sourceName, 'v.qq.com');
  });

  testWidgets('非法地址不入库，并把原因写在弹层里', (tester) async {
    final store = InMemoryWatchLaterStore(accounts: const [_account]);
    await _pump(tester, store);

    await tester.tap(find.widgetWithText(FloatingActionButton, '加入稍后看'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '播放地址'),
      'file:///sdcard/movie.mp4',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.textContaining('只支持 http/https'), findsOneWidget);
    expect(await store.load(_account), isEmpty);
    // 弹层没关，用户输入不丢
    expect(find.widgetWithText(FilledButton, '保存'), findsOneWidget);
  });

  testWidgets('同一地址加两次不产生两条，并提示已存在', (tester) async {
    final store = InMemoryWatchLaterStore(
      accounts: const [_account],
      seed: const [
        WatchLaterItem(
          url: 'https://a.com/movie/流浪地球.mp4',
          title: '流浪地球',
          addedAtMs: 1,
        ),
      ],
    );
    await _pump(tester, store);

    await tester.tap(find.widgetWithText(FloatingActionButton, '加入稍后看'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '播放地址'),
      'https://a.com/movie/流浪地球.mp4',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '标题（可空）'),
      '流浪地球 4K',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已在清单里'), findsOneWidget);
    final items = await store.load(_account);
    expect(items, hasLength(1));
    expect(items.single.title, '流浪地球 4K');
  });

  testWidgets('删除要二次确认，确认后清单里也没了', (tester) async {
    final store = InMemoryWatchLaterStore(
      accounts: const [_account],
      seed: const [
        WatchLaterItem(url: 'https://a.com/1', title: '一号片', addedAtMs: 2),
      ],
    );
    await _pump(tester, store);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('从稍后看移除'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '移除'));
    await tester.pumpAndSettle();

    expect(find.text('还没有想看的'), findsOneWidget);
    expect(await store.load(_account), isEmpty);
  });

  testWidgets('点条目会去播放（测试里拦下播放入口，不真起播放器）', (tester) async {
    final played = <WatchLaterItem>[];
    final store = InMemoryWatchLaterStore(
      accounts: const [_account],
      seed: const [
        WatchLaterItem(
          url: 'https://a.com/movie/流浪地球.mp4',
          title: '流浪地球',
          addedAtMs: 5,
        ),
      ],
    );
    await _pump(tester, store, onPlay: played.add);

    await tester.tap(find.text('流浪地球'));
    await tester.pumpAndSettle();

    expect(played, hasLength(1));
    expect(played.single.url, 'https://a.com/movie/流浪地球.mp4');
  });

  testWidgets('payload 带地址 → 进来就把添加弹层填好（不自动落库）', (tester) async {
    final store = InMemoryWatchLaterStore(accounts: const [_account]);
    await _pump(
      tester,
      store,
      payload: '{"url":"https://a.com/v/77","title":"带来的一集"}',
    );

    // 弹层已打开且填好
    expect(find.widgetWithText(FilledButton, '保存'), findsOneWidget);
    final urlField = tester.widget<TextField>(
      find.widgetWithText(TextField, '播放地址'),
    );
    expect(urlField.controller?.text, 'https://a.com/v/77');

    // 还没保存 → 清单仍为空
    expect(await store.load(_account), isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('带来的一集'), findsOneWidget);
  });

  testWidgets('payload 非法时安静打开空清单，不弹错误', (tester) async {
    final store = InMemoryWatchLaterStore(accounts: const [_account]);
    await _pump(tester, store, payload: 'file:///etc/passwd');

    expect(find.text('还没有想看的'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '保存'), findsNothing);
  });
}
