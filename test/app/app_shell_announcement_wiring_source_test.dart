import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 源码级闸门：确认 AppShell 真的接了公告启动流程。
///
/// 为什么需要这种「读源码」的测试：app_shell_announcement_wiring_test.dart 用的是
/// 复刻的 _ShellLike（真 AppShell 依赖十几个 provider 和平台通道，单测里起不来），
/// 所以那组测试证明不了真实 shell 有接线 —— 把 app_shell.dart 里的调用整段删掉，
/// 它照样全绿。
///
/// 这正是 183/184/185 事故的形状：零件都好，接线是断的，而没有任何测试守着接线。
/// 所以这里直接断言源文件里存在那几处调用。
void main() {
  late String shellSource;
  late String providersSource;
  late String drawerSource;

  setUpAll(() {
    shellSource = File('lib/app/app_shell.dart').readAsStringSync();
    providersSource = File('lib/app/app_providers.dart').readAsStringSync();
    drawerSource = File('lib/app_drawer.dart').readAsStringSync();
  });

  test('AppShell 在首帧回调里调用了 AnnouncementCenter.bootstrap()', () {
    expect(
      shellSource.contains('AnnouncementCenter'),
      isTrue,
      reason: 'AppShell 必须持有 AnnouncementCenter',
    );
    expect(
      shellSource.contains('.bootstrap()'),
      isTrue,
      reason: '删掉 bootstrap 调用则公告永远不会在启动时拉取',
    );
    expect(
      shellSource.contains('addPostFrameCallback'),
      isTrue,
      reason: '必须放在首帧之后，不能阻塞冷启动',
    );
  });

  test('AppShell 接了弹窗调用', () {
    expect(
      shellSource.contains('showAnnouncementPopup'),
      isTrue,
      reason: '删掉弹窗调用则重要公告不会主动触达用户',
    );
    expect(
      shellSource.contains('takePopup'),
      isTrue,
      reason: '需要经由 takePopup 做单次交付判断',
    );
  });

  test('AnnouncementCenter 注册在 app 作用域而不是页面作用域', () {
    expect(
      providersSource.contains('ChangeNotifierProvider<AnnouncementCenter>'),
      isTrue,
      reason: '挂在页面上就会回到「页面不开就不拉」的老问题',
    );
  });

  test('抽屉有公告一级入口', () {
    expect(
      drawerSource.contains('AppRoutes.announcements'),
      isTrue,
      reason: '公告不能只藏在「抽屉 → 账号 → 个人中心」三层之下',
    );
    expect(
      drawerSource.contains('AnnouncementCenter'),
      isTrue,
      reason: '入口要带未读角标，用户才知道有新公告',
    );
  });

  test('已删除从未被调用的 refreshAnnouncementBadge 死代码', () {
    final controller = File(
      'lib/features/account/presentation/controllers/'
      'personal_center_controller.dart',
    ).readAsStringSync();
    expect(
      controller.contains('Future<void> refreshAnnouncementBadge()'),
      isFalse,
      reason: '该方法定义了却从未被调用，职责已由 AnnouncementCenter 接管',
    );
  });
}
