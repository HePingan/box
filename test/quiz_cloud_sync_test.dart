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
        imageSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        imagePerceptualHash: '0123456789abcdef',
      ),
    );
    expect(result.status, 'pending');
    expect(requests[0].url.path, '/api/quiz/catalogs');
    expect(requests[1].url.path, '/api/quiz/submissions');
    expect(requests[1].headers['authorization'], 'Bearer t');
    final body = jsonDecode(requests[1].body) as Map<String, dynamic>;
    expect(body['category'], 'drive_ev');
    expect(
      body['imageSha256'],
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    expect(body['imagePerceptualHash'], '0123456789abcdef');
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

  test('sync deletes only the matching cloud mirror', () async {
    SharedPreferences.setMockInitialValues({});
    final deletedIds = <String>[];
    final service = QuizCloudSyncService(
      httpClient: _PagedSyncClient([
        {
          'cursor': 1,
          'hasMore': false,
          'changes': [
            {'operation': 'delete', 'id': 'cloud-q1'},
          ],
        },
      ]),
      importItems: (_) async => 0,
      deleteCloudItem: (id) async {
        deletedIds.add(id);
        return 1;
      },
    );

    final result = await service.sync(serverUrl: 'https://box.example');
    expect(deletedIds, ['cloud-q1']);
    expect(result.cloudDeletes, 1);
  });

  test('sync keeps image and image fingerprints from cloud changes', () async {
    SharedPreferences.setMockInitialValues({});
    final client = _PagedSyncClient([
      {
        'cursor': 3,
        'hasMore': false,
        'changes': [
          _upsertChange(
            '如图所示题',
            image: '/api/quiz/images/demo.png',
            imageSha256:
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            imagePerceptualHash: '0123456789abcdef',
          ),
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
    expect(
      imported.single.imageSha256,
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    expect(imported.single.imagePerceptualHash, '0123456789abcdef');
  });

  test('单页瞬时网络失败时应重试该页，不得让整轮同步残缺', () async {
    SharedPreferences.setMockInitialValues({});
    final client = _FlakySyncClient({
      '0': {
        'cursor': 100,
        'hasMore': true,
        'changes': [_upsertChange('第1页题')],
      },
      '100': {
        'cursor': 200,
        'hasMore': true,
        'changes': [_upsertChange('第2页题')],
      },
      '200': {
        'cursor': 300,
        'hasMore': false,
        'changes': [_upsertChange('第3页题')],
      },
    }, failOnCall: 2);
    final imported = <QuizBankItem>[];
    final service = QuizCloudSyncService(
      httpClient: client,
      importItems: (items) async {
        imported.addAll(items);
        return items.length;
      },
    );

    final result = await service.sync(serverUrl: 'https://box.example');
    expect(
      imported.map((e) => e.question),
      containsAll(<String>['第1页题', '第2页题', '第3页题']),
      reason: '单页瞬时失败不得截断整轮同步',
    );
    expect(result.reachedPageLimit, isFalse, reason: '不应因瞬时失败标记为未拉完');
  });

  test('重试仍失败时必须保留续传点，供下次补齐', () async {
    SharedPreferences.setMockInitialValues({});
    final client = _AlwaysFailFrom(2);
    final service = QuizCloudSyncService(
      httpClient: client,
      importItems: (items) async => items.length,
    );

    // 彻底拉不动时抛出是允许的（界面会报「同步失败」），
    // 但必须在抛出前记录续传点，否则库残缺却无人知晓。
    await expectLater(
      service.sync(serverUrl: 'https://box.example'),
      throwsA(isA<http.ClientException>()),
    );
    expect(
      await service.hasIncompleteSync(serverUrl: 'https://box.example'),
      isTrue,
      reason: '同步中断必须留下续传点，供下次自动补齐',
    );
  });
}

/// 第 [failFromCall] 次请求起全部抛错。
class _AlwaysFailFrom extends http.BaseClient {
  _AlwaysFailFrom(this.failFromCall);
  final int failFromCall;
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    if (calls >= failFromCall) {
      throw http.ClientException('网络持续不可用', request.url);
    }
    final body = jsonEncode({
      'cursor': 100,
      'hasMore': true,
      'changes': [_upsertChange('第1页题')],
    });
    return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
  }
}

Map<String, Object?> _upsertChange(
  String question, {
  String? image,
  String? imageSha256,
  String? imagePerceptualHash,
}) => {
  'operation': 'upsert',
  'question': {
    'id': question,
    'question': question,
    'type': 'single_choice',
    'options': ['甲', '乙'],
    'correctAnswer': '甲',
    'image': ?image,
    'imageSha256': ?imageSha256,
    'imagePerceptualHash': ?imagePerceptualHash,
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

/// 在第 [failOnCall] 次请求（1 起算）抛一次瞬时网络错误，其余正常返回，
/// 用于验证「单页瞬时失败不得让整轮同步残缺」。
/// 按请求里的 cursor 返回对应页，这样重试同一 cursor 会拿到同一页（与真实服务端一致）。
class _FlakySyncClient extends http.BaseClient {
  _FlakySyncClient(this.responsesByCursor, {required this.failOnCall});
  final Map<String, Map<String, Object?>> responsesByCursor;
  final int failOnCall;
  final List<http.Request> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final copy = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    requests.add(copy);
    if (requests.length == failOnCall) {
      throw http.ClientException('瞬时网络抖动', request.url);
    }
    final cursor = request.url.queryParameters['cursor'] ?? '0';
    final body = jsonEncode(
      responsesByCursor[cursor] ??
          {
            'cursor': cursor,
            'hasMore': false,
            'changes': const <Object>[],
          },
    );
    return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
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
