import 'package:flutter/widgets.dart';

import '../features/account/presentation/account_page.dart';
import '../features/account/presentation/personal_center_page.dart';
import '../features/admin/presentation/admin_page.dart';
import '../features/cloud_sync/presentation/announcement_page.dart';
import '../novel/pages/source_manager/book_source_bootstrap.dart';
import '../novel/pages/source_manager/book_source_manager_page.dart';
import '../pages/debug_log_page.dart';

class AppRoutes {
  const AppRoutes._();

  static const debugLog = '/debug-log';
  static const bookSourceManager = '/book-source-manager';
  static const account = '/account';
  static const personalCenter = '/account/personal-center';
  static const accountAdmin = '/account/admin';

  /// 公告一级入口。原先只能从「抽屉 → 账号 → 个人中心」三层点进去，
  /// 线上出故障时等于没有触达手段。
  static const announcements = '/announcements';

  static Map<String, WidgetBuilder> buildRoutes(
    BookSourceBootstrapResult novelBootstrap,
  ) {
    return {
      debugLog: (_) => const DebugLogPage(),
      account: (_) => const AccountPage(),
      personalCenter: (_) => const PersonalCenterPage(),
      accountAdmin: (_) => const AdminPage(),
      announcements: (_) => const AnnouncementPage(),
      bookSourceManager: (_) => BookSourceManagerPage(
        startupMessage: novelBootstrap.configured ? '' : novelBootstrap.message,
      ),
    };
  }
}
