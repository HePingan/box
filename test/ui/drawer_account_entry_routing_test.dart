import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:box/app_drawer.dart';
import 'package:box/features/cloud_sync/domain/announcement_center.dart';
import 'package:box/app/app_routes.dart';
import 'package:box/features/account/data/account_store.dart';
import 'package:box/features/account/domain/account_models.dart';

/// B6：抽屉头卡按登录态路由。
///
/// 合并前：头卡无条件跳 `AppRoutes.account`（一个 393 行的登录表单页），
/// 功能更全的个人中心（额度/插件/题库/设置/公告 5 个 Tab）被埋在账号中心
/// 里面再点一层。已登录用户想看额度要走 抽屉 → 账号中心 → 个人中心。
///
/// 合并后：已登录直达个人中心（账号主页），未登录才进账号中心（登录页）。
void main() {
  setUp(() => globalSessionNotifier.value = null);
  tearDown(() => globalSessionNotifier.value = null);

  /// 记录被 push 的路由名，不真正构建目标页（目标页有网络依赖）。
  Future<List<String>> tapHeaderCard(WidgetTester tester) async {
    final pushed = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: (settings) {
          if (settings.name != null && settings.name != '/') {
            pushed.add(settings.name!);
          }
          return MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('stub')),
            settings: settings,
          );
        },
        home: ChangeNotifierProvider<AnnouncementCenter>.value(
          value: AnnouncementCenter(),
          child: const Scaffold(drawer: AppDrawer(), body: SizedBox()),
        ),
      ),
    );
    final scaffoldState = tester.state<ScaffoldState>(
      find.byType(Scaffold).last,
    );
    scaffoldState.openDrawer();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('drawer_header_card')));
    await tester.pumpAndSettle();
    return pushed;
  }

  testWidgets('未登录时头卡进账号中心（登录页）', (tester) async {
    globalSessionNotifier.value = null;
    final pushed = await tapHeaderCard(tester);
    expect(
      pushed,
      contains(AppRoutes.account),
      reason: '未登录只能先去登录，账号中心承担登录/注册',
    );
  });

  testWidgets('已登录时头卡直达个人中心，不再中转账号中心', (tester) async {
    globalSessionNotifier.value = const BoxAccountSession(
      serverUrl: 'https://example.invalid',
      token: 'token-for-test',
      user: BoxAccountUser(
        id: 'u1',
        username: 'tester',
        nickname: '测试用户',
        role: 'user',
        status: 'active',
      ),
    );
    final pushed = await tapHeaderCard(tester);
    expect(
      pushed,
      contains(AppRoutes.personalCenter),
      reason: '已登录用户的账号主页是个人中心，额度/设置都在那里',
    );
    expect(
      pushed,
      isNot(contains(AppRoutes.account)),
      reason: '不该再让已登录用户经过登录页中转',
    );
  });
}
