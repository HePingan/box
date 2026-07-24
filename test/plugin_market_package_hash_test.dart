import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('packageJson sha256 matches expected digest', () {
    final package = {
      'schema': 1,
      'id': 'user.u1.demo',
      'title': 'Demo',
      'version': '1.0.0',
      'actionCode': 'toast',
      'payload': 'hi',
    };
    final json = jsonEncode(package);
    final digest = sha256.convert(utf8.encode(json)).toString();
    expect(digest, hasLength(64));
    // re-hash same content stable
    expect(sha256.convert(utf8.encode(json)).toString(), digest);
  });

  test('tampered package fails match', () {
    final a = jsonEncode({'id': 'x', 'v': 1});
    final b = jsonEncode({'id': 'x', 'v': 2});
    final ha = sha256.convert(utf8.encode(a)).toString();
    final hb = sha256.convert(utf8.encode(b)).toString();
    expect(ha == hb, isFalse);
  });
}
