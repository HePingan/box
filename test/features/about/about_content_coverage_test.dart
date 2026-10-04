import 'dart:io';

import 'package:box/features/about/data/about_content.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「帮助与说明」里的内容必须**跟应用的实际能力对齐**。
///
/// 由来：使用文档原来只有 6 节（开始/影视/小说/题库与插件/备份/出问题），
/// 而应用里真实的模块远不止这些 —— 漫画、本地工具、API 能力中心、AI 生图、
/// 内容页、扩展页在文档里一个字都没有，用户只能自己摸。这类"漏"不像写错那样
/// 显眼，所以用下面几条机械判据盯住：
///
/// 1. 每个模块都要在使用文档里有一节，且该模块的实现目录要真的存在；
/// 2. 计数不许手抄（`28 个工具` 这种写在文案里的数字，改一次代码就变假话）；
/// 3. 「不申请位置/通讯录/短信/相机」这类自证，要拿 manifest 真的核对；
/// 4. 「不集成统计/推送/广告 SDK」要拿 pubspec 真的核对。
void main() {
  final content = File(
    'lib/features/about/data/about_content.dart',
  ).readAsStringSync();
  final usageText = AboutContent.usageDocs
      .map((s) => [s.title, ...s.paragraphs, ...s.bullets].join('\n'))
      .join('\n');
  final introText = AboutContent.introduction
      .map((s) => [s.title, ...s.paragraphs, ...s.bullets].join('\n'))
      .join('\n');

  /// 模块名 → 实现该模块的目录/文件（任一存在即可）。
  const modules = <String, List<String>>{
    '漫画': ['lib/features/comic'],
    '本地工具': ['lib/features/local_tools'],
    'API 能力中心': ['lib/features/api_hub'],
    'AI 生图': ['lib/features/image_generator'],
    '扩展': ['lib/features/extensions'],
    '内容': ['lib/features/content'],
    '题库': ['lib/features/quiz_plugin'],
    '备份与恢复': ['lib/features/backup'],
    '云同步': ['lib/features/cloud_sync'],
  };

  for (final entry in modules.entries) {
    test('使用文档里有「${entry.key}」一节，且模块真的存在', () {
      expect(
        usageText.contains(entry.key),
        isTrue,
        reason: '使用文档里没有提到「${entry.key}」',
      );
      expect(
        entry.value.any((p) => FileSystemEntity.isDirectorySync(p) || File(p).existsSync()),
        isTrue,
        reason: '${entry.key} 的实现（${entry.value.join("/")}）找不到了，'
            '模块删了或挪了，文档也要跟着改',
      );
    });
  }

  test('每个模块在使用文档里都有一整节，而不只是顺口提一句', () {
    final sectionTitles = AboutContent.usageDocs.map((s) => s.title).toList();
    for (final need in ['漫画', '本地工具', 'API 能力中心', 'AI 生图', '扩展']) {
      expect(
        sectionTitles.any((t) => t.contains(need)),
        isTrue,
        reason: '「$need」没有独立小节（现有小节：${sectionTitles.join(" / ")}）',
      );
    }
  });

  test('计数不许手抄：文案里不出现「N 个工具 / N 项权限」这类写死的数字', () {
    final banned = RegExp(r'\d+\s*(个|项|条)\s*(本地工具|工具|面板|权限|功能|插件)');
    final hit = banned.firstMatch(content);
    expect(
      hit,
      isNull,
      reason: '文案里写死了计数「${hit?.group(0)}」—— 数字要在界面上现算'
          '（工具页分类芯片、权限页顶部都是现算的），文档里只描述不要计数',
    );
  });

  test('「不申请位置/通讯录/短信/相机」要与 AndroidManifest 真的核对', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    // 这句话只在这几句自证真的成立时才允许写。
    expect(introText.contains('不申请位置、通讯录、短信、相机'), isTrue);
    const neverAllowed = <String>[
      'ACCESS_FINE_LOCATION',
      'ACCESS_COARSE_LOCATION',
      'ACCESS_BACKGROUND_LOCATION',
      'READ_CONTACTS',
      'WRITE_CONTACTS',
      'READ_SMS',
      'SEND_SMS',
      'RECEIVE_SMS',
      'CAMERA',
      'READ_CALL_LOG',
      'CALL_PHONE',
      'READ_PHONE_NUMBERS',
      'BODY_SENSORS',
      'GET_ACCOUNTS',
    ];
    for (final name in neverAllowed) {
      expect(
        manifest.contains(name),
        isFalse,
        reason: 'manifest 里出现了 $name，但软件介绍里写着「不申请…」，'
            '要么去掉这句自证，要么别加这个权限',
      );
    }
  });

  test('「不集成统计/推送/广告 SDK」要与 pubspec 真的核对', () {
    expect(introText.contains('不集成任何统计、推送、广告 SDK'), isTrue);
    final pubspec = File('pubspec.yaml').readAsStringSync().toLowerCase();
    const bannedSdks = <String>[
      'firebase',
      'umeng',
      'umeng_common_sdk',
      'jpush',
      'jiguang',
      'getui',
      'bugly',
      'sentry',
      'admob',
      'google_mobile_ads',
      'talkingdata',
      'amplitude',
      'mixpanel',
      'flutter_local_notifications',
      'analytics',
      'pangle',
      'bytedance',
      'kuaishou',
      'tencentcloud_analytics',
      'x5_webview',
    ];
    for (final sdk in bannedSdks) {
      expect(
        pubspec.contains(sdk),
        isFalse,
        reason: 'pubspec 里出现了「$sdk」，但软件介绍写着「不集成任何统计、推送、'
            '广告 SDK」—— 两边必须同时改',
      );
    }
  });

  test('适用与限制里说的「深色模式与主题配色目前未开放」要属实', () {
    final settings = File(
      'lib/features/settings/presentation/settings_page.dart',
    ).readAsStringSync();
    // 这两项在设置页里必须仍标着「暂不可用」，否则文案要改成已开放。
    expect(
      RegExp('深色模式[\\s\\S]{0,200}暂不可用').hasMatch(settings),
      isTrue,
      reason: '深色模式在设置页不再标注「暂不可用」了，软件介绍里的'
          '「深色模式与主题配色目前未开放」需要同步改',
    );
    expect(
      RegExp('主题配色[\\s\\S]{0,200}暂不可用').hasMatch(settings),
      isTrue,
      reason: '主题配色在设置页不再标注「暂不可用」了，文案需要同步改',
    );
  });

  test('推荐教程覆盖面：影视/下载/漫画/清理/离线/工具/换机/报障都要有', () {
    final titles = AboutContent.tutorials.map((t) => t.title).join(' / ');
    for (final need in ['影视', '下载', '漫画', '空间', '断网', '工具', '换机', '报障']) {
      expect(
        titles.contains(need),
        isTrue,
        reason: '推荐教程里没有覆盖「$need」（现有：$titles）',
      );
    }
  });
}
