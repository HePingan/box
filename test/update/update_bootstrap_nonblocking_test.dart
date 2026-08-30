import 'package:box/update/update_bootstrap_page.dart';
import 'package:box/update/update_check_outcome.dart';
import 'package:box/update/update_ignore_store.dart';
import 'package:box/update/update_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// B2 回归：启动不再被更新检查阻塞，且失败不再静默。
///
/// 旧行为：UpdateBootstrapPage 是 `home:`，必须等网络检查跑完才进主界面。
/// 超时配置 connect 8s + receive 10s，最坏情况白屏近 20 秒。而
/// allowProceedOnCheckFailure 默认 true，任何失败都被静默咽掉——验签 bug
/// 就是这样长期无人发现的。
///
/// 新行为：主界面立刻显示，检查在后台跑；有新版本才弹窗；强更仍能拦住。
UpdateManifest manifest({required int code, bool forceUpdate = false}) {
  return UpdateManifest.fromJson(<String, dynamic>{
    'appId': 'box',
    'platform': 'android',
    'channel': 'release',
    'packageName': 'top.hpa888.box',
    'latestVersionCode': code,
    'latestVersionName': '9.9.9',
    'forceUpdate': forceUpdate,
    'downloadUrl': 'https://box.hpa888.top/a.apk',
    'sha256': 'a' * 64,
  });
}

void main() {
  // 忽略状态走内存态：本文件测的是「启动不阻塞」，不该被 SharedPreferences
  // 的 platform channel 牵连（真机有超时兜底，测试环境里没有 channel 会挂满超时）。
  setUp(() => UpdateIgnoreStore.instance.debugUseInMemory());
  tearDown(() => UpdateIgnoreStore.instance.debugReset());

  Widget harness({
    required Future<UpdateCheckOutcome> Function() check,
    Duration? delay,
  }) {
    return MaterialApp(
      home: UpdateBootstrapPage(
        nextPage: const Scaffold(body: Text('主界面')),
        appId: 'box',
        checkUrl: 'https://box.hpa888.top/api/v1/app-updates/check',
        platform: 'android',
        channel: 'release',
        currentVersionCodeOverride: 169,
        ignoreStore: UpdateIgnoreStore.instance,
        checkOverride: () async {
          if (delay != null) await Future<void>.delayed(delay);
          return check();
        },
      ),
    );
  }

  testWidgets('主界面立刻显示，不等网络', (tester) async {
    // 检查故意拖 5 秒；主界面必须在这之前就已经可见。
    await tester.pumpWidget(
      harness(
        delay: const Duration(seconds: 5),
        check: () async => UpdateCheckOutcome.fromManifest(
          manifest: manifest(code: 300),
          currentVersionCode: 169,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('主界面'), findsOneWidget);
    expect(find.text('正在检查版本...'), findsNothing);

    // 收尾，避免 pending timer 报错。
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('有新版本时后台检查完成后弹窗', (tester) async {
    await tester.pumpWidget(
      harness(
        check: () async => UpdateCheckOutcome.fromManifest(
          manifest: manifest(code: 300),
          currentVersionCode: 169,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('主界面'), findsOneWidget);
    expect(find.textContaining('9.9.9'), findsWidgets);
  });

  testWidgets('已是最新时不弹窗', (tester) async {
    await tester.pumpWidget(
      harness(
        check: () async => UpdateCheckOutcome.fromManifest(
          // 真实情况：后台最新发布 118，本机 169。
          manifest: manifest(code: 118),
          currentVersionCode: 169,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('主界面'), findsOneWidget);
    expect(find.text('更新'), findsNothing);
  });

  testWidgets('强更仍然拦得住：弹窗不可点外部关闭', (tester) async {
    await tester.pumpWidget(
      harness(
        check: () async => UpdateCheckOutcome.fromManifest(
          manifest: manifest(code: 300, forceUpdate: true),
          currentVersionCode: 169,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('9.9.9'), findsWidgets);

    // 点击遮罩外部：强更时不应关闭。
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.textContaining('9.9.9'), findsWidgets);
  });

  testWidgets('检查失败不阻塞主界面，且留下可读原因', (tester) async {
    final logged = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: UpdateBootstrapPage(
          nextPage: const Scaffold(body: Text('主界面')),
          appId: 'box',
          checkUrl: 'https://box.hpa888.top/api/v1/app-updates/check',
          platform: 'android',
          channel: 'release',
          currentVersionCodeOverride: 169,
          onCheckDiagnostic: logged.add,
          checkOverride: () async => UpdateCheckOutcome.failure(
            UpdateCheckStatus.signatureRejected,
            detail: '更新清单签名不匹配',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('主界面'), findsOneWidget);
    // 关键：失败原因必须被记录下来，不能像以前那样 catch(_) 吞掉。
    expect(logged, isNotEmpty);
    expect(logged.join(), contains('签名'));
  });
}
