// 用户报的坑（2026-09-29）：
//   「我放后台更完后，会卡在 100%，也不跳出安装，只能重新再次下载更新」
//
// 两个原因叠在一起：
//   ① Android 10+ 会**静默丢掉**后台发起的 startActivity（open_filex 照样回 done），
//      所以后台下载完的那一刻去拉安装界面，用户什么都看不到；
//   ② 以前下载成功之后不改任何 UI 状态，界面就永远停在「下载中 100%」，
//      按钮还是灰的 —— 想再试一次只能重新下一遍 27MB。
//
// 这个用例钉住修好之后的行为：后台下载完要**说清楚**、回前台自动补上安装界面，
// 而且绝不因为切后台就重下。
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/update/apk_digest.dart';
import 'package:box/update/pending_update_apk_store.dart';
import 'package:box/update/update_dialog.dart';
import 'package:box/update/update_models.dart';

const String _apkPath = '/tmp/fake-update-333.apk';

UpdateManifest _manifest({String? sha256}) => UpdateManifest.fromJson(<String, dynamic>{
  'appId': 'box',
  'platform': 'android',
  'channel': 'release',
  'packageName': 'top.hpa888.box',
  'latestVersionCode': 333,
  'latestVersionName': '1.20.76',
  'forceUpdate': false,
  'minSupportedVersionCode': 100,
  'downloadUrl':
      'https://box.hpa888.top/updates/box/android/release/box-1.20.76-333.apk',
  'sha256': sha256 ?? ('a' * 64),
  'fileSize': 1024,
  'changelog': <String>['测试'],
});

/// 切前后台：走的就是 Android 真实那条路（flutter/lifecycle 平台消息）。
Future<void> _setLifecycle(WidgetTester tester, AppLifecycleState state) async {
  final message = const StringCodec().encodeMessage(state.toString());
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/lifecycle',
    message,
    (_) {},
  );
  await tester.pump();
}

