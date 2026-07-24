import 'dart:convert';

import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:box/features/quiz_plugin/data/quiz_cloud_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cloud catalog and submission use canonical endpoints', () async {
    final requests = <http.Request>[];
    final service = QuizCloudSyncService(httpClient: _Client(requests));
    final catalogs = await service.fetchCatalogs(
      serverUrl: 'https://box.example',
    );
    expect(catalogs.single.id, 'drive_ev');
    final result = await service.submit(
      serverUrl: 'https://box.example',
      token: 't',
      category: 'drive_ev',
      item: const QuizBankItem(
        id: 'local',
        question: '题目',
        type: QuizQuestionType.singleChoice,
        options: ['正确', '错误'],
        correctAnswer: 'A',
      ),
    );
    expect(result.status, 'pending');
    expect(requests[0].url.path, '/api/quiz/catalogs');
    expect(requests[1].url.path, '/api/quiz/submissions');
    expect(requests[1].headers['authorization'], 'Bearer t');
    expect(jsonDecode(requests[1].body), containsPair('category', 'drive_ev'));
  });

  test(
    'sync fetches every page with the original cursor and page token',
    () async {
      SharedPreferences.setMockInitialValues({});
      final client = _PagedSyncClient([
        {
          'cursor': 0,
          'nextCursor': 'page-2',
          'hasMore': true,
          'changes': [_upsertChange('第一题')],
        },
        {
          'cursor': 9,
          'hasMore': false,
          'changes': [_upsertChange('第二题')],
        },
      ]);
      final imported = <QuizBankItem>[];
      final service = QuizCloudSyncService(
        httpClient: client,
        importItems: (items) async {
          imported.addAll(items);
          return items.length;
        },
      );

      final result = await service.sync(
        serverUrl: 'https://box.example',
        category: 'drive_ev',
      );

      expect(imported.map((item) => item.question), ['第一题', '第二题']);
      expect(client.requests, hasLength(2));
      expect(client.requests[0].url.queryParameters, {
        'cursor': '0',
        'limit': '100',
        'category': 'drive_ev',
      });
      expect(client.requests[1].url.queryParameters, {
        'cursor': '0',
        'limit': '100',
        'category': 'drive_ev',
        'pageToken': 'page-2',
      });
      expect(result.cursor, 9);
    },
  );

  test('sync keeps image field from cloud changes', () async {
    SharedPreferences.setMockInitialValues({});
    final client = _PagedSyncClient([
      {
        'cursor': 3,
        'hasMore': false,
        'changes': [
          _upsertChange('如图所示题', image: '/api/quiz/images/demo.png'),
        ],
      },
    ]);
    final imported = <QuizBankItem>[];
    final service = QuizCloudSyncService(
      httpClient: client,
      importItems: (items) async {
        imported.addAll(items);
        return items.length;
      },
    );

    await service.sync(serverUrl: 'https://box.example');
    expect(imported, hasLength(1));
    expect(imported.single.imageUrl, '/api/quiz/images/demo.png');
  });
}

Map<String, Object?> _upsertChange(String question, {String? image}) => {
      'operation': 'upsert',
      'question': {
        'id': question,
        'question': question,
        'type': 'single_choice',
        'options': ['甲', '乙'],
        'correctAnswer': '甲',
        'image': ?image,
      },
    };

class _Client extends http.BaseClient {
  _Client(this.requests);
  final List<http.Request> requests;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final copy = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    if (request is http.Request) copy.bodyBytes = request.bodyBytes;
    requests.add(copy);
    final body = request.url.path.endsWith('catalogs')
        ? '{"catalogs":[{"id":"drive_ev","name":"新能源","count":1}]}'
        : '{"id":"qs_1","status":"pending"}';
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

class _PagedSyncClient extends http.BaseClient {
  _PagedSyncClient(this.responses);
  final List<Map<String, Object?>> responses;
  final List<http.Request> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final copy = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    requests.add(copy);
    final body = jsonEncode(responses[requests.length - 1]);
    return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
  }
}
