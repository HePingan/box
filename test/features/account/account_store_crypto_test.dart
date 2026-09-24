// 账号凭据（token / 用户信息）加解密与迁移单测（C1）。
//
// 覆盖三件事：
// 1. 新格式（每安装密钥 + AES-GCM）落盘为密文、往返一致；
// 2. 密文被篡改时解不出来（而不是把乱码当 token 用）；
// 3. 旧格式（固定盐 AES-CBC）的存量凭据能读出来并自动迁移——用户升级不被登出。

import 'dart:convert';

import 'package:box/features/account/data/account_store.dart';
import 'package:box/features/account/domain/account_models.dart';
import 'package:box/utils/local_secret_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/legacy_cipher.dart';

BoxAccountSession _session({
  String token = 'tok-abc-123',
  String serverUrl = 'https://box.example.com',
}) {
  return BoxAccountSession(
    serverUrl: serverUrl,
    token: token,
    user: const BoxAccountUser(
      id: 'u1',
      username: 'alice',
      nickname: 'Alice',
      role: 'user',
      status: 'normal',
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('保存 / 读取往返：token 与用户信息一致', () async {
    final store = BoxAccountStore();
    await store.saveSession(_session());

    final loaded = await store.loadSession();
    expect(loaded, isNotNull);
    expect(loaded!.token, 'tok-abc-123');
    expect(loaded.serverUrl, contains('box.example.com'));
    expect(loaded.user.username, 'alice');
  });

  test('落盘为密文：不含 token 明文，且为新格式（B2 前缀）', () async {
    final store = BoxAccountStore();
    await store.saveSession(_session(token: 'tok-plain-must-not-persist'));

    final prefs = await SharedPreferences.getInstance();
    final tokenEnc = prefs.getString('boxAccount.tokenEnc');
    final userEnc = prefs.getString('boxAccount.userJsonEnc');

    expect(tokenEnc, isNotNull);
    expect(tokenEnc, startsWith('B2'));
    expect(userEnc, startsWith('B2'));
    expect(tokenEnc, isNot(contains('tok-plain-must-not-persist')));
    expect(userEnc, isNot(contains('alice')));
    // 密钥材料是每安装随机的 32 字节。
    expect(
      base64.decode(prefs.getString(kLocalKeyMaterialPrefsKey)!).length,
      32,
    );
  });

  test('密文被篡改 → loadSession 返回 null（不会把乱码当 token）', () async {
    final store = BoxAccountStore();
    await store.saveSession(_session());

    final prefs = await SharedPreferences.getInstance();
    final material = prefs.getString(kLocalKeyMaterialPrefsKey)!;
    final serverUrl = prefs.getString('boxAccount.serverUrl')!;
    final tokenEnc = prefs.getString('boxAccount.tokenEnc')!;
    final userEnc = prefs.getString('boxAccount.userJsonEnc')!;

    final raw = base64.decode(tokenEnc.substring(2));
    raw[raw.length ~/ 2] = raw[raw.length ~/ 2] ^ 0x01;
    SharedPreferences.setMockInitialValues(<String, Object>{
      kLocalKeyMaterialPrefsKey: material,
      'boxAccount.serverUrl': serverUrl,
      'boxAccount.tokenEnc': 'B2${base64.encode(raw)}',
      'boxAccount.userJsonEnc': userEnc,
    });

    expect(await store.loadSession(), isNull);
  });

  test('旧格式凭据（固定盐 CBC）：能读出会话，并自动迁移为新格式', () async {
    final session = _session(token: 'legacy-token', serverUrl: 'https://old.example.com');
    SharedPreferences.setMockInitialValues(<String, Object>{
      'boxAccount.serverUrl': 'https://old.example.com',
      'boxAccount.tokenEnc':
          legacyEncrypt(session.token, 'box-account-store-v1'),
      'boxAccount.userJsonEnc': legacyEncrypt(
        jsonEncode(session.user.toJson()),
        'box-account-store-v1',
      ),
    });

    final store = BoxAccountStore();
    final loaded = await store.loadSession();

    expect(loaded, isNotNull, reason: '升级后不能被登出');
    expect(loaded!.token, 'legacy-token');
    expect(loaded.user.username, 'alice');

    // 懒迁移：盘上已经是新格式，下次读不用再走兼容分支。
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('boxAccount.tokenEnc'), startsWith('B2'));
    expect(prefs.getString('boxAccount.userJsonEnc'), startsWith('B2'));
    expect((await store.loadSession())!.token, 'legacy-token');
  });

  test('旧格式但密钥材料已被清掉：旧密文仍可读（兼容分支不依赖新密钥）', () async {
    final session = _session(token: 'legacy-only');
    SharedPreferences.setMockInitialValues(<String, Object>{
      'boxAccount.serverUrl': 'https://old.example.com',
      'boxAccount.tokenEnc': legacyEncrypt(session.token, 'box-account-store-v1'),
      'boxAccount.userJsonEnc': legacyEncrypt(
        jsonEncode(session.user.toJson()),
        'box-account-store-v1',
      ),
    });

    final loaded = await BoxAccountStore().loadSession();
    expect(loaded?.token, 'legacy-only');
  });

  test('clearSession：清掉凭据（默认保留服务器地址）', () async {
    final store = BoxAccountStore();
    await store.saveSession(_session());
    await store.clearSession();

    expect(await store.loadSession(), isNull);
    expect(await store.loadServerUrl(), contains('box.example.com'));

    await store.saveSession(_session());
    await store.clearSession(keepServerUrl: false);
    expect(
      await store.loadServerUrl(),
      BoxAccountDefaults.normalizeServerUrl(''),
      reason: '空值回落到默认服务器（应用既有语义）',
    );
  });

  test('非 JSON / 空值 / 缺字段不崩，返回 null', () async {
    final store = BoxAccountStore();
    expect(await store.loadSession(), isNull);

    final material = base64.encode(List<int>.generate(32, (i) => i));
    final codec = await _codecWith(material, 'account');
    SharedPreferences.setMockInitialValues(<String, Object>{
      kLocalKeyMaterialPrefsKey: material,
      'boxAccount.serverUrl': 'https://box.example.com',
      'boxAccount.tokenEnc': codec.encrypt('tok'),
      'boxAccount.userJsonEnc': codec.encrypt('not-json'),
    });
    expect(await store.loadSession(), isNull);
  });
}

/// 用给定的密钥材料构造 codec（模拟"同一安装"）。
Future<LocalSecretCodec> _codecWith(String material, String context) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    kLocalKeyMaterialPrefsKey: material,
  });
  return LocalSecretCodec.open(context);
}
