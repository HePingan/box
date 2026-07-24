import 'package:box/novel/core/wtzw_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WtzwCrypto', () {
    test('md5Sign produces deterministic hash', () {
      final params = <String, dynamic>{'a': '1', 'b': '2'};
      final first = WtzwCrypto.md5Sign(params);
      final second = WtzwCrypto.md5Sign(params);
      expect(first, second);
      expect(first, isA<String>());
      expect(first.length, 32);
    });

    test('withParamSign injects sign field', () {
      final params = {'a': '1'};
      final signed = WtzwCrypto.withParamSign(params);
      expect(signed.containsKey('sign'), isTrue);
      expect(signed['a'], '1');
    });

    test('decryptChapterContent round trips through encryptChapterContent', () {
      const plain = 'Hello 阅读助手';
      final encrypted = WtzwCrypto.encryptChapterContent(plain);
      final decrypted = WtzwCrypto.decryptChapterContent(encrypted);
      expect(decrypted, plain);
    });

    test('decryptChapterContent returns empty for empty input', () {
      expect(WtzwCrypto.decryptChapterContent(''), '');
      expect(WtzwCrypto.decryptChapterContent('   '), '   ');
    });

    test('decryptChapterContent returns raw on invalid base64', () {
      const raw = 'not-valid-base64!!!';
      expect(WtzwCrypto.decryptChapterContent(raw), raw);
    });
  });
}
