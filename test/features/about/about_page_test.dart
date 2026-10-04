import 'package:box/config/app_config.dart';
import 'package:box/features/about/data/about_content.dart';
import 'package:box/features/about/data/permission_notes.dart';
import 'package:box/features/about/presentation/about_page.dart';
import 'package:box/features/about/presentation/app_permissions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 关于页结构回归。
///
/// 这个页面替代了原来抽屉里的 `_showAboutDialog`。需求点名要装七样东西
/// （版本信息、软件介绍、使用文档、推荐教程、更新内容、用户协议、隐私政策），
/// 少一样就是漏做，所以逐个锁住。
void main() {
  Widget host({String? version}) => MaterialApp(
        home: AboutPage(versionOverride: version ?? '9.9.9+999'),
      );

  // 每个用例都从「没有上次检查记录」开始：关于页会读它来拼副标题。
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// 关于页比测试默认视口（800x600）高，ListView 只构建可见区域，
  /// 下半部分（法律条款、页脚）不滚动就 findsNothing —— 那是懒加载而不是缺失。
  /// 把视口调高，让整页一次性构建出来。
  Future<void> pumpTall(WidgetTester tester, Widget app) async {
    tester.view.physicalSize = const Size(1200, 4600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  testWidgets('入口都在（原七项 + 本轮新增五项）', (tester) async {
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
      '更新来源与校验',
      '开源许可与致谢',
      '问题反馈',
      '项目源码',
      '联系邮箱',
      '权限说明',
      '应用自检',
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

  testWidgets('「更新来源与校验」弹窗里的数字来自真源，不是手抄', (tester) async {
    await pumpTall(tester, host());
    await tester.tap(find.text('更新来源与校验'));
    await tester.pumpAndSettle();

    // 弹窗里必须能看到现取的检查地址与下载域名（同一配置源）
    expect(find.text(AppConfig.updateCheckUrl), findsOneWidget);
    expect(find.text(AppConfig.updateDownloadAllowedHosts), findsOneWidget);
    // 签名算法显示成人能读的写法
    expect(find.textContaining('HMAC-SHA256 签名'), findsOneWidget);
    // 测试环境读不到 PackageInfo → 包名行显示 `—`，不猜也不空白
    expect(find.text('—'), findsOneWidget);
    expect(find.text('知道了'), findsOneWidget);
  });

  testWidgets('「问题反馈」点击复制地址并给明确反馈', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await pumpTall(tester, host());
    await tester.tap(find.text('问题反馈'));
    await tester.pumpAndSettle();

    expect(copied, [AboutContent.issuesUrl]);
    expect(find.text('反馈地址已复制'), findsOneWidget);
  });

  testWidgets('「开源许可与致谢」能进到真正的许可页', (tester) async {
    await pumpTall(tester, host());
    await tester.tap(find.text('开源许可与致谢'));
    await tester.pumpAndSettle();

    // showLicensePage 的页面（Flutter 自带），标题带应用名
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.textContaining(AboutContent.appName), findsWidgets);
  });

  testWidgets('页脚写明数据在哪（且与隐私政策例外口径一致）', (tester) async {
    await pumpTall(tester, host());
    expect(find.text(AboutContent.localDataNote), findsOneWidget);
    expect(find.textContaining('只存在这台设备上'), findsOneWidget);
  });

  testWidgets('副标题摊开上次检查的时间与结论（有记录时）', (tester) async {
    SharedPreferences.setMockInitialValues({
      'update_last_check_v1':
          '{"at":"${DateTime.now().subtract(const Duration(minutes: 3)).toIso8601String()}",'
          '"status":"upToDate"}',
    });
    await pumpTall(tester, host());
    await tester.pumpAndSettle();

    expect(find.textContaining('上次检查'), findsOneWidget);
    expect(find.textContaining('3 分钟前'), findsOneWidget);
    expect(find.textContaining('已是最新版本'), findsOneWidget);
  });

  testWidgets('没有检查记录时显示原来的说明句，不写占位', (tester) async {
    await pumpTall(tester, host());
    expect(find.text('从官方更新服务器获取最新版本'), findsOneWidget);
    expect(find.textContaining('上次检查'), findsNothing);
  });

  testWidgets('调试日志挪进了「反馈与联系」（它是报障工具，不是说明书）', (tester) async {
    await pumpTall(tester, host());

    double y(String text) => tester.getTopLeft(find.text(text)).dy;

    expect(y('帮助与说明') < y('调试日志'), isTrue);
    expect(
      y('反馈与联系') < y('调试日志'),
      isTrue,
      reason: '调试日志应该在「反馈与联系」组里',
    );
    expect(
      y('调试日志') < y('法律条款'),
      isTrue,
      reason: '但仍在法律条款之前',
    );
    // 报障三件套在同一组里：反馈入口、日志、自检
    expect(y('问题反馈') < y('调试日志'), isTrue);
    expect(y('调试日志') < y('应用自检'), isTrue);
  });

  testWidgets('页脚的「数据在哪」可点，弹出明细并能跳隐私政策', (tester) async {
    await pumpTall(tester, host());
    await tester.tap(find.text('点击看：数据都在哪 · 怎么清'));
    await tester.pumpAndSettle();

    expect(find.text('你的数据都在哪'), findsOneWidget);
    expect(find.text('书架 · 阅读进度 · 书源'), findsOneWidget);
    expect(find.textContaining('不参与系统的备份与换机迁移'), findsOneWidget);
    expect(find.text('看《隐私政策》'), findsOneWidget);

    // 只断言弹窗能关；不点「看《隐私政策》」——那是跨路由跳转，本测试的宿主
    // 没挂应用的路由表（挂上去等于在关于页的用例里测路由表）。
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('你的数据都在哪'), findsNothing, reason: '弹窗应关闭');
  });

  testWidgets('权限说明页：13 条都在，每条四行齐、含系统原文名', (tester) async {
    tester.view.physicalSize = const Size(1200, 5200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: AppPermissionsPage()));
    await tester.pumpAndSettle();

    expect(find.textContaining('13 项权限与系统能力'), findsOneWidget);
    for (final note in kPermissionNotes) {
      expect(
        find.text(note.title),
        findsOneWidget,
        reason: '权限说明页缺少「${note.title}」',
      );
      // 系统里显示的是清单名，必须一起列出来，用户才对得上号
      expect(find.text(note.manifestName), findsOneWidget);
    }
    for (final label in ['用来做什么', '什么时候用到', '不给会怎样', '怎么关掉']) {
      expect(
        find.text(label),
        findsNWidgets(kPermissionNotes.length),
        reason: '「$label」应当每条都有',
      );
    }
    expect(find.textContaining('卸载应用即全部收回'), findsOneWidget);
  });
}
