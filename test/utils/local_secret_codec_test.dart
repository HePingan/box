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
    // 用 Json 版本：裸 decryptLegacy 在错盐下**本来就可能返回乱码**（见下一条）。
    expect(LocalSecretCodec.decryptLegacyJson(legacy, 'another-salt'), isNull);
  });

  // 回归锁：这条曾经是偶发红的（约 0.5% 的跑批会遇到）。
  //
  // 根因不是测试写得松，而是**旧格式本身没有认证**：AES-CBC + PKCS7 padding，
  // 用错误的盐解密时，末尾 padding 有约 1/256 的概率「碰巧」通过校验，
  // 于是 decryptLegacy 返回一段乱码而不是 null。实测 2000 次错盐解密里出现 9 次。
  //
  // 危险的不只是测试变红：两个调用方（account_store / remote_storage_store）
  // 一旦认了这份乱码，就会把它当作"旧数据"按新格式**重新加密写回**，
  // 把用户真实凭据覆盖成垃圾。修法是解密后校验明文形态（本仓旧密文一律是 JSON）。
  test('错盐解旧密文：批量尝试也不许返回内容（CBC 无认证的已知坑）', () {
    const legacySalt = 'box-remote-storage-v1';
    const plain = '{"accounts":["旧版本写下的凭据"]}';

    var leaked = 0;
    String? sample;
    for (var i = 0; i < 300; i++) {
      final legacy = legacyEncrypt(plain, legacySalt);
      // 裸版本：这里**允许**偶发返回乱码（这就是那条坑本身），但只做统计。
      // 真正要守的是下面那个 Json 版本必须一次都不漏。
      final validated = LocalSecretCodec.decryptLegacyJson(
        legacy,
        'another-salt',
      );
      if (validated != null) {
        leaked++;
        sample ??= validated;
      }
    }

    expect(
      leaked,
      0,
      reason: '带 JSON 校验后，错盐一次都不该解出可用的明文'
          '（漏了说明校验没生效，或 padding 碰撞被当成了成功）：$sample',
    );
  });

  test('错盐解出的乱码：token 形态校验能挡住（账号凭据那条路）', () {
    // account_store 的 token 不是 JSON，不能套 decryptLegacyJson；它用的是
    // "非空 + 无控制字符"这条形态校验。这里直接验证乱码会被它挡住。
    const legacySalt = 'box-remote-storage-v1';
    const plain = 'legacy-token-abc123';

    // 与 account_store._looksLikeToken 同口径（那边是私有的，这里复刻判据）。
    bool looksLikeToken(String s) {
      if (s.isEmpty || s.length > 4096) return false;
      for (final unit in s.codeUnits) {
        if (unit < 0x20 || (unit >= 0x7F && unit <= 0x9F)) return false;
      }
      return true;
    }

    var leaked = 0;
    for (var i = 0; i < 300; i++) {
      final legacy = legacyEncrypt(plain, legacySalt);
      final out = LocalSecretCodec.decryptLegacy(legacy, 'wrong-salt');
      if (out != null && looksLikeToken(out)) leaked++;
    }
    expect(
      leaked,
      0,
      reason: '错盐解出的乱码几乎必然带控制字符；'
          '若这里不为 0，说明 token 的形态校验挡不住，用户会被"迁移"成乱码 token',
    );
  });

  test('decryptLegacyJson 对非 JSON 明文一律拒绝（它就是那道认证）', () {
    // 用一个非 JSON 的旧密文：裸 decryptLegacy 解得出，Json 版本必须拒绝。
    const legacySalt = 'box-remote-storage-v1';
    final legacy = legacyEncrypt('this is not json at all', legacySalt);

    expect(LocalSecretCodec.decryptLegacy(legacy, legacySalt),
        'this is not json at all',
        reason: '裸版本仍保留通用能力（不做形态假设）');
    expect(LocalSecretCodec.decryptLegacyJson(legacy, legacySalt), isNull,
        reason: 'Json 版本只认 JSON 对象/数组，其余一律当"解不开"');
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
