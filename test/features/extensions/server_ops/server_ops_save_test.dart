// 落盘的抗断网语义：先写临时名、再 MOVE 盖到目标上 —— 而不是直接 PUT 覆盖。
//
// 为什么值得为这个写一条：手机网络断在传输中间时，rclone 会留下**被截断**的目标
// 文件（"文件坏了"比"这次没保存成功"严重得多）。这里断言两件事：
//   1) 成功路径：内容先落到 `<path>.box-new-…`，再 MOVE 到目标；
//   2) 失败路径：MOVE 没过时，把临时文件删掉、把错误抛出去（目标文件没被动过）。

import 'dart:typed_data';

import 'package:box/features/extensions/plugins/remote_storage/domain/webdav_client.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_files_service.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_text_edit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ops_test_servers.dart';

/// 只认 MOVE / DELETE 的假传输（PUT 被 saveText 的覆写挡掉了，见 _SaveOnlyService）。
class _MoveTransport implements WebdavTransport {
  _MoveTransport({this.failMove = false});

  final bool failMove;
  final List<String> methods = <String>[];
  final List<String> destinations = <String>[];
  final List<String> deleted = <String>[];

  /// 绝对/相对 URI 都归一成"相对 baseUrl 的路径"（destination 头给的是什么形态
  /// 由底层传输决定，测试不该依赖它的写法）。
  String _rel(Uri uri) {
    var path = uri.path;
    path = path.replaceFirst(RegExp(r'^/+'), '');
    path = path.replaceFirst(RegExp(r'^(?:dav175|dav)/'), '');
    return path.replaceAll(RegExp(r'/+$'), '');
  }

  @override
  Future<WebdavResponse> send(WebdavRequest request) async {
    methods.add(request.method);
    switch (request.method) {
      case 'MOVE':
        if (failMove) {
          return const WebdavResponse(statusCode: 500, headers: {});
        }
        destinations.add(_rel(Uri.parse(request.headers['destination'] ?? '')));
        return const WebdavResponse(statusCode: 201, headers: {});
      case 'DELETE':
        deleted.add(_rel(request.uri));
        return const WebdavResponse(statusCode: 204, headers: {});
      default:
        return const WebdavResponse(statusCode: 501, headers: {});
    }
  }
}

/// 把 saveText 换成记录（这样测试只盯"临时名 → MOVE"这段逻辑）。
class _SaveOnlyService extends ServerOpsFilesService {
  _SaveOnlyService(WebdavTransport transport)
      : super(settings: testSettingsPrimary, transportFactory: () => transport);

  final List<String> savedPaths = <String>[];

  @override
  Future<void> saveText(String path, Uint8List bytes) async {
    savedPaths.add(path);
  }
}

void main() {
  test('保存：先写 .box-new-… 临时名，再 MOVE 盖到目标上', () async {
    final transport = _MoveTransport();
    final service = _SaveOnlyService(transport);

    await service.saveTextAtomic(
      '/dav/etc/hosts',
      Uint8List.fromList(<int>[1, 2, 3]),
    );

    expect(service.savedPaths, hasLength(1));
    expect(
      service.savedPaths.single.startsWith('/dav/etc/hosts$kOpsPendingMarker'),
      isTrue,
      reason: '内容先落到临时名上，不能直接写目标',
    );
    // 不依赖 destination 头的具体写法（绝对/相对由底层传输决定），
    // 只断言两件要紧的事：目的地是**目标文件**、而且不是那个临时名。
    expect(transport.destinations, hasLength(1));
    final dest = transport.destinations.single;
    expect(dest.endsWith('etc/hosts'), isTrue, reason: '要 MOVE 到目标路径');
    expect(dest.contains(kOpsPendingMarker), isFalse,
        reason: '目的地不许还是临时名（那就是没盖上去）');
    expect(transport.deleted, isEmpty, reason: '成功了就不该留临时文件');
  });

  test('MOVE 失败：删掉临时文件、把错误抛出去（目标文件不动）', () async {
    final transport = _MoveTransport(failMove: true);
    final service = _SaveOnlyService(transport);

    await expectLater(
      service.saveTextAtomic('/dav/etc/hosts', Uint8List.fromList(<int>[1])),
      throwsA(anything),
    );

    expect(transport.deleted, hasLength(1), reason: '半成品要收拾掉');
    expect(
      transport.deleted.single.contains('etc/hosts$kOpsPendingMarker'),
      isTrue,
      reason: '删的应该是那个半成品临时文件',
    );
  });
}
