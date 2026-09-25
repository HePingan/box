// 文件页的**写档动作**用例（解压 / 权限属主）——写档接的是只读接口，不是文件通道。
//
// 守三件事：
//   1. 菜单项跟着"这玩意儿是不是压缩包"走（普通文件不该出现「解压」）；
//   2. 动作要**先确认**再发（写动作会真的改机器）；
//   3. 路径口径：文件通道是相对路径（a/b.txt），写动作要**绝对路径**（/a/b.txt）——
//      少了那个前导斜杠，服务端直接 400「必须是绝对路径」。
import 'dart:convert';

import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/server_ops/files_tab.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_api_client.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_files_service.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_runtime.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'ops_test_servers.dart';

// 写档要有**设备令牌**（口令是文件通道的凭据，两套不通用）。
const ServerOpsSettings _settings = testSettingsWithApiToken;

class _FakeFiles extends ServerOpsFilesService {
  _FakeFiles({required this.entries, this.byPath = const {}})
      : super(settings: _settings);

  final List<RemoteStorageEntry> entries;

  /// 按目录给不同内容（子目录用例要用）。
  final Map<String, List<RemoteStorageEntry>> byPath;
  final List<String> listed = <String>[];

  @override
  Future<List<RemoteStorageEntry>> list(String path) async {
    listed.add(path);
    return byPath[path] ?? entries;
  }

  @override
  Future<bool> exists(String path) async => false;

  @override
  Future<void> createDirectory(String path) async {}
}

/// 记录写动作请求的假传输。
class _ApiCalls {
  final List<String> actions = <String>[];
  final List<Map<String, dynamic>> bodies = <Map<String, dynamic>>[];

  MockClient client({int status = 200, String? error}) => MockClient((req) async {
        actions.add(req.url.path.split('/').where((s) => s.isNotEmpty).last);
        if (req.body.isNotEmpty) {
          bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        }
        if (status != 200) {
          return http.Response(
            jsonEncode({'error': error ?? '被拒'}),
            status,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(
          jsonEncode({
            'path': '/a.zip',
            'count': 3,
            'dest': '/',
            'mode': '755',
            'truncated': false,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
}

Future<void> _pumpTab(
  WidgetTester tester,
  _FakeFiles files,
  _ApiCalls api,
) async {
  debugSetServerOpsRuntime(
    filesService: files,
    settings: _settings,
    apiClientFactory: (s) => OpsApiClient(
      baseUrl: s.effectiveApiUrl,
      token: s.effectiveApiToken,
      client: api.client(),
    ),
  );
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: ServerOpsFilesTab(settings: _settings))),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _openMenu(WidgetTester tester, String name) async {
  await tester.tap(
    find.descendant(
      of: find.widgetWithText(ListTile, name),
      matching: find.byType(PopupMenuButton<String>),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  final entries = <RemoteStorageEntry>[
    const RemoteStorageEntry(name: 'a.zip', path: 'a.zip', isDirectory: false),
    const RemoteStorageEntry(name: 'readme.txt', path: 'readme.txt', isDirectory: false),
    const RemoteStorageEntry(name: 'www', path: 'www', isDirectory: true),
  ];

  testWidgets('压缩包才有「解压到当前目录」，普通文件没有', (tester) async {
    await _pumpTab(tester, _FakeFiles(entries: entries), _ApiCalls());

    await _openMenu(tester, 'a.zip');
    expect(find.text('解压到当前目录'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5)); // 关掉菜单
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await _openMenu(tester, 'readme.txt');
    expect(find.text('解压到当前目录'), findsNothing);
  });

  testWidgets('解压：先确认，再把**绝对路径**发给只读接口，成功后刷新列表', (tester) async {
    final api = _ApiCalls();
    final files = _FakeFiles(entries: entries);
    await _pumpTab(tester, files, api);
    final listedBefore = files.listed.length;

    await _openMenu(tester, 'a.zip');
    await tester.tap(find.text('解压到当前目录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 确认框里有"会覆盖/不执行脚本"这类要说清的话
    expect(find.textContaining('服务端会把它解到当前目录'), findsOneWidget);
    await tester.tap(find.text('解压').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.actions, contains('extract'));
    expect(api.bodies.single['path'], '/a.zip');
    expect(api.bodies.single['dest'], '');
    expect(files.listed.length, greaterThan(listedBefore), reason: '写完要刷新');
  });

  testWidgets('解压：在子目录里发的是子目录的绝对路径', (tester) async {
    final api = _ApiCalls();
    final files = _FakeFiles(
      entries: const [
        RemoteStorageEntry(name: 'etc', path: 'etc', isDirectory: true),
      ],
      byPath: const {
        'etc': [
          RemoteStorageEntry(
              name: 'b.tgz', path: 'etc/b.tgz', isDirectory: false),
        ],
      },
    );
    await _pumpTab(tester, files, api);

    await tester.tap(find.widgetWithText(ListTile, 'etc'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(files.listed, contains('etc'));

    await _openMenu(tester, 'b.tgz');
    await tester.tap(find.text('解压到当前目录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('解压').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 关键：'etc/b.tgz' → '/etc/b.tgz'（服务端要求绝对路径）
    expect(api.bodies.single['path'], '/etc/b.tgz');
  });

  testWidgets('权限：填了权限与属主就发 chmod + chown，递归勾选框只对目录出现', (tester) async {
    final api = _ApiCalls();
    await _pumpTab(tester, _FakeFiles(entries: entries), api);

    await _openMenu(tester, 'readme.txt');
    await tester.tap(find.text('权限 / 属主'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('连同里面的内容'), findsNothing, reason: '文件不该有递归勾选');
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), '640');
    await tester.enterText(fields.at(1), 'www');
    await tester.tap(find.text('应用'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.actions, contains('chmod'));
    expect(api.bodies[0]['path'], '/readme.txt');
    expect(api.bodies[0]['mode'], '640');
    expect(api.bodies[1]['owner'], 'www');
  });

  testWidgets('权限：目录有递归勾选框，勾上后 recursive=true', (tester) async {
    final api = _ApiCalls();
    await _pumpTab(tester, _FakeFiles(entries: entries), api);

    await _openMenu(tester, 'www');
    await tester.tap(find.text('权限 / 属主'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('连同里面的内容'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('应用'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.bodies[0]['path'], '/www');
    // 客户端发的是真的 JSON 布尔（服务端会把布尔归一成 'true'/'false' 再校验）。
    expect(api.bodies[0]['recursive'], isTrue);
  });

  testWidgets('服务端拒绝时把原话显示出来（例如受保护路径）', (tester) async {
    final api = _ApiCalls();
    api.client; // 保持接口一致
    final files = _FakeFiles(entries: entries);
    debugSetServerOpsRuntime(
      filesService: files,
      settings: _settings,
      apiClientFactory: (s) => OpsApiClient(
        baseUrl: s.effectiveApiUrl,
        token: s.effectiveApiToken,
        client: MockClient((req) async => http.Response(
              jsonEncode({'error': '这个路径受保护，写动作一律拒绝：/root/.secrets'}),
              403,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )),
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ServerOpsFilesTab(settings: _settings))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await _openMenu(tester, 'a.zip');
    await tester.tap(find.text('解压到当前目录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('解压').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('受保护'), findsOneWidget);
  });
}
