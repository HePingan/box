import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:box/app_drawer.dart';
import 'package:box/features/account/presentation/account_page.dart';
import 'package:box/features/cloud_sync/domain/announcement_center.dart';
import 'package:box/features/cloud_sync/data/announcement_service.dart';
import 'package:box/features/cloud_sync/domain/cloud_sync_models.dart';
import 'package:box/features/settings/presentation/data_settings_page.dart';

/// 抽屉信息架构 B 阶段回归。
///
/// B 阶段的三条改动都指向同一个毛病：同一个目的地有多个入口，
/// 以及需要成对使用的功能被拆散在长列表里。
///
///  1. 「账号」此前有三个入口（头部卡片、「账号中心」、原「设置」）。
///     A 阶段修掉了「设置」，B 阶段让头部卡片成为唯一入口。
///  2. 公告未读红点原先只在「更多」列表里，划开抽屉不滚动可能看不到；
///     提到常驻可见的头部卡片上。
///  3. 备份/恢复是成对功能，挪进「数据设置」二级页，抽屉只留一个入口。
AnnouncementEntry _entry(String id) => AnnouncementEntry(
  id: id,
  title: 't-$id',
  body: 'b-$id',
  level: 'info',
  publishedAt: DateTime(2026, 1, 1),
  pinned: false,
  linkUrl: '',
);

/// 假公告服务：不打真网络，直接给定未读状态。
class _FakeAnnouncementService extends AnnouncementService {
  _FakeAnnouncementService({required this.remote}) : super(prefs: _prefs);

  static late SharedPreferences _prefs;

  final AnnouncementState remote;

  @override
  Future<AnnouncementState> load({bool force = false}) async => remote;

  @override
  Future<AnnouncementState> loadCachedOnly() async => AnnouncementState.empty;

  @override
  Future<Set<String>> markRead(String id) async => {id};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _FakeAnnouncementService._prefs = await SharedPreferences.getInstance();
    PackageInfo.setMockInitialValues(
      appName: 'Box',
      packageName: 'top.hpa888.box',
      version: '1.9.7',
      buildNumber: '197',
      buildSignature: '',
    );
  });

  Future<void> pumpDrawer(
    WidgetTester tester, {
    AnnouncementCenter? center,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<AnnouncementCenter>.value(
        value: center ?? AnnouncementCenter(),
        child: MaterialApp(
          routes: {
            '/account': (_) => const AccountPage(),
            '/settings/data': (_) => const DataSettingsPage(),
          },
          home: const Scaffold(drawer: AppDrawer(), body: SizedBox.shrink()),
        ),
      ),
    );
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();
  }

  group('账号入口唯一化', () {
    testWidgets('「更多」列表不再有「账号中心」', (tester) async {
      await pumpDrawer(tester);
      expect(
        find.text('账号中心'),
        findsNothing,
        reason: '头部卡片本身就是账号入口，列表里再列一条是同一目的地的第二个入口',
      );
    });

    testWidgets('点头部卡片仍能进账号页', (tester) async {
      await pumpDrawer(tester);

      await tester.tap(find.text('未登录'));
      await tester.pumpAndSettle();

      expect(find.byType(AccountPage), findsOneWidget);
    });
  });

  group('备份/恢复并入数据设置', () {
    testWidgets('抽屉不再直接列备份与恢复两项', (tester) async {
      await pumpDrawer(tester);
      expect(find.text('备份本地数据'), findsNothing);
      expect(find.text('恢复本地数据'), findsNothing);
    });

    testWidgets('抽屉「数据」组用一个「备份与恢复」入口进二级页', (tester) async {
      await pumpDrawer(tester);

      expect(find.text('备份与恢复'), findsOneWidget);
      await tester.ensureVisible(find.text('备份与恢复'));
      await tester.tap(find.text('备份与恢复'));
      await tester.pumpAndSettle();

      expect(find.byType(DataSettingsPage), findsOneWidget);
    });

    testWidgets('二级页里备份与恢复两项都在', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: DataSettingsPage()),
      );
      await tester.pumpAndSettle();

      expect(find.text('备份本地数据'), findsOneWidget);
      expect(find.text('恢复本地数据'), findsOneWidget);
    });
  });

  group('公告未读红点提到头部卡片', () {
    testWidgets('有未读时头部卡片上出现红点计数', (tester) async {
      final center = AnnouncementCenter(
        service: _FakeAnnouncementService(
          remote: AnnouncementState(
            items: [_entry('a1'), _entry('a2')],
            readIds: const {},
            fetchedAt: DateTime(2026, 1, 1),
            fromCache: false,
          ),
        ),
      );
      await center.bootstrap();
      expect(center.unreadCount, 2, reason: 'fake 数据没造出未读，后面的断言就没意义');

      await pumpDrawer(tester, center: center);

      // 用 key 定位，避免与「更多」列表里那个同样显示条数的徽标混淆。
      final badge = find.byKey(const Key('drawer_header_unread_badge'));
      expect(badge, findsOneWidget);
      expect(
        find.descendant(of: badge, matching: find.text('2')),
        findsOneWidget,
      );
    });

    testWidgets('无未读时头部卡片不显示徽标', (tester) async {
      await pumpDrawer(tester);
      expect(
        find.byKey(const Key('drawer_header_unread_badge')),
        findsNothing,
      );
    });
  });
}
