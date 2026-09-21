import 'dart:convert';

import 'package:box/features/quiz_plugin/data/quiz_cloud_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 复刻 QuizCloudSyncService._safeKey（base64url 去 '='），
/// 使测试写入的续传点键与生产代码完全一致。
String _safeKey(String raw) =>
    base64Url.encode(utf8.encode(raw)).replaceAll('=', '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('中断同步可续传（同步被打断不得静默丢进度）', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('默认无未完成轨', () async {
      final sync = QuizCloudSyncService();
      expect(
        await sync.hasIncompleteSync(serverUrl: 'https://example.com'),
        isFalse,
      );
    });

    test('未完成轨按 server+category 隔离，互不串扰', () async {
      final sync = QuizCloudSyncService();
      const server = 'https://example.com';
      final serverKey = _safeKey(server);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'quiz_cloud_incomplete_v1:$serverKey:': 1528,
        'quiz_cloud_incomplete_v1:$serverKey:catA': 900,
      });

      expect(await sync.hasIncompleteSync(serverUrl: server), isTrue);
      expect(
        await sync.hasIncompleteSync(serverUrl: server, category: 'catA'),
        isTrue,
      );
      expect(
        await sync.hasIncompleteSync(serverUrl: server, category: 'catB'),
        isFalse,
      );
      expect(
        await sync.hasIncompleteSync(serverUrl: 'https://other.com'),
        isFalse,
      );
    });
  });
}
