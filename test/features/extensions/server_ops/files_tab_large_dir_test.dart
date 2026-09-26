// 服务器运维插件：「文件」页签的大目录用例（D1）。
//
// 背景（实测）：运维通道是逐项读的，`/usr/lib64`（758 条）一次列举要 54 秒 / 484 KB。
// 所以这一页要保证三件事：
//   1. 不管目录多大，**一次只渲染 300 条**，剩下的靠「继续加载」；
//   2. 列举超过 5 秒要说清"在大目录上，可能要几十秒"，而不是只转圈；
//   3. 用户能「停止等待」，而且停掉之后回来的结果**不许**再刷界面。
import 'dart:async';

import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/server_ops/files_tab.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_files_service.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ops_test_servers.dart';

const _settings = testSettingsPrimary;

/// 假服务：条目一次给全（服务端就是这么给的），可以卡住不返回。
class _FakeFilesService extends ServerOpsFilesService {
  _FakeFilesService({this.entries = const [], this.gate}) : super(settings: _settings);

  List<RemoteStorageEntry> entries;

  /// 非 null 时，`list` 会等它完成才返回（用来演"大目录还在列举"）。
  Completer<void>? gate;

  @override
  Future<List<RemoteStorageEntry>> list(String path) async {
    final g = gate;
    if (g != null) await g.future;
    return entries;
  }
}

List<RemoteStorageEntry> _manyEntries(int count) => List<RemoteStorageEntry>.generate(
      count,
      (i) => RemoteStorageEntry(
        // 名字补零，排序稳定，也方便按名字过滤
        name: 'file-${i.toString().padLeft(4, '0')}.log',
        path: 'logs/file-${i.toString().padLeft(4, '0')}.log',
        isDirectory: false,
        size: 1024,
        modifiedAt: DateTime(2026, 9, 26),
      ),
    );

Future<void> _pump(WidgetTester tester, _FakeFilesService service) async {
  debugSetServerOpsRuntime(filesService: service);
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: ServerOpsFilesTab(settings: _settings))),
  );
  await tester.pump();
}

/// 滚到某个 finder 可见。
///
/// 必须显式指定"主列表"的可滚动区：页面里不止一个 Scrollable（面包屑也能横向滚），
/// scrollUntilVisible 默认的 `find.byType(Scrollable)` 会命中多个而报 Too many elements。
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  final scrollable = find
      .descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable))
      .first;
  await tester.scrollUntilVisible(finder, 600, scrollable: scrollable, maxScrolls: 400);
  await tester.pump();
}

void main() {
  testWidgets('2000 项：一次只渲染 300 条，底部是「还有 1700 项，继续加载」', (tester) async {
    final service = _FakeFilesService(entries: _manyEntries(2000));
    await _pump(tester, service);
    await tester.pump();

    // 首屏就有内容（不是整页转圈），说明列举本身是好的
    expect(find.text('file-0000.log'), findsOneWidget);

    // 页脚存在 = 只渲染了前 300 条（2000-300=1700 还没给）
    final footer = find.text('还有 1700 项，继续加载');
    await _scrollTo(tester, footer);
    expect(footer, findsOneWidget, reason: '2000 项应当只渲染 300 条');
    // 滚到底之后第 1 条已经不在树里（懒加载），这本身就是"没有一次全渲染"的证据
    expect(find.text('file-0000.log'), findsNothing);
  });

  testWidgets('点「继续加载」每次多给 300 条', (tester) async {
    final service = _FakeFilesService(entries: _manyEntries(2000));
    await _pump(tester, service);
    await tester.pump();

    await _scrollTo(tester, find.text('还有 1700 项，继续加载'));
    await tester.tap(find.text('还有 1700 项，继续加载'));
    await tester.pump();

    final next = find.text('还有 1400 项，继续加载');
    await _scrollTo(tester, next);
    expect(next, findsOneWidget);
  });

  testWidgets('过滤之后回到初值：命中的条目少于 300 时没有「继续加载」', (tester) async {
    final service = _FakeFilesService(entries: _manyEntries(2000));
    await _pump(tester, service);
    await tester.pump();

    await tester.enterText(find.byKey(const ValueKey('ops-file-filter')), 'file-004');
    await tester.pump();
    // 'file-004x' 命中 10 条；如果没回到初值，就会残留"还有 xxx 项"的页脚
    expect(find.textContaining('继续加载'), findsNothing);
  });

  testWidgets('列举超过 5 秒：说清"目录比较大"，并且给「停止等待」', (tester) async {
    final gate = Completer<void>();
    final service = _FakeFilesService(entries: _manyEntries(3), gate: gate);
    await _pump(tester, service);

    // 5 秒前只有转圈，没有"目录比较大"这句
    expect(find.textContaining('目录比较大'), findsNothing);
    await tester.pump(const Duration(seconds: 6));

    expect(find.textContaining('目录比较大'), findsOneWidget);
    expect(find.text('停止等待'), findsOneWidget);

    gate.complete();
    await tester.pump();
    await tester.pump();
  });

  testWidgets('「停止等待」之后：界面不再被在途结果刷到，也不写成功日志', (tester) async {
    final gate = Completer<void>();
    final service = _FakeFilesService(entries: _manyEntries(3), gate: gate);
    await _pump(tester, service);
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('停止等待'), findsOneWidget);

    await tester.tap(find.text('停止等待'));
    await tester.pump();
    expect(find.text('停止等待'), findsNothing, reason: '停了之后不该还挂着这个按钮');
    expect(find.byType(CircularProgressIndicator), findsNothing, reason: '转圈也要停');

    // 在途请求这才回来 —— 结果必须被丢掉，列表仍然没有内容
    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('file-0000.log'), findsNothing, reason: '停止等待之后的结果不许刷界面');
  });
}
