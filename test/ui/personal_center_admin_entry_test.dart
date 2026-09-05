import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/account/domain/account_models.dart';
import 'package:box/features/account/presentation/widgets/personal_center_admin_entry.dart';

/// B6：个人中心成为账号主页后，管理后台入口必须在这里出现。
///
/// 合并前管理后台只挂在账号中心（AccountStatusCard.onAdminTap）。头卡改为
/// 已登录直达个人中心后，管理员就再也看不到后台入口了 —— 这个测试守住它。
///
/// 同时守住权限边界：非管理员不得看到入口（个人能力与管理员后台分离）。
void main() {
  Future<void> pumpEntry(WidgetTester tester, BoxAccountUser? user) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PersonalCenterAdminEntry(user: user, onTap: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  BoxAccountUser userWithRole(String role) => BoxAccountUser(
    id: 'u1',
    username: 'tester',
    nickname: '测试用户',
    role: role,
    status: 'normal',
  );

  testWidgets('管理员能在个人中心看到管理后台入口', (tester) async {
    await pumpEntry(tester, userWithRole('admin'));
    expect(find.text('管理后台'), findsOneWidget);
  });

  testWidgets('普通用户看不到管理后台入口', (tester) async {
    await pumpEntry(tester, userWithRole('user'));
    expect(
      find.text('管理后台'),
      findsNothing,
      reason: '个人能力与管理员后台分离，普通用户不该看到管理入口',
    );
  });

  testWidgets('未登录（user 为空）不显示管理后台入口', (tester) async {
    await pumpEntry(tester, null);
    expect(find.text('管理后台'), findsNothing);
  });
}
