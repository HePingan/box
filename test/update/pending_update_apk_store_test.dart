// 「下完了没装上 → 只能重下一遍」的解药：记住已下载的更新包。
//
// 这里钉住三件事：
//   1. 同版本 + 哈希对得上 + 文件还在 → 认这个包（省一次 27MB 下载）；
//   2. 版本换了 / 哈希变了 / 文件被系统清了 → 一律不认，并且把失效记录清掉；
//   3. 存不下、读不到（存储不可用）都不能把更新流程卡住。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:box/update/apk_digest.dart';
import 'package:box/update/pending_update_apk_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late File apk;
  late String apkSha;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('pending_apk_test');
    apk = File('${tmp.path}/box-1.20.76-333.apk');
    await apk.writeAsString('fake apk body for hashing');
    apkSha = await sha256OfFile(apk);
  });

  tearDownAll(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  setUp(() {
    // 真·SharedPreferences 走内存 mock：既验证真实读写路径，又不碰平台通道。
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PendingUpdateApkStore.instance.debugReset();
  });

  test('存下再读回来：版本 / 路径 / 哈希都对得上', () async {
    final store = PendingUpdateApkStore.instance;
    await store.save(versionCode: 333, path: apk.path, sha256: apkSha);

    final record = await store.read();
    expect(record, isNotNull);
    expect(record!.versionCode, 333);
    expect(record.path, apk.path);
    expect(record.sha256, apkSha);
  });

  test('同版本 + 哈希对得上 + 文件在 → 认这个包', () async {
    final store = PendingUpdateApkStore.instance;
    await store.save(versionCode: 333, path: apk.path, sha256: apkSha);

    final path = await store.reusablePath(
      versionCode: 333,
      expectedSha256: apkSha,
    );
    expect(path, apk.path);
  });

  test('版本换了 → 不认，并把失效记录清掉（别反复认一个用不了的包）', () async {
    final store = PendingUpdateApkStore.instance;
    await store.save(versionCode: 332, path: apk.path, sha256: apkSha);

    expect(
      await store.reusablePath(versionCode: 333, expectedSha256: apkSha),
      isNull,
    );
    expect(await store.read(), isNull);
  });

  test('同一版本但哈希变了（服务端重发了包）→ 不认', () async {
    final store = PendingUpdateApkStore.instance;
    await store.save(versionCode: 333, path: apk.path, sha256: apkSha);

    expect(
      await store.reusablePath(versionCode: 333, expectedSha256: 'b' * 64),
      isNull,
    );
    expect(await store.read(), isNull);
  });

  test('文件被系统清掉了 → 不认，不抛异常', () async {
    final gone = File('${tmp.path}/gone.apk');
    final store = PendingUpdateApkStore.instance;
    await store.save(versionCode: 333, path: gone.path, sha256: apkSha);

    expect(
      await store.reusablePath(versionCode: 333, expectedSha256: apkSha),
      isNull,
    );
    expect(await store.read(), isNull);
  });

  test('文件内容被改过（哈希对不上）→ 不认（绝不把动过的包当更新包装上去）', () async {
    final tampered = File('${tmp.path}/tampered.apk');
    await tampered.writeAsString('tampered content');
    final store = PendingUpdateApkStore.instance;
    await store.save(versionCode: 333, path: tampered.path, sha256: apkSha);

    expect(
      await store.reusablePath(versionCode: 333, expectedSha256: apkSha),
      isNull,
    );
  });

  test('参数缺失（版本号/哈希为空）不认，也不异常', () async {
    final store = PendingUpdateApkStore.instance;
    await store.save(versionCode: 0, path: apk.path, sha256: apkSha);
    expect(await store.read(), isNull, reason: '版本号非正数不该落库');

    await store.save(versionCode: 333, path: apk.path, sha256: apkSha);
    expect(
      await store.reusablePath(versionCode: 333, expectedSha256: ''),
      isNull,
    );
  });

  test('清掉之后就读不到了', () async {
    final store = PendingUpdateApkStore.instance;
    await store.save(versionCode: 333, path: apk.path, sha256: apkSha);
    await store.clear();
    expect(await store.read(), isNull);
  });
}
