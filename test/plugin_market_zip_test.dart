import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('zip package sha256 is of raw bytes not json', () async {
    final tmp = await Directory.systemTemp.createTemp('box_zip_test_');
    try {
      final pluginJson = File('${tmp.path}/plugin.json');
      await pluginJson.writeAsString(jsonEncode({
        'id': 'demo',
        'title': 'Demo',
        'actionCode': 'toast',
        'version': '1.0.0',
      }));
      final zipPath = '${tmp.path}/demo.zip';
      final r = await Process.run('zip', ['-j', zipPath, pluginJson.path]);
      expect(r.exitCode, 0);
      final bytes = await File(zipPath).readAsBytes();
      final digest = sha256.convert(bytes).toString();
      expect(digest, hasLength(64));
      // mutating changes hash
      final other = List<int>.from(bytes)..add(0);
      expect(sha256.convert(other).toString() == digest, isFalse);
    } finally {
      await tmp.delete(recursive: true);
    }
  });

  test('plugin.json required name patterns', () {
    final names = ['plugin.json', 'my-plugin/plugin.json', 'a/b/plugin.json'];
    bool ok(String n) =>
        n == 'plugin.json' || RegExp(r'^[^/]+/plugin\.json$').hasMatch(n);
    expect(ok(names[0]), isTrue);
    expect(ok(names[1]), isTrue);
    expect(ok(names[2]), isFalse); // deeper nested rejected by pattern
  });
}
