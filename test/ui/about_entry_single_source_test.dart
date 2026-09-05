import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// B7：「关于」只保留一处实现（侧边栏）。
///
/// 合并前有两份且内容不一致：
///  - app_drawer.dart：自定义 AlertDialog，带「检查更新」按钮，有测试守护
///    （test/update/manual_check_snackbar_test.dart）
///  - personal_center_page.dart：Material 简版 showAboutDialog，应用名写的是
///    「Geek工具箱 Pro」，与抽屉那份不一致
///
/// 两份同时存在，用户从不同入口看到不同的应用名和不同的功能，改一处漏一处。
/// 这个测试用源码断言守住「只有一处」，不是行为测试 —— 重复实现是结构问题，
/// 只有结构断言能防住它再长回来。
void main() {
  test('个人中心不再自带「关于」，避免与抽屉那份内容不一致', () {
    final source = File(
      'lib/features/account/presentation/personal_center_page.dart',
    ).readAsStringSync();

    expect(
      source.contains('showAboutDialog'),
      isFalse,
      reason: '关于应统一由抽屉的 _showAboutDialog 提供（含检查更新入口）',
    );
    expect(
      source.contains('Geek工具箱 Pro'),
      isFalse,
      reason: '硬编码的应用名与抽屉那份不一致，移除关于入口时应一并删掉',
    );
  });

  test('抽屉仍然是「关于」的唯一实现', () {
    final source = File('lib/app_drawer.dart').readAsStringSync();
    expect(source.contains('_showAboutDialog'), isTrue);
  });
}
