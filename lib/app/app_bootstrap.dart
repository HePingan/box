import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/admin/register_providers.dart';
import '../novel/pages/source_manager/book_source_bootstrap.dart';
import '../platform/window_diagnostics_channel.dart';
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
    await _attachWindowDiagnostics();
    _installErrorHandlers();
    _configureSystemUi();
    _configureImageCache();

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

  /// 接上原生小窗诊断通道。
  ///
  /// 必须排在 [_initLogger] 之后：原生会回放引擎就绪前缓冲的早期事件，
  /// AppLogger 还没 init 的话这批最关键的现场会落空。
  static Future<void> _attachWindowDiagnostics() async {
    try {
      await WindowDiagnosticsChannel().attach();
    } catch (e) {
      debugPrint('WindowDiagnostics attach failed: $e');
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

  /// 扩容全局图片内存缓存。
  ///
  /// 默认上限 1000 张 / 100MB。首页是 2 列大封面墙 + 滚动预取，
  /// 默认池容易把刚滑过的大图挤出，往回滚要重新解码。提到 ~256MB /
  /// 更多张数后，回滚立即命中内存、不重解码。纯内存配置、可回退。
  static void _configureImageCache() {
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.maximumSize = 400;
    imageCache.maximumSizeBytes = 256 * 1024 * 1024;
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
