import 'dart:io';

import 'package:box/features/extensions/plugins/remote_storage/application/remote_storage_service.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/webdav_client.dart';
import 'package:box/utils/app_logger.dart';
import 'package:box/utils/log_channels.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「已记入调试日志」不是装饰文案：
/// 用户可见的每个连接错误，必须在「存储」频道里真的有落点可回看。
/// 本文件把承诺与行为钉在一起——文案在异常归一化处产生，落盘也必须在同一处发生。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLogger.instance.lines.value = const <String>[];
  });

  List<LogEntry> storageEntries() => AppLogger.instance.lines.value
      .map(LogEntry.parse)
      .where((e) => e.channel == LogChannel.storage)
      .toList();

  DioException dio({required DioExceptionType type, int? status}) =>
      DioException(
        requestOptions: RequestOptions(path: '/dav/'),
        type: type,
        response: status == null
            ? null
            : Response(
                requestOptions: RequestOptions(path: '/dav/'),
                statusCode: status,
              ),
      );

  group('「已记入调试日志」承诺真实成立', () {
    test('连接超时：归一化时立即落盘，文案与落盘同源', () {
      final e = mapDioException(dio(type: DioExceptionType.connectionTimeout));

      expect(e.kind, RemoteStorageError.timeout);
      expect(e.message, contains('已记入调试日志'));

      final logged = storageEntries();
      expect(logged, hasLength(1), reason: '承诺文案出现时，日志里必须已经落点');
      expect(logged.single.level, LogLevel.error);
      expect(logged.single.message, contains('DioException'));
    });

    test('HTTP 507（空间不足）同样落盘', () {
      mapDioException(dio(type: DioExceptionType.badResponse, status: 507));
      expect(storageEntries(), hasLength(1));
    });

    test('用户主动取消不写日志（避免刷屏）', () {
      final e = mapDioException(dio(type: DioExceptionType.cancel));
      expect(e.kind, RemoteStorageError.canceled);
      expect(storageEntries(), isEmpty);
    });

    test('传输层原始错误（非 dio 路径）也落盘——防御性加固', () {
      mapTransportError(SocketException('connection refused'));
      expect(storageEntries(), hasLength(1));
    });
  });
}