Future<void> _pump(
  WidgetTester tester, {
  required Future<String> Function(UpdateManifest, void Function(double))
  downloader,
  required Future<void> Function(String) launcher,
  PendingUpdateApkStore? pendingStore,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: UpdateDialog(
          manifest: _manifest(),
          currentVersionName: '1.20.75',
          currentVersionCode: 332,
          force: false,
          downloaderOverride: downloader,
          launcherOverride: launcher,
          pendingStore:
              pendingStore ?? (PendingUpdateApkStore.instance..debugUseInMemory()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() async {
    // 别把 paused 状态漏给后面的用例：paused 时框架**不再排帧**，
    // 下一个用例的 pumpAndSettle 会空转到超时（实测空转 6 分钟才报错）。
    final binding = TestWidgetsFlutterBinding.instance;
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StringCodec().encodeMessage('AppLifecycleState.resumed'),
      (_) {},
    );
    binding.platformDispatcher.resetInitialLifecycleState();
  });

  testWidgets('后台把更新下完：不静默卡在 100%，回到前台自动弹出安装界面', (tester) async {
    final downloads = <String>[];
    final launches = <String>[];
    final gate = Completer<void>();

    Future<String> downloader(
      UpdateManifest manifest,
      void Function(double) onProgress,
    ) async {
      downloads.add(manifest.latestVersionName);
      onProgress(0.5);
      await gate.future; // 下载还卡在半路
      onProgress(1);
      return _apkPath;
    }

    await _pump(
      tester,
      downloader: downloader,
      launcher: (path) async => launches.add(path),
    );

    await tester.tap(find.text('更新'));
    await tester.pump();
    expect(find.text('下载中 50%'), findsOneWidget);

    // 用户把 App 切到后台，然后下载在后台完成。
    await _setLifecycle(tester, AppLifecycleState.paused);
    gate.complete();
    // 注意：App 处于 paused 时框架**不再排帧**（这正是"后台什么都不弹"的现场），
    // 所以这里不要等 UI，只断言"没有偷偷去拉安装界面"。
    await tester.pump();
    expect(
      launches,
      isEmpty,
      reason: '后台拉安装界面会被系统静默丢掉，等于什么都没发生',
    );

    // 回到前台：自动把安装界面补上（用户不用重新下载）。
    await _setLifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(launches, <String>[_apkPath], reason: '回前台要自动弹安装界面');
    expect(downloads.length, 1, reason: '切后台不能导致重下一遍');
    expect(
      find.textContaining('下载中'),
      findsNothing,
      reason: '不能停在「下载中 100%」这种没出路的样子',
    );
    expect(find.textContaining('已交给系统安装器'), findsOneWidget);
    expect(find.text('立即安装'), findsOneWidget, reason: '得给一个还能点的按钮');
  });

  testWidgets('前台把更新下完：立刻拉安装界面，按钮不再是「下载中 100%」', (tester) async {
    final launches = <String>[];

    await _pump(
      tester,
      downloader: (manifest, onProgress) async {
        onProgress(1);
        return _apkPath;
      },
      launcher: (path) async => launches.add(path),
    );

    await tester.tap(find.text('更新'));
    await tester.pumpAndSettle();

    expect(launches, <String>[_apkPath], reason: '前台就该当场拉安装界面');
    expect(find.textContaining('下载中'), findsNothing);
    expect(
      find.text('立即安装'),
      findsOneWidget,
      reason: '包已经在手上，按钮要说「立即安装」而不是「更新」',
    );
  });

  testWidgets('从安装界面取消回来后，再点「立即安装」还能再拉一次', (tester) async {
    final launches = <String>[];

    await _pump(
      tester,
      downloader: (manifest, onProgress) async {
        onProgress(1);
        return _apkPath;
      },
      launcher: (path) async => launches.add(path),
    );

    await tester.tap(find.text('更新'));
    await tester.pumpAndSettle();
    expect(launches.length, 1);

    // 用户在系统安装界面上点了取消，回到 App 想再装一次。
    await tester.tap(find.text('立即安装'));
    await tester.pumpAndSettle();
    expect(
      launches.length,
      2,
      reason: '取消之后还要能再来一次，不能点了没反应',
    );
  });

  testWidgets('上次下完没装上的包：再点一次不重下，直接进安装', (tester) async {
    // 真文件 + 真哈希。widget 测试跑在假时钟里，真实 I/O 必须放进 runAsync：
    // 直接在用例体里做文件读写，会留下一个悬着的 I/O 事件，
    // 整个测试进程结束时卡住并报 "Cannot close sink while adding stream"（实测卡 6 分钟）。
    late File file;
    late String realSha;
    await tester.runAsync(() async {
      file = File(
        '${Directory.systemTemp.path}/pending_update_'
        '${DateTime.now().microsecondsSinceEpoch}.apk',
      )..writeAsStringSync('not-a-real-apk-but-hashable');
      realSha = await sha256OfFile(file);
    });

    final store = PendingUpdateApkStore.instance..debugUseInMemory();
    await store.save(versionCode: 333, path: file.path, sha256: realSha);

    final downloads = <String>[];
    final launches = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateDialog(
            manifest: _manifest(sha256: realSha),
            currentVersionName: '1.20.75',
            currentVersionCode: 332,
            force: false,
            downloaderOverride: (manifest, onProgress) async {
              downloads.add(manifest.latestVersionName);
              onProgress(1);
              return '/tmp/should-not-be-used.apk';
            },
            launcherOverride: (path) async => launches.add(path),
            pendingStore: store,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 认包要算真文件的 SHA-256（真实 I/O）：widget 测试的假时钟里必须用 runAsync，
    // 否则这个 future 不会完成，用例会看到"什么也没发生"。
    await tester.runAsync(() async {
      await tester.tap(find.text('更新'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(downloads, isEmpty, reason: '同一个包已经在本地，不该再下一遍');
    expect(launches, <String>[file.path], reason: '直接装本地那个已校验的包');

    // 收拾掉临时 apk（别在临时目录里留垃圾）。
    await tester.runAsync(() async {
      if (await file.exists()) await file.delete();
    });
  });
}
