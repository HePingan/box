import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 本地启动 image_platform_quota_server，验证 incomplete 筛选/批量与已发布题补图。
///
/// 注意：这是纯 dart:io 集成测试，绝不能调用
/// TestWidgetsFlutterBinding.ensureInitialized()——它会劫持 HttpClient
/// 让所有请求返回 400，导致就绪探测永远拿不到 200 而空转到超时。
void main() {
  late Process server;
  late int port;
  final stderrText = StringBuffer();
  final statePath = File(
    '${Directory.systemTemp.path}/box-quiz-incomplete-bulk-state.json',
  );
  const adminToken = 'test-admin-token';

  setUpAll(() async {
    if (await statePath.exists()) await statePath.delete();
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    port = socket.port;
    await socket.close();

    final dartCommand = Platform.isWindows ? 'dart.bat' : 'dart';
    server = await Process.start(
      dartCommand,
      [
        'run',
        'tool/image_platform_quota_server.dart',
        '--host',
        '127.0.0.1',
        '--port',
        '$port',
      ],
      workingDirectory: Directory.current.path,
      environment: {
        ...Platform.environment,
        'IMAGE_STATE_PATH': statePath.path,
        'IMAGE_ADMIN_TOKEN': adminToken,
        'BOX_ADMIN_PASSWORD': '',
      },
    );

    server.stderr.transform(utf8.decoder).listen(stderrText.write);
    final stdoutLines = server.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asBroadcastStream();

    // 监听 stdout 的就绪行判就绪，比 HTTP 探测更可靠（server 首次编译较慢）。
    await stdoutLines
        .firstWhere(
          (line) => line.contains('Box image platform quota server running'),
        )
        .timeout(
          const Duration(seconds: 60),
          onTimeout: () =>
              fail('server did not start in 60s: $stderrText'),
        );
  });

  tearDownAll(() async {
    server.kill(ProcessSignal.sigterm);
    if (await statePath.exists()) await statePath.delete();
  });

  Future<Map<String, dynamic>> api(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final client = HttpClient();
    final uri = Uri.parse('http://127.0.0.1:$port$path');
    final req = await client.openUrl(method, uri);
    req.headers.set('x-admin-token', adminToken);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    client.close(force: true);
    final decoded = text.trim().isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(text) as Map);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      fail('$method $path => ${res.statusCode} $text');
    }
    return decoded;
  }

  test('incomplete filter + bulk category + discard + published image', () async {
    final importBody = {
      'mode': 'published',
      'items': [
        {
          'question': '如图所示，缺答案题甲',
          'type': 'single_choice',
          'options': ['A', 'B'],
          'correctAnswer': '',
          'category': '',
        },
        {
          'question': '如图所示，缺答案题乙',
          'type': 'single_choice',
          'options': ['C', 'D'],
          'correctAnswer': '',
          'category': '',
        },
        {
          'question': '完整题应直接入库',
          'type': 'true_false',
          'options': ['正确', '错误'],
          'correctAnswer': '正确',
          'category': '驾驶理论题库-20260719',
          'image': '/api/quiz/images/placeholder.png',
        },
      ],
    };
    final imported = await api('POST', '/admin/quiz/import', body: importBody);
    expect(imported['invalid'], greaterThanOrEqualTo(2));

    final all = await api('GET', '/admin/quiz/incomplete');
    final items = (all['items'] as List).cast<Map>();
    expect(items.length, greaterThanOrEqualTo(2));
    final ids = items.map((e) => e['id'].toString()).toList();

    final missing = await api(
      'GET',
      '/admin/quiz/incomplete?filter=missing_answer',
    );
    expect((missing['items'] as List).length, greaterThanOrEqualTo(2));

    final categorized = await api(
      'POST',
      '/admin/quiz/incomplete/bulk',
      body: {
        'action': 'set_category',
        'ids': ids.take(1).toList(),
        'category': '驾驶理论题库-20260719',
      },
    );
    expect(categorized['updated'], 1);

    final discarded = await api(
      'POST',
      '/admin/quiz/incomplete/bulk',
      body: {
        'action': 'discard',
        'ids': ids.skip(1).take(1).toList(),
      },
    );
    expect(discarded['removed'], 1);

    final questions = await api('GET', '/admin/quiz/questions?search=完整题');
    final list = (questions['questions'] as List?) ?? const [];
    expect(list, isNotEmpty);
    final qid = (list.first as Map)['id'].toString();
    final patched = await api(
      'PATCH',
      '/admin/quiz/questions/$qid',
      body: {'image': '/api/quiz/images/demo-patched.png'},
    );
    final image = patched['image']?.toString() ??
        ((patched['question'] is Map)
            ? (patched['question'] as Map)['image']?.toString()
            : null);
    expect(image, '/api/quiz/images/demo-patched.png');
  });
}
