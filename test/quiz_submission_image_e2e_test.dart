import 'dart:convert';
import 'dart:io';

import 'package:box/features/admin/domain/quiz_bank_models.dart';
import 'package:box/features/quiz_plugin/data/quiz_cloud_sync.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 端到端：本地带图题 -> submit 请求体 -> 审核端解析。
///
/// 用户反馈「重新提交带图的题，审核投稿没显示」，所以必须验证
/// 整条链路，而不只是各段的纯函数。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late File png;

  // 1x1 PNG 真实字节
  final pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
    '//8/AwAI/AL+hc2rNAAAAABJRU5ErkJggg==',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('quiz_e2e_');
    png = File('${tmp.path}/shot.png');
    await png.writeAsBytes(pngBytes, flush: true);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('带图投稿：请求体必须携带 data URL 像素，而不是设备本地路径', () async {
    final requests = <http.Request>[];
    final service = QuizCloudSyncService(httpClient: _CaptureClient(requests));

    await service.submit(
      serverUrl: 'https://box.example',
      token: 't',
      item: QuizBankItem(
        id: 'local-1',
        question: '这个标志是什么含义？',
        type: QuizQuestionType.singleChoice,
        options: const ['禁止通行', '允许通行'],
        correctAnswer: '禁止通行',
        imageUrl: png.path,
      ),
    );

    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    final image = body['image']?.toString() ?? '';

    expect(
      image.startsWith('data:image/png;base64,'),
      isTrue,
      reason: '提交体里必须是内联像素，实际=${image.length > 60 ? image.substring(0, 60) : image}',
    );
    expect(image.contains(png.path), isFalse, reason: '不得再发设备本地路径');
    // 像素必须能还原成原图字节
    expect(
      base64Decode(image.split(',').last),
      pngBytes,
      reason: 'data URL 解出来必须等于原始 PNG 字节',
    );
  });

  test('审核端能从提交体形态的 JSON 里解析出图片', () async {
    final requests = <http.Request>[];
    final service = QuizCloudSyncService(httpClient: _CaptureClient(requests));
    await service.submit(
      serverUrl: 'https://box.example',
      token: 't',
      item: QuizBankItem(
        id: 'local-2',
        question: '题',
        type: QuizQuestionType.singleChoice,
        options: const ['甲', '乙'],
        correctAnswer: '甲',
        imageUrl: png.path,
      ),
    );
    final submitted = jsonDecode(requests.single.body) as Map<String, dynamic>;

    // 服务端典型回包：把投稿题包在 question 里
    final adminJson = <String, dynamic>{
      'id': 'sub-1',
      'status': 'pending',
      'question': submitted,
    };
    final parsed = QuizBankSubmission.fromJson(adminJson);
    expect(
      parsed.question.image.startsWith('data:image/png;base64,'),
      isTrue,
      reason: '审核端必须拿到内联像素',
    );

    // 服务端另一种形态：图片平铺在顶层
    final flatJson = <String, dynamic>{
      'id': 'sub-2',
      'status': 'pending',
      'question': {...submitted}..remove('image'),
      'image': submitted['image'],
    };
    final parsedFlat = QuizBankSubmission.fromJson(flatJson);
    expect(
      parsedFlat.question.image.startsWith('data:image/png;base64,'),
      isTrue,
      reason: '顶层 image 也要能被捡起来',
    );
  });

  test('无图投稿不得凭空多出 image 字段', () async {
    final requests = <http.Request>[];
    final service = QuizCloudSyncService(httpClient: _CaptureClient(requests));
    await service.submit(
      serverUrl: 'https://box.example',
      token: 't',
      item: const QuizBankItem(
        id: 'local-3',
        question: '无图题',
        type: QuizQuestionType.singleChoice,
        options: ['甲', '乙'],
        correctAnswer: '甲',
      ),
    );
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body.containsKey('image'), isFalse);
  });

  test('文件已被删除时不得提交本地路径（宁可无图）', () async {
    await png.delete();
    final requests = <http.Request>[];
    final service = QuizCloudSyncService(httpClient: _CaptureClient(requests));
    await service.submit(
      serverUrl: 'https://box.example',
      token: 't',
      item: QuizBankItem(
        id: 'local-4',
        question: '图没了',
        type: QuizQuestionType.singleChoice,
        options: const ['甲', '乙'],
        correctAnswer: '甲',
        imageUrl: png.path,
      ),
    );
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body.containsKey('image'), isFalse);
  });
}

class _CaptureClient extends http.BaseClient {
  _CaptureClient(this.requests);

  final List<http.Request> requests;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) requests.add(request);
    return http.StreamedResponse(
      Stream.value(
        utf8.encode(jsonEncode({'id': 'sub-x', 'status': 'pending'})),
      ),
      200,
      request: request,
    );
  }
}
