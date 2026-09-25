// ignore_for_file: non_const_argument_for_const_parameter

// P2-2：页面装配（从 home_plugin_core.dart 拆出）。
//
// 这里集中「路由 code → 具体页面」的绑定。core 只保留注册表容器
// （HomePluginRouteRegistry 的 register/lookup/contains），不再直接
// 依赖任何具体 UI 页面。

import 'package:flutter/material.dart';

import 'package:box/daily_news_page.dart';
import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:box/features/extensions/plugins/github_accel/github_accel_sheet.dart';
import 'package:box/features/extensions/plugins/monitor/monitor_page.dart';
import 'package:box/features/extensions/plugins/remote_storage/presentation/remote_storage_page.dart';
import 'package:box/features/image_generator/presentation/image_generator_page.dart';
import 'package:box/novel/pages/novel_list_page.dart';
import 'package:box/video/video_compat_pages.dart';

/// 注册内置路由默认绑定（P2-2 从 HomePluginRouteRegistry.registerDefaults 拆出）。
///
/// 保持与拆分前逐条一致：同一页面绑定两个 code（短码 + open 前缀码）。
void registerBuiltinRouteDefaults() {
  HomePluginRouteRegistry.register('daily_news', (_) => const DailyNewsPage());
  HomePluginRouteRegistry.register(
    'openDailyNews',
    (_) => const DailyNewsPage(),
  );
  HomePluginRouteRegistry.register(
    'novel_list',
    (_) => const NovelListPageWithProvider(),
  );
  HomePluginRouteRegistry.register(
    'openNovelList',
    (_) => const NovelListPageWithProvider(),
  );
  HomePluginRouteRegistry.register(
    'video_list',
    (_) => const VideoListPage(),
  );
  HomePluginRouteRegistry.register(
    'openVideoList',
    (_) => const VideoListPage(),
  );
  HomePluginRouteRegistry.register(
    'image_generator',
    (_) => const ImageGeneratorPage(),
  );
  HomePluginRouteRegistry.register(
    'openImageGenerator',
    (_) => const ImageGeneratorPage(),
  );
  HomePluginRouteRegistry.register(
    'remote_storage',
    (_) => const RemoteStoragePage(),
  );
  HomePluginRouteRegistry.register(
    'openRemoteStorage',
    (_) => const RemoteStoragePage(),
  );
  HomePluginRouteRegistry.register(
    'service_monitor',
    (_) => const ServiceMonitorPage(),
  );
  HomePluginRouteRegistry.register(
    'openServiceMonitor',
    (_) => const ServiceMonitorPage(),
  );
}

/// GitHub 加速下载动作（P2-2 从 HomePluginActionRegistry 的 handler 拆出）。
///
/// 它是底部面板不是整页，所以走 show 而非 Navigator.push；
/// 空 context 直接忽略（与拆分前行为一致）。
Future<void> showGithubAccelAction(
  BuildContext? context,
  String initialUrl,
) async {
  if (context == null) return;
  await GithubAccelSheet.show(context, initialUrl: initialUrl);
}
