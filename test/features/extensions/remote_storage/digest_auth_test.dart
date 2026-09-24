// 279 C5：HTTP Digest 认证的测试。
//
// 两层：协议纯逻辑（挑战解析 + 摘要计算，含 RFC 2617 官方示例向量）与客户端
// 集成（401 挑战 → 带 Digest 重试一次；流式请求体不盲目重发）。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:box/features/extensions/plugins/remote_storage/domain/digest_auth.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/webdav_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('挑战解析（C5）', () {
    test('标准头：realm/nonce/qop/opaque/algorithm', () {
      final c = DigestChallenge.tryParse(
        'Digest realm="testrealm@host.com", qop="auth,auth-int", '
        'nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093", '
        'opaque="5ccc069c403ebaf9f0171e9517f40e41"',
      );
      expect(c, isNotNull);
      expect(c!.realm, 'testrealm@host.com');
      expect(c.nonce, 'dcd98b7102dd2f0e8b11d0f600bfb0c093');
      expect(c.qop, 'auth,auth-int');
      expect(c.opaque, '5ccc069c403ebaf9f0171e9517f40e41');
      expect(c.algorithm, isNull, reason: '未给 algorithm 时按 MD5（RFC 2617 默认）');
      expect(c.unsupportedReason, isNull);
    });

    test('带 algorithm=MD5 与 stale=true', () {
      final c = DigestChallenge.tryParse(
        'Digest realm="r", nonce="n", algorithm=MD5, stale=true',
      )!;
      expect(c.algorithm, 'MD5');
      expect(c.stale, isTrue);
    });

    test('值里的逗号不被切分（qop 列表、含逗号的 realm）', () {
      final c = DigestChallenge.tryParse(
        'Digest realm="a,b", nonce="n", qop="auth,auth-int"',
      )!;
      expect(c.realm, 'a,b');
      expect(c.qop, 'auth,auth-int');
    });

    test('多挑战头里挑出 Digest', () {
      final c = DigestChallenge.tryParse(
        'Basic realm="x", Digest realm="y", nonce="z"',
      );
      expect(c?.realm, 'y');
    });

    test('不是 Digest / 缺 realm 或 nonce → null（不能瞎猜）', () {
      expect(DigestChallenge.tryParse('Basic realm="x"'), isNull);
      expect(DigestChallenge.tryParse('Digest realm="x"'), isNull);
      expect(DigestChallenge.tryParse('Digest nonce="n"'), isNull);
      expect(DigestChallenge.tryParse(null), isNull);
      expect(DigestChallenge.tryParse('   '), isNull);
    });

    test('不支持的算法 / 只给 auth-int → 给出人话原因', () {
      final sha512 = DigestChallenge.tryParse(
        'Digest realm="r", nonce="n", algorithm=SHA-512-256',
      )!;
      expect(sha512.unsupportedReason, contains('SHA-512-256'));

      final authInt = DigestChallenge.tryParse(
        'Digest realm="r", nonce="n", qop="auth-int"',
      )!;
      expect(authInt.unsupportedReason, contains('auth-int'));
    });

    test('cnonce：每次不同且为 32 位十六进制', () {
      final a = newDigestCnonce();
      final b = newDigestCnonce();
      expect(a, isNot(b));
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(a), isTrue);
    });
  });

  group('摘要计算（C5）', () {
    // RFC 2617 §3.5 的官方示例向量：逐字对照，算错一个字节都对不上。
    const rfc2617 = DigestChallenge(
      realm: 'testrealm@host.com',
      nonce: 'dcd98b7102dd2f0e8b11d0f600bfb0c093',
      qop: 'auth,auth-int',
      opaque: '5ccc069c403ebaf9f0171e9517f40e41',
    );

    test('RFC 2617 示例：response=6629fae49393a05397450978507c4ef1', () {
      final header = buildDigestAuthorization(
        challenge: rfc2617,
        username: 'Mufasa',
        password: 'Circle Of Life',
        method: 'GET',
        uri: '/dir/index.html',
        cnonce: '0a4f113b',
        nc: 1,
      );
      expect(header, contains('response="6629fae49393a05397450978507c4ef1"'));
      expect(header, startsWith('Digest '));
      expect(header, contains('username="Mufasa"'));
      expect(header, contains('realm="testrealm@host.com"'));
      expect(header, contains('uri="/dir/index.html"'));
      expect(header, contains('qop=auth'));
      expect(header, contains('nc=00000001'));
      expect(header, contains('cnonce="0a4f113b"'));
      expect(header, contains('opaque="5ccc069c403ebaf9f0171e9517f40e41"'));
    });

    test('无 qop（RFC 2069 形式）：头里不带 nc/cnonce/qop', () {
      final header = buildDigestAuthorization(
        challenge: const DigestChallenge(realm: 'r', nonce: 'n'),
        username: 'u',
        password: 'p',
        method: 'GET',
        uri: '/x',
        cnonce: 'ignored',
        nc: 1,
      );
      expect(header, contains('response="'));
      expect(header, isNot(contains('qop=')));
      expect(header, isNot(contains('nc=')));
      expect(header, isNot(contains('cnonce=')));
    });

    test('nc 递增会改变 response（服务端靠它防重放）', () {
      String at(int nc) => buildDigestAuthorization(
            challenge: rfc2617,
            username: 'Mufasa',
            password: 'Circle Of Life',
            method: 'GET',
            uri: '/dir/index.html',
            cnonce: '0a4f113b',
            nc: nc,
          );
      expect(at(1), contains('nc=00000001'));
      expect(at(1), isNot(at(2)));
      expect(at(2), contains('nc=00000002'));
    });

    test('SHA-256 挑战可用（RFC 7616 起服务端常给）', () {
      final header = buildDigestAuthorization(
        challenge: const DigestChallenge(
          realm: 'r',
          nonce: 'n',
          qop: 'auth',
          algorithm: 'SHA-256',
        ),
        username: 'u',
        password: 'p',
        method: 'PROPFIND',
        uri: '/dav/',
        cnonce: 'abc',
        nc: 1,
      );
      expect(header, contains('algorithm=SHA-256'));
      expect(header, contains('response="'));
    });

    test('MD5-sess：HA1 再叠一次 nonce/cnonce', () {
      String build(String? algorithm) => buildDigestAuthorization(
            challenge: DigestChallenge(
              realm: 'r',
              nonce: 'n',
              qop: 'auth',
              algorithm: algorithm,
            ),
            username: 'u',
            password: 'p',
            method: 'GET',
            uri: '/x',
            cnonce: 'c',
            nc: 1,
          );
      expect(build('MD5'), isNot(build('MD5-sess')));
    });

    test('只给 auth-int / 未知算法 → 抛 DigestUnsupported（不发自以为是的头）', () {
      expect(
        () => buildDigestAuthorization(
          challenge: const DigestChallenge(realm: 'r', nonce: 'n', qop: 'auth-int'),
          username: 'u',
          password: 'p',
          method: 'GET',
          uri: '/x',
          cnonce: 'c',
          nc: 1,
        ),
        throwsA(isA<DigestUnsupported>()),
      );
      expect(
        () => buildDigestAuthorization(
          challenge: const DigestChallenge(
            realm: 'r',
            nonce: 'n',
            algorithm: 'SHA-512-256',
          ),
          username: 'u',
          password: 'p',
          method: 'GET',
          uri: '/x',
          cnonce: 'c',
          nc: 1,
        ),
        throwsA(isA<DigestUnsupported>()),
      );
    });

    test('引号与反斜杠按 quoted-string 转义', () {
      final header = buildDigestAuthorization(
        challenge: const DigestChallenge(realm: 'a"b\\c', nonce: 'n'),
        username: 'u',
        password: 'p',
        method: 'GET',
        uri: '/x',
        cnonce: 'c',
        nc: 1,
      );
      expect(header, contains(r'realm="a\"b\\c"'));
    });
  });

  group('客户端集成（C5）', () {
    const challengeHeader =
        'Digest realm="dav", nonce="abc123", qop="auth", algorithm=MD5';

    WebdavClient clientWith(FakeTransport transport) => WebdavClient(
          baseUrl: 'https://dav.example.com/dav/',
          username: 'u',
          password: 'p',
          transport: transport,
        );

    test('401 + Digest 挑战 → 自动带 Digest 重试一次并成功', () async {
      final transport = FakeTransport();
      var calls = 0;
      transport.handler = (request) async {
        calls += 1;
        if (calls == 1) {
          expect(request.headers['authorization'], startsWith('Basic '));
          return const WebdavResponse(
            statusCode: 401,
            headers: {'www-authenticate': challengeHeader},
          );
        }
        return xmlResponse(propfindXml(const []));
      };

      final entries = await clientWith(transport).list('');
      expect(entries, isEmpty);
      expect(calls, 2);

      final retry = transport.requests.last;
      final auth = retry.headers['authorization']!;
      expect(auth, startsWith('Digest '));
      expect(auth, contains('username="u"'));
      expect(auth, contains('realm="dav"'));
      expect(auth, contains('nonce="abc123"'));
      expect(auth, contains('qop=auth'));
      expect(auth, contains('nc=00000001'));
      expect(auth, contains('uri="/dav/"'));
      expect(
        auth,
        isNot(contains('Basic')),
        reason: 'Basic 与 Digest 不能混在同一个头里',
      );
    });

    test('挑战被记住：后续请求第一个就带 Digest，不再吃 401', () async {
      final transport = FakeTransport();
      var digestFirstCalls = 0;
      transport.handler = (request) async {
        final auth = request.headers['authorization'] ?? '';
        if (auth.startsWith('Digest ')) {
          digestFirstCalls += 1;
          return xmlResponse(propfindXml(const []));
        }
        return const WebdavResponse(
          statusCode: 401,
          headers: {'www-authenticate': challengeHeader},
        );
      };

      final client = clientWith(transport);
      await client.list(''); // 第一次：Basic 被拒 → Digest 成功
      expect(digestFirstCalls, 1);

      await client.list(''); // 第二次：直接 Digest
      expect(digestFirstCalls, 2);
      expect(
        transport.requests.where((r) => r.headers['authorization']!.startsWith('Basic ')),
        hasLength(1),
        reason: '只有第一次该走 Basic（也就是只吃一次 401）',
      );
    });

    test('401 但没有 Digest 挑战（真·密码错）→ 不重试', () async {
      final transport = FakeTransport();
      transport.handler = (_) async => const WebdavResponse(
            statusCode: 401,
            headers: {'www-authenticate': 'Basic realm="dav"'},
          );

      await expectLater(
        clientWith(transport).list(''),
        throwsA(isA<RemoteStorageException>()),
      );
      expect(transport.requests, hasLength(1));
    });

    test('只给 auth-int → 明确报"不支持"，不发看不懂的头', () async {
      final transport = FakeTransport();
      transport.handler = (_) async => const WebdavResponse(
            statusCode: 401,
            headers: {
              'www-authenticate': 'Digest realm="dav", nonce="n", qop="auth-int"',
            },
          );

      await expectLater(
        clientWith(transport).list(''),
        throwsA(
          isA<RemoteStorageException>().having(
            (e) => e.message,
            'message',
            contains('auth-int'),
          ),
        ),
      );
      expect(transport.requests, hasLength(1), reason: '发第二次也没用，别浪费往返');
    });

    test('流式请求体（PUT 大文件）：被 401 打断后能重开流再传，内容不丢', () async {
      final transport = FakeTransport();
      var puts = 0;
      final bodies = <String>[];
      final authSeen = <String>[];
      transport.handler = (request) async {
        if (request.method != 'PUT') {
          return const WebdavResponse(statusCode: 404, headers: {});
        }
        puts += 1;
        authSeen.add(request.headers['authorization'] ?? '');
        bodies.add(await bodyTextOf(request));
        // 真实服务器：第一次（Basic）拒绝并给挑战，带 Digest 的第二次放行
        if (puts == 1) {
          return const WebdavResponse(
            statusCode: 401,
            headers: {'www-authenticate': challengeHeader},
          );
        }
        return const WebdavResponse(statusCode: 201, headers: {});
      };

      final dir = await Directory.systemTemp.createTemp('digest');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/big.bin');
      await file.writeAsBytes(Uint8List.fromList(utf8.encode('payload')));

      final client = clientWith(transport);
      await client.uploadFrom(file, 'big.bin'); // 不该抛：重开流重试后成功

      expect(puts, 2);
      expect(authSeen.first, startsWith('Basic '));
      expect(authSeen.last, startsWith('Digest '));
      expect(
        bodies,
        ['payload', 'payload'],
        reason: '两次都必须是完整内容——流式体重发时若不重开流就会传空文件',
      );
    });

    test('isRetryableTransferError 尊重显式 retryable（C5 的重试语义）', () {
      const retryMe = RemoteStorageException(
        RemoteStorageError.unauthorized,
        '服务器要求 Digest 认证（已记住认证方式，重试即可）',
        statusCode: 401,
        retryable: true,
      );
      expect(isRetryableTransferError(retryMe), isTrue);
      expect(
        isRetryableTransferError(
          const RemoteStorageException(RemoteStorageError.unauthorized, '密码错'),
        ),
        isFalse,
        reason: '没显式指定的仍按 kind 判：401 默认不重试',
      );
    });
  });
}
