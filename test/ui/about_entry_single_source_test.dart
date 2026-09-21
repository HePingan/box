import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// B7：「关于」只保留一处实现。
///
/// 合并前有两份且内容不一致：
///  - app_drawer.dart：自定义 AlertDialog，带「检查更新」按钮
///  - personal_center_page.dart：Material 简版 showAboutDialog，应用名写的是
///    「Geek工具箱 Pro」，与抽屉那份不一致
///
/// 两份同时存在，用户从不同入口看到不同的应用名和不同的功能，改一处漏一处。
/// 这个测试用源码断言守住「只有一处」，不是行为测试 —— 重复实现是结构问题，
/// 只有结构断言能防住它再长回来。
///
/// 2026-09 更新：单一来源从「抽屉里的 AlertDialog」迁到了 [AboutPage] 整页。
/// 弹窗装不下版本信息 / 软件介绍 / 使用文档 / 推荐教程 / 历史更新 / 用户协议 /
/// 隐私政策这一堆内容。断言随之改为指向新的唯一实现 —— 意图没变（仍然只许一处），
/// 变的只是那一处在哪。
void main() {
  test('个人中心不再自带「关于」，避免与另一份内容不一致', () {
    final source = File(
      'lib/features/account/presentation/personal_center_page.dart',
    ).readAsStringSync();

    expect(
      source.contains('showAboutDialog'),
      isFalse,
      reason: '关于应统一由 AboutPage 提供',
    );
    expect(
      source.contains('Geek工具箱 Pro'),
      isFalse,
      reason: '硬编码的应用名与另一份不一致，移除关于入口时应一并删掉',
    );
  });

  test('抽屉不再自建关于弹窗，改为跳 AboutPage', () {
    final source = File('lib/app_drawer.dart').readAsStringSync();

    expect(
      source.contains('_showAboutDialog'),
      isFalse,
      reason: '弹窗版实现应已删除，否则和 AboutPage 又是两份',
    );
    expect(
      source.contains('AppRoutes.about'),
      isTrue,
      reason: '抽屉的「关于」必须指向统一的 AboutPage 路由',
    );
  });

  test('AboutPage 是「关于」的唯一实现', () {
    expect(
      File('lib/features/about/presentation/about_page.dart').existsSync(),
      isTrue,
    );

    // 全仓扫一遍，确认没有别的地方又冒出一个关于弹窗。
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // 只看真实代码：注释里提到 showAboutDialog 是在记录"以前是弹窗"的历史，
      // 不剔掉注释的话这个守卫会被自己的文档说明误伤。
      final code = entity
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      if (code.contains('showAboutDialog')) offenders.add(entity.path);
    }

    expect(
      offenders,
      isEmpty,
      reason: '这些文件又自建了关于弹窗，会和 AboutPage 内容不一致：$offenders',
    );
  });
}
