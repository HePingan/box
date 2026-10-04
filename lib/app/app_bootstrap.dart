import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../design_system/app_tokens.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/admin/register_providers.dart';
import '../features/comic/domain/comic_offline_downloader.dart';
import '../features/comic/domain/comic_offline_store.dart';
import '../features/comic/presentation/comic_offline_wiring.dart';
import '../novel/pages/source_manager/book_source_bootstrap.dart';
import '../platform/flutter_viewport_diagnostics.dart';
import '../platform/window_diagnostics_channel.dart';
import '../utils/app_logger.dart';
import '../utils/diagnostic_report.dart';
import '../utils/log_channels.dart';
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
    applySystemUi();
    _configureImageCache();

    final prefs = await SharedPreferences.getInstance();
    final novelBootstrap = await BookSourceBootstrap.loadAndConfigure(prefs);
    _configureVideoCatalog();
    _configureComicDownloads();
    registerResourceProviders();

    return AppBootstrapResult(prefs: prefs, novelBootstrap: novelBootstrap);
  }

  static Future<void> _initLogger() async {
    try {
      await AppLogger.instance.init();
    } catch (e) {
      debugPrint('AppLogger init failed: $e');
    }

    // 预取版本/系统信息，供诊断报告同步取用。
    // 放在这里而不是复制时才取：复制是报障的核心动作，不能等 platform channel。
    await DiagnosticHeader.prime();
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

    // Flutter 侧视口诊断：原生日志只能证明 Android 窗口尺寸变了，
    // 证明不了 Flutter 的 physicalSize 有没有跟上。两层都记，才能区分
    // 「原生没恢复」和「原生恢复了但 Flutter 视口没同步」。
    try {
      FlutterViewportDiagnostics().attach();
    } catch (e) {
      debugPrint('FlutterViewportDiagnostics attach failed: $e');
    }
  }

  static void _installErrorHandlers() {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);

      // 走 error 频道 + error 级别：崩溃现场是报障时第一个要看的东西，
      // 以前记成 FLUTTER/info，用户点「仅错误」反而筛不到。
      AppLogger.instance.logTo(
        LogChannel.error,
        'FlutterError: ${details.exceptionAsString()}',
        level: LogLevel.error,
      );

      if (details.stack != null) {
        AppLogger.instance.logTo(
          LogChannel.error,
          details.stack.toString(),
          level: LogLevel.error,
        );
      }
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      AppLogger.instance.logChannelError(LogChannel.error, error, stack);
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

  /// 应用系统状态栏/导航栏样式。
  ///
  /// 图标亮度**必须跟着深色外壳走**：写死 `Brightness.dark`（深色图标）在浅色底上
  /// 才对，深色底上会让时间、电量、导航键全部看不见。原先这里是一个 `const`
  /// 样式，深色模式接进来时立刻会成为真机上的第一眼 bug。
  ///
  /// 深浅切换时由 `_BoxAppState` 再调一次，不只是启动时调。
  static void applySystemUi() {
    final dark = AppTokens.isDark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: dark ? AppTokens.surface : Colors.white,
        systemNavigationBarIconBrightness:
            dark ? Brightness.light : Brightness.dark,
      ),
    );
  }

  /// 漫画离线下载的启动接线：装网络策略 + 清 `.part` 残渣 + **允许时**自动续下。
  ///
  /// 续下（`autoResumeIfAllowed`）**不在这里**：它要能"取一话的图片地址"，
  /// 而那个 loader 要等漫画页起来才接得上（`setLoadImages`）—— 接在漫画页那里，
  /// 顺带也覆盖了"用户上次就是在看漫画时点的下载"。这里只收残渣。
  static void _configureComicDownloads() {
    final store = ComicOfflineStore();
    final downloader = ComicOfflineDownloader.shared();
    wireComicOfflineNetworkGuard(downloader);
    unawaited(() async {
      try {
        // 下了一半留下的残渣会被算进"离线占用"，却没人能删 —— 启动时收一次。
        final freed = await store.purgePartials();
        if (freed > 0) {
          AppLogger.instance.logTo(
            LogChannel.system,
            '漫画离线下载：清掉未完成的残渣 $freed 字节',
          );
        }
      } catch (_) {
        // 清理失败不影响启动。
      }
    }());
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
