import 'package:flutter/widgets.dart';

import '../features/account/presentation/account_page.dart';
import '../novel/pages/source_manager/book_source_bootstrap.dart';
import '../novel/pages/source_manager/book_source_manager_page.dart';
import '../pages/debug_log_page.dart';

class AppRoutes {
  const AppRoutes._();

  static const debugLog = '/debug-log';
  static const bookSourceManager = '/book-source-manager';
  static const account = '/account';

  static Map<String, WidgetBuilder> buildRoutes(
    BookSourceBootstrapResult novelBootstrap,
  ) {
    return {
      debugLog: (_) => const DebugLogPage(),
      account: (_) => const AccountPage(),
      bookSourceManager: (_) => BookSourceManagerPage(
        startupMessage: novelBootstrap.configured ? '' : novelBootstrap.message,
      ),
    };
  }
}
