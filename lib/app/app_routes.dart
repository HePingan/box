import 'package:flutter/widgets.dart';

import '../features/account/presentation/account_page.dart';
import '../features/account/presentation/personal_center_page.dart';
import '../features/admin/presentation/admin_page.dart';
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

  static Map<String, WidgetBuilder> buildRoutes(
    BookSourceBootstrapResult novelBootstrap,
  ) {
    return {
      debugLog: (_) => const DebugLogPage(),
      account: (_) => const AccountPage(),
      personalCenter: (_) => const PersonalCenterPage(),
      accountAdmin: (_) => const AdminPage(),
      bookSourceManager: (_) => BookSourceManagerPage(
        startupMessage: novelBootstrap.configured ? '' : novelBootstrap.message,
      ),
    };
  }
}
