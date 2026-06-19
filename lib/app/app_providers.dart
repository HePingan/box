import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../novel/pages/source_manager/book_source_manager.dart';
import '../video_module.dart';
import 'app_bootstrap.dart';

class AppProviders extends StatelessWidget {
  const AppProviders({super.key, required this.bootstrap, required this.child});

  final AppBootstrapResult bootstrap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Use Provider (not ChangeNotifierProvider) to wrap the ChangeNotifiers.
    // Provider does NOT create an InheritedNotifier, so notifyListeners()
    // will never trigger the InheritedNotifier ancestry assertion.
    // Consumers still use context.watch<T>() and context.select<T, R>() normally.
    return MultiProvider(
      providers: [
        Provider<BookSourceManager>(
          create: (_) => BookSourceManager(bootstrap.prefs),
        ),
        Provider<VideoController>(
          create: (_) => VideoController(),
        ),
        Provider<HistoryController>(
          create: (_) => HistoryController(),
        ),
      ],
      child: child,
    );
  }
}
