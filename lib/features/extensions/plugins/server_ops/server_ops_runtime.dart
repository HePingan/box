// 服务器运维插件：运行期接缝（测试注入点）。
//
// 为什么要单独一个文件：页面（server_ops_page）要装配三个页签，三个页签各自
// 需要 host service / settings / files service；如果每个页签都各自 new 一个，
// widget 测试就没法一次把三处都换成假实现。集中在这里，与仓库既有插件
// （debugSetServiceMonitorRuntime / debugSetRemoteStorageRuntime）同一形状。

import 'package:flutter/material.dart';

import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/presentation/image_preview_dialog.dart';
import 'package:box/features/extensions/plugins/server_ops/host_service.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_files_service.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';

HostService _hostService = HostService();
ServerOpsSettings? _settingsOverride;
ServerOpsFilesService? _filesServiceOverride;

/// 打开图片预览的接缝。默认实现就是弹远端存储的相册对话框（相册滑动、缩放、
/// 20MB 上限、逐页失败不阻塞都在那里面）；widget 测试注入假实现即可，免得
/// 单测真的联网拉图 —— 那是 live 测试该干的事。
typedef OpsImagePreviewOpener = Future<void> Function(
  BuildContext context,
  RemoteStorageAccount account,
  List<RemoteStorageEntry> images,
  int initialIndex,
);

OpsImagePreviewOpener? _imagePreviewOpener;

/// 当前生效的图片预览实现。
OpsImagePreviewOpener get serverOpsImagePreviewOpener =>
    _imagePreviewOpener ?? showOpsImagePreviewDialog;

/// 默认图片预览：直接复用远端存储插件的相册对话框。
Future<void> showOpsImagePreviewDialog(
  BuildContext context,
  RemoteStorageAccount account,
  List<RemoteStorageEntry> images,
  int initialIndex,
) =>
    showDialog<void>(
      context: context,
      builder: (_) => ImagePreviewDialog(
        account: account,
        entries: images,
        initialIndex: initialIndex,
      ),
    );

/// 主机快照服务（页面用它拉快照 / 读缓存与历史）。
HostService get serverOpsHostService => _hostService;

/// 文件页用的服务：测试注入优先，否则按当前设置懒建。
ServerOpsFilesService serverOpsFilesService(ServerOpsSettings settings) =>
    _filesServiceOverride ?? ServerOpsFilesService(settings: settings);

/// 读设置：测试注入优先（避免 widget 测试依赖 SharedPreferences 的时序）。
Future<ServerOpsSettings> loadServerOpsSettings() async =>
    _settingsOverride ?? ServerOpsSettings.load();

/// 测试接缝：不传参就全部恢复默认。
void debugSetServerOpsRuntime({
  HostService? hostService,
  ServerOpsSettings? settings,
  ServerOpsFilesService? filesService,
  OpsImagePreviewOpener? imagePreviewOpener,
}) {
  _hostService = hostService ?? HostService();
  _settingsOverride = settings;
  _filesServiceOverride = filesService;
  _imagePreviewOpener = imagePreviewOpener;
}
