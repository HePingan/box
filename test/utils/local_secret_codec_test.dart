// 本地密文编解码单测（C1）：每安装密钥 + AES-GCM 认证 + 旧格式兼容读。

import 'dart:convert';

import 'package:box/utils/local_secret_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'legacy_cipher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('加解密往返：ASCII / 中文 / 长文本 / 空串', () async {
    final codec = await LocalSecretCodec.open('remote-storage');

    for (final text in <String>[
      'hello',
      '应用密码：中文·带空格 ',
      'x' * 5000,
      '',
    ]) {
      final encoded = codec.encrypt(text);
      expect(encoded.startsWith('B2'), isTrue, reason: '新格式带 B2 前缀');
      expect(codec.decrypt(encoded), text);
    }
  });

  test('密文不含明文；同一明文两次密文不同（随机 nonce）', () async {
    final codec = await LocalSecretCodec.open('remote-storage');
    const secret = 'super-secret-app-password';

    final first = codec.encrypt(secret);
    final second = codec.encrypt(secret);

    expect(first, isNot(contains(secret)));
    expect(second, isNot(contains(secret)));
    expect(first, isNot(second));
    expect(codec.decrypt(first), secret);
    expect(codec.decrypt(second), secret);
  });

  test('密文被改动一位 → 解密返回 null（GCM 认证，不是解出乱码）', () async {
    final codec = await LocalSecretCodec.open('remote-storage');
    final encoded = codec.encrypt('tamper-me');
    final raw = base64.decode(encoded.substring(2));

    for (final index in <int>[0, 12, raw.length - 1]) {
      final broken = List<int>.from(raw);
      broken[index] = broken[index] ^ 0x01;
      expect(
        codec.decrypt('B2${base64.encode(broken)}'),
        isNull,
        reason: '改动第 $index 字节后必须拒绝',
      );
    }
  });

  test('不同 context 的密钥不同：另一模块解不开', () async {
    final storage = await LocalSecretCodec.open('remote-storage');
    final account = await LocalSecretCodec.open('account');

    final encoded = storage.encrypt('only-for-storage');
    expect(storage.decrypt(encoded), 'only-for-storage');
    expect(account.decrypt(encoded), isNull);
  });

  test('每安装随机密钥：同一安装内密钥稳定，清掉安装数据后解不开旧密文', () async {
    final first = await LocalSecretCodec.open('remote-storage');
    final encoded = first.encrypt('per-install-key');

    final prefs = await SharedPreferences.getInstance();
    final material = prefs.getString(kLocalKeyMaterialPrefsKey);
    expect(material, isNotNull);
    expect(base64.decode(material!).length, 32, reason: '32 字节随机材料');

    // 同一安装再次打开：材料复用 → 仍能解开。
    final reopened = await LocalSecretCodec.open('remote-storage');
    expect(reopened.decrypt(encoded), 'per-install-key');

    // 模拟换机/清数据（密文被恢复但密钥材料不在）：解不开，而不是用固定密钥
    // 解出别人的凭据。
    SharedPreferences.setMockInitialValues(<String, Object>{
      'someOther.key': 'x',
    });
    final otherInstall = await LocalSecretCodec.open('remote-storage');
    expect(otherInstall.decrypt(encoded), isNull);
  });

  test('looksLegacy：旧格式为真、新格式为假', () async {
    final codec = await LocalSecretCodec.open('remote-storage');
    expect(LocalSecretCodec.looksLegacy(codec.encrypt('x')), isFalse);
    expect(
      LocalSecretCodec.looksLegacy(legacyEncrypt('x', 'box-remote-storage-v1')),
      isTrue,
    );
  });

  test('decryptLegacy 能解出旧密文；新旧格式互不误判', () async {
    const legacySalt = 'box-remote-storage-v1';
    const plain = '{"accounts":["旧版本写下的凭据"]}';
    final legacy = legacyEncrypt(plain, legacySalt);

    expect(LocalSecretCodec.decryptLegacy(legacy, legacySalt), plain);

    // 新格式解不了旧密文，旧格式也解不了新格式（各走各的分支）。
    final codec = await LocalSecretCodec.open('remote-storage');
    expect(codec.decrypt(legacy), isNull);

    // 盐不对 → 解不出来（不会拿错盐的密钥解出垃圾）。
    expect(LocalSecretCodec.decryptLegacy(legacy, 'another-salt'), isNull);
  });

  test('非法输入一律返回 null，不抛异常', () async {
    final codec = await LocalSecretCodec.open('remote-storage');

    expect(codec.decrypt(''), isNull);
    expect(codec.decrypt('not-a-v2-value'), isNull);
    expect(codec.decrypt('B2'), isNull);
    expect(codec.decrypt('B2!!!not-base64!!!'), isNull);
    expect(codec.decrypt('B2${base64.encode(List<int>.filled(8, 0))}'), isNull);
    expect(LocalSecretCodec.decryptLegacy('', 's'), isNull);
    expect(LocalSecretCodec.decryptLegacy('!!!', 's'), isNull);
  });
}
