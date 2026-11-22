// 所有 `flutter test` 用例的统一入口（Flutter 约定：test/ 下存在本文件即自动加载）。
//
// 这里只关掉一件与业务无关、却会污染整个测试套的东西：
// `QuizPluginEntry._recordClientVersion()` 里对 `PackageInfo.fromPlatform()` 的
// `.timeout(2s)`。widget 测试没有 package_info 平台通道，那个 future 永不完成，
// 2 秒 timer 就永远 pending —— 于是**任何**调到 `buildDefaultPlugins` 的用例
// （哪怕只是建一份插件目录）都会报 "A Timer is still pending even after the
// widget tree was disposed"。放在全局入口关闭，比在每个用例里重复声明可靠。
//
// 生产行为不变：`versionProbeEnabled` 默认 true，真机照常上报版本号。
import 'dart:async';

import 'package:box/features/quiz_plugin/presentation/quiz_plugin_entry.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  QuizPluginEntry.versionProbeEnabled = false;
  await testMain();
}
