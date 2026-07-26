import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../novel/pages/source_manager/book_source_manager.dart';
import '../video_module.dart';
import 'app_bootstrap.dart';
import '../video/controller/video_download_controller.dart';
import '../video/services/hive_video_download_repository.dart';
import '../video/services/video_download_gateway.dart';

class AppProviders extends StatelessWidget {
  const AppProviders({super.key, required this.bootstrap, required this.child});

  final AppBootstrapResult bootstrap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<BookSourceManager>(
          create: (_) => BookSourceManager(bootstrap.prefs),
        ),
        Provider<VideoController>(create: (_) => VideoController()),
        Provider<HistoryController>(create: (_) => HistoryController()),
        ChangeNotifierProvider<FavoritesController>(
          create: (_) => FavoritesController(),
        ),
        ChangeNotifierProvider<VideoDownloadController>(
          // load() 会加载持久化任务并启动平台进度轮询（_startPolling）。
          // 之前从未调用 load()，导致轮询不启动、snapshots 永不刷新、进度条一直转圈。
          create: (_) => VideoDownloadController(
            repository: HiveVideoDownloadRepository(),
            gateway: MethodChannelVideoDownloadGateway(),
          )..load(),
        ),
      ],
      child: child,
    );
  }
}
