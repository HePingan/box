import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('image platform quota server exposes root health payload', () async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();

    final stateFile = File(
      '${Directory.systemTemp.path}/box_health_${DateTime.now().microsecondsSinceEpoch}.json',
    );
    final dartCommand = Platform.isWindows ? 'dart.bat' : 'dart';
    final process = await Process.start(
      dartCommand,
      [
        'run',
        'tool/image_platform_quota_server.dart',
        '--host',
        '127.0.0.1',
        '--port',
        '$port',
      ],
      environment: {
        'IMAGE_STATE_PATH': stateFile.path,
        'BOX_ADMIN_PASSWORD': 'test-admin-password',
      },
      includeParentEnvironment: true,
    );

    final stdoutLines = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asBroadcastStream();
    final stderrText = StringBuffer();
    final stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .listen(stderrText.write);

    try {
      await stdoutLines.firstWhere(
        (line) => line.contains('Box image platform quota server running'),
      );

      final client = HttpClient();
      try {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/'),
        );
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final decoded = jsonDecode(body) as Map<String, dynamic>;

        expect(response.statusCode, HttpStatus.ok);
        expect(decoded['ok'], isTrue);
        expect(decoded['service'], 'box-image-platform');
        expect(decoded['message'], contains('running'));
      } finally {
        client.close(force: true);
      }
    } finally {
      process.kill();
      await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -1,
      );
      await stderrSubscription.cancel();
      if (await stateFile.exists()) await stateFile.delete();
    }

    final stderrOutput = stderrText.toString();
    expect(stderrOutput, isNot(contains('Unhandled request error')));
  });
}
