import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 包名一致性闸门。
///
/// 为什么需要：包名散落在 gradle（namespace/applicationId）、Kotlin package 声明、
/// res XML 的自定义 View 全限定名、以及 Dart/Kotlin 两侧的 MethodChannel 字符串里。
/// MethodChannel 名不一致是**编译期发现不了**的——运行时才炸 MissingPluginException，
/// 表现为「某个功能点了没反应」。这个测试把这些位置钉在一起。
void main() {
  const expected = 'top.hpa888.box';
  const legacy = 'com.example.box';

  test('gradle 的 namespace 与 applicationId 都是新包名', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('namespace = "$expected"'));
    expect(gradle, contains('applicationId = "$expected"'));
    expect(gradle, isNot(contains(legacy)), reason: 'gradle 里不应再有旧包名');
  });

  test('Kotlin 源码目录已迁移，且没有残留旧 package 声明', () {
    expect(
      Directory('android/app/src/main/kotlin/top/hpa888/box').existsSync(),
      isTrue,
      reason: 'Kotlin 源码应位于新包名目录下',
    );
    expect(
      Directory('android/app/src/main/kotlin/com/example').existsSync(),
      isFalse,
      reason: '旧包名目录应已删除，否则会留下编译不到的僵尸源码',
    );
  });

  test('Dart 侧 MethodChannel 名与 Kotlin 侧逐字一致', () {
    // 这三个 channel 名两侧必须完全相同，错一个字就是运行时「点了没反应」。
    const channels = <String, String>{
      'quiz_plugin':
          'lib/features/quiz_plugin/presentation/quiz_plugin_entry.dart',
      'video_downloads': 'lib/video/services/video_download_gateway.dart',
      'reader_keys': 'lib/novel/pages/reader/reader_volume_key_controller.dart',
    };

    final mainActivity = File(
      'android/app/src/main/kotlin/top/hpa888/box/MainActivity.kt',
    ).readAsStringSync();

    channels.forEach((suffix, dartPath) {
      final full = '$expected/$suffix';
      final dart = File(dartPath).readAsStringSync();
      expect(dart, contains(full), reason: '$dartPath 的 channel 名应为 $full');
      expect(
        mainActivity,
        contains(full),
        reason: 'MainActivity.kt 缺少与 Dart 对应的 channel 名 $full',
      );
    });
  });

  test('无障碍服务的全限定名已随包名更新', () {
    // 这个字符串用于比对 Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES，
    // 不一致会导致「明明开了无障碍，App 仍判定未开启」。
    final mainActivity = File(
      'android/app/src/main/kotlin/top/hpa888/box/MainActivity.kt',
    ).readAsStringSync();
    expect(mainActivity, contains('$expected.QuizAccessibilityService'));
    expect(mainActivity, isNot(contains('$legacy.QuizAccessibilityService')));
  });

  test('res XML 里的自定义 View 全限定名已更新', () {
    // XML 里写错包名不会编译失败，会在 inflate 时抛 ClassNotFoundException。
    for (final path in const [
      'android/app/src/main/res/layout/quiz_overlay.xml',
      'android/app/src/main/res/layout/quiz_ocr_entry_overlay.xml',
      'android/app/src/main/res/xml/quiz_accessibility_config.xml',
    ]) {
      final xml = File(path).readAsStringSync();
      expect(xml, isNot(contains(legacy)), reason: '$path 仍含旧包名');
    }
  });
}
