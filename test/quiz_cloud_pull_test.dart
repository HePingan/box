import 'dart:convert';

import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:box/features/quiz_plugin/data/quiz_cloud_pull.dart';
import 'package:box/features/quiz_plugin/data/quiz_cloud_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pullAll defaults to all catalogs and aggregates inserted count', () async {
    SharedPreferences.setMockInitialValues({});
    final client = _FakeCloudClient();
    final imported = <QuizBankItem>[];
    final service = QuizCloudSyncService(
      httpClient: client,
      importItems: (items) async {
        imported.addAll(items);
        return items.length;
      },
    );
    final pull = QuizCloudPullCoordinator(syncService: service);

    final result = await pull.pullAll(serverUrl: 'https://box.example');

    expect(result.inserted, 2);
    expect(result.categories, ['驾驶理论题库-20260719']);
    expect(imported.map((e) => e.question), ['云端题一', '云端题二']);
    expect(client.paths, contains('/api/quiz/catalogs'));
    expect(client.paths.where((p) => p == '/api/quiz/sync').length, 1);

    final status = await pull.loadStatus();
    expect(status.subscribedCategories, ['驾驶理论题库-20260719']);
    expect(status.lastSummary, contains('新增 2'));
  });

  test('resetCursor sends cursor 0 again after previous sync', () async {
    SharedPreferences.setMockInitialValues({});
    final client = _FakeCloudClient();
    final service = QuizCloudSyncService(
      httpClient: client,
      importItems: (items) async => items.length,
    );
    final pull = QuizCloudPullCoordinator(syncService: service);

    await pull.pullAll(serverUrl: 'https://box.example');
    final cursorsBefore = List<String>.from(client.syncCursors);
    await pull.pullAll(serverUrl: 'https://box.example', resetCursor: true);
    expect(client.syncCursors, isNotEmpty);
    expect(client.syncCursors.last, '0');
    expect(cursorsBefore, isNotEmpty);
  });

  test('subscription list is persisted and reused', () async {
    SharedPreferences.setMockInitialValues({});
    final client = _FakeCloudClient(multiCatalog: true);
    final service = QuizCloudSyncService(
      httpClient: client,
      importItems: (items) async => items.length,
    );
    final pull = QuizCloudPullCoordinator(syncService: service);
    await pull.saveSubscribedCategories(['B类']);
    final result = await pull.pullAll(serverUrl: 'https://box.example');
    expect(result.categories, ['B类']);
    expect(client.syncCategories, ['B类']);
  });
}

class _FakeCloudClient extends http.BaseClient {
  _FakeCloudClient({this.multiCatalog = false});

  final bool multiCatalog;
  final List<String> paths = [];
  final List<String> syncCursors = [];
  final List<String> syncCategories = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    paths.add(request.url.path);
    final Map<String, Object?> body;
    if (request.url.path.endsWith('/catalogs')) {
      body = {
        'catalogs': multiCatalog
            ? [
                {'id': 'A类', 'name': 'A类', 'count': 1},
                {'id': 'B类', 'name': 'B类', 'count': 1},
              ]
            : [
                {
                  'id': '驾驶理论题库-20260719',
                  'name': '驾驶理论题库-20260719',
                  'count': 2,
                },
              ],
      };
    } else {
      syncCursors.add(request.url.queryParameters['cursor'] ?? '');
      final category = request.url.queryParameters['category'] ?? '';
      if (category.isNotEmpty) syncCategories.add(category);
      body = {
        'cursor': 2,
        'hasMore': false,
        'changes': [
          _change('云端题一'),
          _change('云端题二'),
        ],
      };
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

Map<String, Object?> _change(String question) => {
      'operation': 'upsert',
      'question': {
        'id': question,
        'question': question,
        'type': 'single_choice',
        'options': ['甲', '乙'],
        'correctAnswer': '甲',
      },
    };
