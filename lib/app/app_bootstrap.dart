import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/admin/register_providers.dart';
import '../novel/pages/source_manager/book_source_bootstrap.dart';
import '../utils/app_logger.dart';
import '../utils/http_overrides.dart';
import '../video/config/video_proxy_config.dart';
import '../video_module.dart';

class AppBootstrapResult {
  const AppBootstrapResult({required this.prefs, required this.novelBootstrap});

  final SharedPreferences prefs;
  final BookSourceBootstrapResult novelBootstrap;
}

class AppBootstrap {
  static Future<AppBootstrapResult> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 证书忽略：仅调试环境启用，避免 release 全局接受不安全 HTTPS 证书。
    if (kDebugMode) {
      enableInsecureCertificateOverrides();
    }

    await Hive.initFlutter();
    await _initLogger();
    _installErrorHandlers();
    _configureSystemUi();

    final prefs = await SharedPreferences.getInstance();
    final novelBootstrap = await BookSourceBootstrap.loadAndConfigure(prefs);
    _configureVideoCatalog();
    registerResourceProviders();

    return AppBootstrapResult(prefs: prefs, novelBootstrap: novelBootstrap);
  }

  static Future<void> _initLogger() async {
    try {
      await AppLogger.instance.init();
    } catch (e) {
      debugPrint('AppLogger init failed: $e');
    }
  }

  static void _installErrorHandlers() {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);

      AppLogger.instance.log(
        'FlutterError: ${details.exceptionAsString()}',
        tag: 'FLUTTER',
      );

      if (details.stack != null) {
        AppLogger.instance.log(details.stack.toString(), tag: 'FLUTTER');
      }
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      AppLogger.instance.logError(error, stack, 'DART');
      return true;
    };
  }

  static void _configureSystemUi() {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
  }

  static void _configureVideoCatalog() {
    VideoModule.configureLicensedCatalogSource(
      catalogName: 'OuonnkiTV',
      catalogUrls: const [
        kDefaultVideoCatalogUrlFormat0,
        kDefaultVideoCatalogUrlFormat1,
      ],
    );
  }
}
