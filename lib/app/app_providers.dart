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
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<BookSourceManager>(
          create: (_) => BookSourceManager(bootstrap.prefs)..load(),
        ),
        ChangeNotifierProvider<VideoController>(
          create: (_) => VideoController(),
        ),
        ChangeNotifierProvider<HistoryController>(
          create: (_) {
            final controller = HistoryController();
            controller.loadHistory();
            return controller;
          },
        ),
      ],
      child: child,
    );
  }
}
