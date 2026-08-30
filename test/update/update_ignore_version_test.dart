import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/update/update_bootstrap_page.dart';
import 'package:box/update/update_check_outcome.dart';
import 'package:box/update/update_dialog.dart';
import 'package:box/update/update_ignore_store.dart';
import 'package:box/update/update_models.dart';

UpdateManifest _manifest({
  int latestVersionCode = 174,
  String latestVersionName = '1.7.4',
  int minSupported = 0,
  bool forceUpdate = false,
}) {
  return UpdateManifest(
    schemaVersion: 1,
    appId: 'box',
    platform: 'android',
    channel: 'release',
    packageName: 'top.hpa888.box',
    latestVersionCode: latestVersionCode,
    latestVersionName: latestVersionName,
    minSupportedVersionCode: minSupported,
    blockedVersionCodes: const <int>[],
    forceUpdate: forceUpdate,
    title: 'box $latestVersionName',
    notice: '测试公告',
    changelog: const <String>['条目一'],
    downloadUrl:
        'https://box.hpa888.top/updates/box/android/release/box-$latestVersionName-$latestVersionCode.apk',
    backupDownloadUrl: null,
    sha256: 'a' * 64,
    fileSize: 1024,
    publishedAt: '2026-08-30T08:10:53.105859+00:00',
    supportUrl: null,
    signatureAlgorithm: 'HMAC-SHA256',
    signature: 'b' * 64,
  );
}

void main() {
  group('UpdateIgnoreStore', () {
    late UpdateIgnoreStore store;

    setUp(() {
      store = UpdateIgnoreStore.instance;
      store.debugUseInMemory();
    });

    tearDown(() => store.debugReset());

    test('从未忽略过时应当弹窗', () async {
      expect(await store.shouldShowForVersion(174), isTrue);
    });

    test('忽略当前版本后不再弹窗', () async {
      await store.ignoreVersion(174);
      expect(await store.shouldShowForVersion(174), isFalse);
    });

    test('服务端发布更高版本后重新弹窗', () async {
      await store.ignoreVersion(174);
      expect(await store.shouldShowForVersion(175), isTrue,
          reason: '有新版本必须重新提示，否则用户永远收不到后续更新');
    });

    test('比忽略版本更低的版本不弹（降级发布不该打扰）', () async {
      await store.ignoreVersion(174);
      expect(await store.shouldShowForVersion(173), isFalse);
    });

    test('强更无视忽略状态', () async {
      await store.ignoreVersion(174);
      expect(
        await store.shouldShowForVersion(174, force: true),
        isTrue,
        reason: '忽略不能变成绕过强更的后门',
      );
    });

    test('忽略非法版本号不写入', () async {
      await store.ignoreVersion(0);
      expect(await store.readIgnoredVersionCode(), isNull);
    });

    test('存储永久挂起时必须超时放行弹窗，不能吞掉更新提示', () async {
      // 这是最危险的失败模式：SharedPreferences.getInstance() 在缺少
      // platform channel 的 widget binding 环境下既不返回也不抛异常（实测永久挂起），
      // 只 catch 异常挡不住。若不兜超时，用户会永远收不到更新提示。
      // 这里用注入的挂起存储确定性复现，而不是依赖环境的偶然行为。
      store.debugUseHangingStorage();

      final sw = Stopwatch()..start();
      final show = await store.shouldShowForVersion(174);
      sw.stop();

      expect(show, isTrue, reason: '存储读不到时必须弹窗，否则用户再也收不到更新');
      expect(
        sw.elapsed,
        greaterThanOrEqualTo(
          UpdateIgnoreStore.readTimeout - const Duration(milliseconds: 200),
        ),
        reason: '确认真的走了超时兜底路径，而不是碰巧读到了值',
      );
      expect(
        sw.elapsed,
        lessThan(UpdateIgnoreStore.readTimeout + const Duration(seconds: 5)),
        reason: '必须被 readTimeout 兜住，不能无限挂起',
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('clear 后恢复弹窗', () async {
      await store.ignoreVersion(174);
      await store.clear();
      expect(await store.shouldShowForVersion(174), isTrue);
    });
  });

  group('UpdateDialog 忽略按钮', () {
    testWidgets('非强更时展示「忽略此版本」，点击后写入并关闭', (tester) async {
      final store = UpdateIgnoreStore.instance;
      store.debugUseInMemory();
      addTearDown(store.debugReset);

      int? ignoredCallback;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => UpdateDialog(
                    manifest: _manifest(),
                    currentVersionName: '1.7.3',
                    currentVersionCode: 173,
                    force: false,
                    ignoreStore: store,
                    onIgnored: (c) => ignoredCallback = c,
                    installOverride: () async {},
                    backupOverride: () async => '',
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('忽略此版本'), findsOneWidget);

      await tester.tap(find.text('忽略此版本'));
      await tester.pumpAndSettle();

      expect(await store.readIgnoredVersionCode(), 174);
      expect(ignoredCallback, 174);
      expect(find.text('忽略此版本'), findsNothing, reason: '点完应当关闭弹窗');
    });

    testWidgets('强更时不展示「忽略此版本」', (tester) async {
      final store = UpdateIgnoreStore.instance;
      store.debugUseInMemory();
      addTearDown(store.debugReset);

      await tester.pumpWidget(
        MaterialApp(
          home: UpdateDialog(
            manifest: _manifest(minSupported: 174, forceUpdate: true),
            currentVersionName: '1.7.3',
            currentVersionCode: 173,
            force: true,
            ignoreStore: store,
            installOverride: () async {},
            backupOverride: () async => '',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('忽略此版本'), findsNothing);
      expect(find.text('更新'), findsOneWidget);
    });
  });

  group('启动检查遵守忽略状态', () {
    testWidgets('已忽略该版本则启动不弹窗', (tester) async {
      final store = UpdateIgnoreStore.instance;
      store.debugUseInMemory(initial: 174);
      addTearDown(store.debugReset);

      final messages = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: UpdateBootstrapPage(
            nextPage: const Scaffold(body: Text('主界面')),
            appId: 'box',
            checkUrl: 'https://example.invalid/check',
            platform: 'android',
            channel: 'release',
            currentVersionCodeOverride: 173,
            ignoreStore: store,
            onCheckDiagnostic: messages.add,
            checkOverride: () async => UpdateCheckOutcome.fromManifest(
              manifest: _manifest(),
              currentVersionCode: 173,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('主界面'), findsOneWidget);
      expect(find.text('更新'), findsNothing, reason: '忽略过就不该再弹');
      expect(
        messages.any((m) => m.contains('已忽略该版本')),
        isTrue,
        reason: '要留下可诊断记录，而不是静默跳过',
      );
    });

    testWidgets('忽略旧版本后，更高版本仍会弹窗', (tester) async {
      final store = UpdateIgnoreStore.instance;
      store.debugUseInMemory(initial: 174);
      addTearDown(store.debugReset);

      await tester.pumpWidget(
        MaterialApp(
          home: UpdateBootstrapPage(
            nextPage: const Scaffold(body: Text('主界面')),
            appId: 'box',
            checkUrl: 'https://example.invalid/check',
            platform: 'android',
            channel: 'release',
            currentVersionCodeOverride: 173,
            ignoreStore: store,
            checkOverride: () async => UpdateCheckOutcome.fromManifest(
              manifest: _manifest(
                latestVersionCode: 175,
                latestVersionName: '1.7.5',
              ),
              currentVersionCode: 173,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('忽略此版本'), findsOneWidget);
      expect(find.textContaining('1.7.5'), findsWidgets);
    });
  });
}
