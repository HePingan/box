import 'package:flutter/widgets.dart';

import '../novel/pages/source_manager/book_source_bootstrap.dart';
import '../novel/pages/source_manager/book_source_manager_page.dart';
import '../pages/debug_log_page.dart';

class AppRoutes {
  const AppRoutes._();

  static const debugLog = '/debug-log';
  static const bookSourceManager = '/book-source-manager';

  static Map<String, WidgetBuilder> buildRoutes(
    BookSourceBootstrapResult novelBootstrap,
  ) {
    return {
      debugLog: (_) => const DebugLogPage(),
      bookSourceManager: (_) => BookSourceManagerPage(
        startupMessage: novelBootstrap.configured ? '' : novelBootstrap.message,
      ),
    };
  }
}
