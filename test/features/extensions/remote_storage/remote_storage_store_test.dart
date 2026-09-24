// 远程存储凭据持久化单测：密文落 SharedPreferences（每安装密钥 + AES-GCM），
// 明文不得落盘；随机 nonce 保证同一账户两次保存密文不同；
// 旧格式（固定盐 AES-CBC）密文仍可读并自动迁移。

import 'dart:convert';

import 'package:box/features/extensions/plugins/remote_storage/data/remote_storage_store.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/legacy_cipher.dart';
import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('保存后读取，全字段一致（含密码）', () async {
    final store = RemoteStorageStore();
    final account = testAccount(
      tlsMode: RemoteTlsMode.allow,
      allowBadCert: true,
      showSystemFolders: true,
      createdAt: 42,
    );
    await store.saveAccounts([account]);

    final loaded = await store.loadAccounts();
    expect(loaded, hasLength(1));
    expect(loaded.first.id, account.id);
    expect(loaded.first.baseUrl, account.baseUrl);
    expect(loaded.first.username, account.username);
    expect(loaded.first.password, account.password);
    expect(loaded.first.tlsMode, RemoteTlsMode.allow);
    expect(loaded.first.allowBadCert, isTrue);
    expect(loaded.first.createdAt, 42);
  });

  test('落盘内容为密文：不含用户名/密码明文', () async {
    final store = RemoteStorageStore();
    await store.saveAccounts([
      testAccount(username: 'user@example.com', password: 'super-secret'),
    ]);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(RemoteStorageStore.accountsKey);
    expect(raw, isNotNull);
    expect(raw, isNotEmpty);
    expect(raw, isNot(contains('user@example.com')));
    expect(raw, isNot(contains('super-secret')));
    expect(raw, isNot(contains('"baseUrl"')));

    // 新格式：`B2` 前缀 + base64(nonce ‖ 密文+认证标签)。
    expect(raw!.startsWith('B2'), isTrue);
    final decoded = base64.decode(raw.substring(2));
    expect(decoded.length, greaterThan(12), reason: '12 字节 nonce + 密文');
  });

  test('随机 IV：两次保存密文不同，解密结果一致', () async {
    final store = RemoteStorageStore();
    final account = testAccount();
    await store.saveAccounts([account]);
    final first = (await SharedPreferences.getInstance())
        .getString(RemoteStorageStore.accountsKey);

    await store.saveAccounts([account]);
    final second = (await SharedPreferences.getInstance())
        .getString(RemoteStorageStore.accountsKey);

    expect(first, isNot(second));
    final loaded = await store.loadAccounts();
    expect(loaded.single.password, account.password);
  });

  test('无数据 / 空串 / 非法密文 / 非 JSON 均返回空列表', () async {
    final store = RemoteStorageStore();
    expect(await store.loadAccounts(), isEmpty);

    SharedPreferences.setMockInitialValues(<String, Object>{
      RemoteStorageStore.accountsKey: '',
    });
    expect(await store.loadAccounts(), isEmpty);

    SharedPreferences.setMockInitialValues(<String, Object>{
      RemoteStorageStore.accountsKey: 'not-base64!!!',
    });
    expect(await store.loadAccounts(), isEmpty);

    // 合法 base64 但解密/JSON 失败（随机字节）。
    final garbage = base64.encode(List<int>.generate(48, (i) => i * 7 % 256));
    SharedPreferences.setMockInitialValues(<String, Object>{
      RemoteStorageStore.accountsKey: garbage,
    });
    expect(await store.loadAccounts(), isEmpty);
  });

  test('多账户保存与顺序保持', () async {
    final store = RemoteStorageStore();
    await store.saveAccounts([
      testAccount(id: 'rs_a', label: 'A'),
      testAccount(id: 'rs_b', label: 'B'),
    ]);
    final loaded = await store.loadAccounts();
    expect(loaded.map((a) => a.id).toList(), ['rs_a', 'rs_b']);
  });

  test('旧格式（固定盐 CBC）密文：能读出账户并自动迁移为新格式', () async {
    final account = testAccount(id: 'rs_old', label: '旧版', password: 'old-pass');
    final legacy = legacyEncrypt(
      jsonEncode([account.toJson()]),
      kRemoteStorageLegacySalt,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      RemoteStorageStore.accountsKey: legacy,
    });

    final store = RemoteStorageStore();
    final loaded = await store.loadAccounts();

    expect(loaded, hasLength(1), reason: '升级后不能丢掉已保存的账户');
    expect(loaded.single.id, 'rs_old');
    expect(loaded.single.password, 'old-pass');

    // 懒迁移：盘上已换成新格式，再次读取不用再走兼容分支。
    final raw = (await SharedPreferences.getInstance())
        .getString(RemoteStorageStore.accountsKey)!;
    expect(raw, isNot(legacy));
    expect(raw, startsWith('B2'));
    expect((await store.loadAccounts()).single.password, 'old-pass');
  });

  test('旧格式密文但缺密钥材料：旧格式仍可读（与每安装密钥无关）', () async {
    final legacy = legacyEncrypt(
      jsonEncode([testAccount(id: 'rs_only_legacy').toJson()]),
      kRemoteStorageLegacySalt,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      RemoteStorageStore.accountsKey: legacy,
    });

    final loaded = await RemoteStorageStore().loadAccounts();
    expect(loaded.single.id, 'rs_only_legacy');
  });
}
