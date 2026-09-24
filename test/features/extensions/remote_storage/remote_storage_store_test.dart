// 远程存储凭据持久化单测：密文落 SharedPreferences（每安装密钥 + AES-GCM），
// 明文不得落盘；随机 nonce 保证同一账户两次保存密文不同；
// 旧格式（固定盐 AES-CBC）密文仍可读并自动迁移。

import 'dart:convert';

import 'package:box/features/extensions/plugins/remote_storage/data/remote_storage_store.dart';
import 'package:box/features/extensions/plugins/remote_storage/data/playback_progress_store.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/playback_progress.dart';
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

  group('浏览页偏好（283 D2）', () {
    test('排序字段：存了读回来一致；没存过/空串当没存', () async {
      final store = RemoteStorageStore();

      expect(await store.loadBrowserSortFieldName(), isNull, reason: '未存过');

      await store.saveBrowserSortFieldName('size');
      expect(await store.loadBrowserSortFieldName(), 'size');

      await store.saveBrowserSortFieldName('');
      expect(await store.loadBrowserSortFieldName(), isNull, reason: '空串不算偏好');
    });

    test('滚动位置：往返一致（含多目录）', () async {
      final store = RemoteStorageStore();

      expect(await store.loadBrowserScrollOffsets(), isEmpty);

      await store.saveBrowserScrollOffsets({
        'acc\u0000/': 120.5,
        'acc\u0000/照片': 4096.0,
      });

      final loaded = await store.loadBrowserScrollOffsets();
      expect(loaded['acc\u0000/'], 120.5);
      expect(loaded['acc\u0000/照片'], 4096.0);
    });

    test('超过上限：只保留最后 200 条（Map 是插入序，丢最早的）', () async {
      final store = RemoteStorageStore();
      final offsets = <String, double>{
        for (var i = 0; i < RemoteStorageStore.kMaxRememberedScrollOffsets + 50; i++)
          'acc\u0000/dir$i': i.toDouble(),
      };

      await store.saveBrowserScrollOffsets(offsets);
      final loaded = await store.loadBrowserScrollOffsets();

      expect(loaded.length, RemoteStorageStore.kMaxRememberedScrollOffsets);
      expect(loaded.containsKey('acc\u0000/dir0'), isFalse, reason: '最早的最先丢');
      expect(
        loaded.containsKey('acc\u0000/dir249'),
        isTrue,
        reason: '最近的必须留住',
      );
    });

    test('坏数据一律当空：不抛异常、不拖垮列表', () async {
      final store = RemoteStorageStore();

      SharedPreferences.setMockInitialValues(<String, Object>{
        RemoteStorageStore.browserScrollOffsetsKey: '{"a": 1.5, "b": "x", "c": -3, "d": null}',
      });
      final parsed = await store.loadBrowserScrollOffsets();
      expect(parsed, {'a': 1.5}, reason: '只留合法正数，其余丢弃');

      SharedPreferences.setMockInitialValues(<String, Object>{
        RemoteStorageStore.browserScrollOffsetsKey: '这不是 JSON',
      });
      expect(await store.loadBrowserScrollOffsets(), isEmpty);

      SharedPreferences.setMockInitialValues(<String, Object>{
        RemoteStorageStore.browserScrollOffsetsKey: '[1, 2, 3]',
      });
      expect(await store.loadBrowserScrollOffsets(), isEmpty, reason: '不是对象');
    });

    test('无穷大/负数偏移不写盘（滚不到的位置没意义）', () async {
      final store = RemoteStorageStore();
      await store.saveBrowserScrollOffsets({
        'ok': 10,
        'inf': double.infinity,
        'nan': double.nan,
        'neg': -5,
      });

      final loaded = await store.loadBrowserScrollOffsets();
      expect(loaded, {'ok': 10.0});
    });
  });

  group('删账户清理本地残留（284 P1）', () {
    const progress = RemotePlaybackProgressStore();

    test('播放进度：只清该账户的键', () async {
      final a = testAccount(id: 'accA');
      final b = testAccount(id: 'accB');
      await progress.save(
        a,
        '/v1.mp4',
        position: const Duration(minutes: 5),
        duration: const Duration(minutes: 30),
      );
      await progress.save(
        a,
        '/v2.mp4',
        position: const Duration(minutes: 6),
        duration: const Duration(minutes: 30),
      );
      await progress.save(
        b,
        '/v1.mp4',
        position: const Duration(minutes: 7),
        duration: const Duration(minutes: 30),
      );

      expect(await progress.clearAccount('accA'), 2);
      expect(await progress.positionFor(a, '/v1.mp4'), isNull);
      expect(await progress.positionFor(a, '/v2.mp4'), isNull);
      expect(
        await progress.positionFor(b, '/v1.mp4'),
        isNotNull,
        reason: '别的账户不受影响',
      );
    });

    test('播放进度：前缀按 | 收边，accA 不会清到 accAA', () async {
      final a = testAccount(id: 'accA');
      final aa = testAccount(id: 'accAA');
      await progress.save(
        a,
        '/v.mp4',
        position: const Duration(minutes: 5),
        duration: const Duration(minutes: 30),
      );
      await progress.save(
        aa,
        '/v.mp4',
        position: const Duration(minutes: 5),
        duration: const Duration(minutes: 30),
      );

      expect(await progress.clearAccount('accA'), 1);
      expect(await progress.positionFor(aa, '/v.mp4'), isNotNull);
    });

    test('播放进度：前缀与键格式同源（改键格式不会让清理静默失效）', () {
      expect(
        playbackProgressKey('accA', '/v.mp4'),
        startsWith(playbackProgressKeyPrefix('accA')),
      );
      expect(
        playbackProgressKey('accB', '/v.mp4'),
        isNot(startsWith(playbackProgressKeyPrefix('accA'))),
      );
    });

    test('播放进度：没有该账户的键时返回 0', () async {
      expect(await progress.clearAccount('accNobody'), 0);
    });

    test('滚动位置：只清该账户的条目，别的账户保留', () async {
      final store = RemoteStorageStore();
      await store.saveBrowserScrollOffsets(<String, double>{
        'accA|/photos': 120,
        'accAA|/photos': 30,
        'accB|/docs': 5,
      });

      expect(await store.clearBrowserScrollOffsetsForAccount('accA'), 1);

      final left = await store.loadBrowserScrollOffsets();
      expect(left.keys.toSet(), <String>{'accAA|/photos', 'accB|/docs'});
      expect(left['accAA|/photos'], 30);
    });

    test('滚动位置：无匹配时返回 0 且不改动存档', () async {
      final store = RemoteStorageStore();
      await store.saveBrowserScrollOffsets(<String, double>{'accB|/docs': 5});
      expect(await store.clearBrowserScrollOffsetsForAccount('accA'), 0);
      expect(await store.loadBrowserScrollOffsets(), <String, double>{
        'accB|/docs': 5,
      });
    });
  });

  group('播放倍速偏好（284 P4）', () {
    test('没存过 → 1×（默认不能是 0）', () async {
      final store = RemoteStorageStore();
      expect(await store.loadPlaybackSpeed(), 1);
    });

    test('存了读回来一致', () async {
      final store = RemoteStorageStore();
      await store.savePlaybackSpeed(1.5);
      expect(await store.loadPlaybackSpeed(), 1.5);
    });

    test('坏数据（不在档位表里）→ 回落 1×', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        RemoteStorageStore.playbackSpeedKey: 0.3,
      });
      final store = RemoteStorageStore();
      expect(
        await store.loadPlaybackSpeed(),
        1,
        reason: '0 或负数会让播放器卡住不动，必须拦住',
      );
    });

    test('写非法档位不落盘（保持原值）', () async {
      final store = RemoteStorageStore();
      await store.savePlaybackSpeed(1.25);
      await store.savePlaybackSpeed(3);
      expect(await store.loadPlaybackSpeed(), 1.25);
    });
  });

  group('目录快照（284 D7）', () {
    late RemoteStorageStore store;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      store = RemoteStorageStore();
    });

    test('存了读回来一致（按账户+目录分开）', () async {
      await store.saveDirSnapshot('accA', '相册', const [
        RemoteStorageEntry(name: 'a.jpg', path: '相册/a.jpg', isDirectory: false, size: 10),
      ]);

      final snapshot = await store.loadDirSnapshot('accA', '相册');
      expect(snapshot, isNotNull);
      expect(snapshot!.entries.single.name, 'a.jpg');

      expect(await store.loadDirSnapshot('accA', '视频'), isNull);
      expect(await store.loadDirSnapshot('accB', '相册'), isNull);
    });

    test('根目录用 / 作键，不会和别的目录混', () async {
      await store.saveDirSnapshot('accA', '', const [
        RemoteStorageEntry(name: 'root.txt', path: 'root.txt', isDirectory: false),
      ]);

      expect((await store.loadDirSnapshot('accA', ''))!.entries.single.name, 'root.txt');
      expect(await store.loadDirSnapshot('accA', '/'), isNotNull);
    });

    test('条目数超上限：不存快照（截断后的列表更容易骗人）', () async {
      final many = <RemoteStorageEntry>[
        for (var i = 0; i <= kDirSnapshotMaxEntries; i++)
          RemoteStorageEntry(name: 'f$i', path: 'f$i', isDirectory: false),
      ];

      await store.saveDirSnapshot('accA', '大批', many);

      expect(await store.loadDirSnapshot('accA', '大批'), isNull);
    });

    test('快照数超上限：丢最早的，保留刚存的', () async {
      for (var i = 0; i < kDirSnapshotMaxDirs + 3; i++) {
        await store.saveDirSnapshot('accA', '目录$i', const [
          RemoteStorageEntry(name: 'x', path: 'x', isDirectory: false),
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }

      final prefs = await SharedPreferences.getInstance();
      final keys = prefs
          .getKeys()
          .where((k) => k.startsWith(RemoteStorageStore.dirSnapshotKeyPrefix))
          .toList();

      expect(keys.length, lessThanOrEqualTo(kDirSnapshotMaxDirs));
      expect(
        keys.any((k) => k.endsWith('目录${kDirSnapshotMaxDirs + 2}')),
        isTrue,
        reason: '刚存的不能被自己淘汰掉',
      );
      expect(keys.any((k) => k.endsWith('目录0')), isFalse);
    });

    test('删账户清掉该账户全部快照，别的账户保留', () async {
      await store.saveDirSnapshot('accA', '相册', const [
        RemoteStorageEntry(name: 'a.jpg', path: '相册/a.jpg', isDirectory: false),
      ]);
      await store.saveDirSnapshot('accA2', '相册', const [
        RemoteStorageEntry(name: 'a.jpg', path: '相册/a.jpg', isDirectory: false),
      ]);
      await store.saveDirSnapshot('accB', '相册', const [
        RemoteStorageEntry(name: 'b.jpg', path: '相册/b.jpg', isDirectory: false),
      ]);

      final removed = await store.clearAccountSnapshots('accA');

      expect(removed, 1, reason: '前缀按账户 id + | 收边，accA 不会清到 accA2');
      expect(await store.loadDirSnapshot('accA', '相册'), isNull);
      expect(await store.loadDirSnapshot('accA2', '相册'), isNotNull);
      expect(await store.loadDirSnapshot('accB', '相册'), isNotNull);
    });

    test('坏数据当没有：不抛异常', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        '${RemoteStorageStore.dirSnapshotKeyPrefix}accA|相册': '这不是 JSON',
      });

      expect(await store.loadDirSnapshot('accA', '相册'), isNull);
    });
  });
}
