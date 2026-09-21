import 'package:box/features/about/data/about_content.dart';
import 'package:box/features/about/presentation/about_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 关于页结构回归。
///
/// 这个页面替代了原来抽屉里的 `_showAboutDialog`。需求点名要装七样东西
/// （版本信息、软件介绍、使用文档、推荐教程、更新内容、用户协议、隐私政策），
/// 少一样就是漏做，所以逐个锁住。
void main() {
  Widget host({String? version}) => MaterialApp(
        home: AboutPage(versionOverride: version ?? '9.9.9+999'),
      );

  /// 关于页比测试默认视口（800x600）高，ListView 只构建可见区域，
  /// 下半部分（法律条款、页脚）不滚动就 findsNothing —— 那是懒加载而不是缺失。
  /// 把视口调高，让整页一次性构建出来。
  Future<void> pumpTall(WidgetTester tester, Widget app) async {
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  testWidgets('需求要求的七个入口都在', (tester) async {
    await pumpTall(tester, host());

    for (final label in [
      '当前版本',
      '检查更新',
      '更新内容',
      '软件介绍',
      '使用文档',
      '推荐教程',
      '用户协议',
      '隐私政策',
    ]) {
      expect(
        find.text(label),
        findsOneWidget,
        reason: '关于页缺少「$label」入口',
      );
    }
  });

  testWidgets('调试日志入口保留（报障主要抓手，不能因为改版丢掉）', (tester) async {
    await pumpTall(tester, host());
    expect(find.text('调试日志'), findsOneWidget);
  });

  testWidgets('版本号注入后直接显示，不显示占位文案', (tester) async {
    await pumpTall(tester, host(version: '1.10.2+203'));

    expect(find.text('1.10.2+203'), findsOneWidget);
    expect(find.text('读取中…'), findsNothing);
    expect(find.text('获取失败'), findsNothing);
  });

  testWidgets('PackageInfo 读取失败时显示「获取失败」而不是空白', (tester) async {
    // 这条曾经写错过：以为 widget test 里 PackageInfo.fromPlatform() 会直接抛
    // MissingPluginException。实测它**既不抛也不返回**，而是一直挂着
    // （probe 跑了 4 分钟没结束），于是失败分支永远进不去、断言必然红。
    // 正确做法是主动 mock 平台通道让它抛。
    const channel = MethodChannel('dev.fluttercommunity.plus/package_info');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => throw MissingPluginException('no impl in test'),
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await pumpTall(tester, const MaterialApp(home: AboutPage()));

    // 不静默：早先的写法 catch(_) 之后什么都不显示，
    // 报障时分不清「没显示」和「没读到」。
    expect(find.text('获取失败'), findsOneWidget);
  });

  testWidgets('页脚免责声明可见，且不含承诺性措辞', (tester) async {
    await pumpTall(tester, host());

    expect(find.textContaining('不内置任何内容资源'), findsOneWidget);
    // 页脚是最容易被顺手写成宣传语的地方，锁一下。
    for (final banned in ['永久免费', '绝对安全', '最好用']) {
      expect(
        AboutContent.disclaimerShort.contains(banned),
        isFalse,
        reason: '页脚出现兜不住的措辞：$banned',
      );
    }
  });
}
