// 服务器运维插件：运行期接缝（测试注入点）。
//
// 为什么要单独一个文件：页面（server_ops_page）要装配三个页签，三个页签各自
// 需要 host service / settings / files service；如果每个页签都各自 new 一个，
// widget 测试就没法一次把三处都换成假实现。集中在这里，与仓库既有插件
// （debugSetServiceMonitorRuntime / debugSetRemoteStorageRuntime）同一形状。

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/server_ops/monitor_service.dart';
import 'package:box/features/extensions/plugins/remote_storage/presentation/image_preview_dialog.dart';
import 'package:box/features/extensions/plugins/server_ops/host_service.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_api_client.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_diagnostics.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_download_cache.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_files_service.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';

HostService _hostService = HostService();
ServerOpsSettings? _settingsOverride;
ServerOpsFilesService? _filesServiceOverride;

/// 按设置**现建**只读接口客户端的接缝（写档）：文件页的「解压」「改权限」走它。
/// 用例注入假客户端就不会联网；不注入时按当前这台机器的地址与令牌现建。
OpsApiClient Function(ServerOpsSettings settings)? _apiClientFactory;

/// 当前生效的只读接口客户端（每台机器一套地址与令牌）。
OpsApiClient serverOpsApiClient(ServerOpsSettings settings) {
  final factory = _apiClientFactory;
  if (factory != null) return factory(settings);
  return OpsApiClient(
    baseUrl: settings.effectiveApiUrl,
    token: settings.effectiveApiToken,
  );
}

/// 按设置**现建**文件服务的接缝（B1）：页面每换一台服务器都会重问一次，
/// 用它就能断言"切完之后连的到底是哪台"（假实现里读 settings.effectiveBaseUrl）。
ServerOpsFilesService Function(ServerOpsSettings settings)? _filesServiceFactory;

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

/// 终端探针的接缝：默认真发一次 HTTP；widget 测试注入假实现，避免单测联网。
OpsTerminalProbe? _terminalProbe;

/// 当前生效的终端探针。
OpsTerminalProbe get serverOpsTerminalProbe =>
    _terminalProbe ?? probeOpsTerminal;

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

/// 选中的本地文件（把 file_picker 的 PlatformFile 折成插件自己的最小视图：
/// 页面只用到名字与路径，用例也不必依赖 file_picker 的平台实现——它是 abstract）。
class OpsPickedFile {
  const OpsPickedFile({required this.name, required this.path});

  final String name;

  /// 本机绝对路径；为空串表示"这个文件本机没有可直接读取的路径"。
  final String path;
}

/// 「多选本地文件」的接缝：默认真调系统文件选择器（多选）；widget 测试注入假实现。
typedef OpsFilePicker = Future<List<OpsPickedFile>> Function();

Future<List<OpsPickedFile>> _defaultPickFiles() async {
  final picked = await FilePicker.pickFiles();
  return [
    for (final file in picked)
      OpsPickedFile(name: file.name, path: file.path ?? ''),
  ];
}

OpsFilePicker _filePicker = _defaultPickFiles;

/// 当前生效的文件选择器。
OpsFilePicker get serverOpsPickFiles => _filePicker;

/// 下载缓存（A8）：默认落 path_provider 的临时目录；widget 测试注入假实现，
/// 免得单测碰到平台通道。
ServerOpsDownloadCache _downloadCache = ServerOpsDownloadCache();

ServerOpsDownloadCache get serverOpsDownloadCache => _downloadCache;

/// 站点快照（monitors.json）服务：体检卡用它取"证书还剩几天 / 站点在不在线"。
/// 与主机快照同一条链路、同一个令牌；测试注入假实现就不联网。
MonitorService _monitorService = MonitorService();

MonitorService get serverOpsMonitorService => _monitorService;

/// 文件页用的服务：测试注入优先，否则按当前设置懒建。
ServerOpsFilesService serverOpsFilesService(ServerOpsSettings settings) =>
    _filesServiceFactory?.call(settings) ??
    _filesServiceOverride ??
    ServerOpsFilesService(settings: settings);

/// 清掉 WebView 缓存的 HTTP Basic 凭据（296）。
///
/// 为什么要有：Android WebView 把 Basic 凭据按 (源 + realm) 缓存，**缓存命中时
/// `onHttpAuthRequest` 不会被调用**，于是"在设置里换成设备凭据之后，终端页还在用旧口令"
/// （真机日志里 `/term/ws` 带的还是旧用户名）。默认实现走平台通道；平台侧没有
/// （单测、非 Android、老安装）就静静返回 —— 清不掉最多是这次仍按缓存问一次，
/// 不该让终端页打不开。
typedef OpsWebViewAuthCacheClearer = Future<void> Function();

OpsWebViewAuthCacheClearer _clearWebViewAuthCacheImpl = _clearWebViewAuthCacheDefault;

Future<void> _clearWebViewAuthCacheDefault() async {
  try {
    await const MethodChannel('top.hpa888.box/webview_auth_cache')
        .invokeMethod<bool>('clear');
  } catch (_) {
    // 见上：平台差异不参与正确性判断
  }
}

/// 当前生效的实现。
OpsWebViewAuthCacheClearer get serverOpsClearWebViewAuthCache =>
    _clearWebViewAuthCacheImpl;

/// 读设置：测试注入优先（避免 widget 测试依赖 SharedPreferences 的时序）。
Future<ServerOpsSettings> loadServerOpsSettings() async =>
    _settingsOverride ?? ServerOpsSettings.load();

/// 测试接缝：不传参就全部恢复默认。
void debugSetServerOpsRuntime({
  HostService? hostService,
  ServerOpsSettings? settings,
  ServerOpsFilesService? filesService,
  ServerOpsFilesService Function(ServerOpsSettings settings)? filesServiceFactory,
  OpsImagePreviewOpener? imagePreviewOpener,
  OpsTerminalProbe? terminalProbe,
  OpsFilePicker? filePicker,
  ServerOpsDownloadCache? downloadCache,
  OpsApiClient Function(ServerOpsSettings settings)? apiClientFactory,
  OpsWebViewAuthCacheClearer? webViewAuthCacheClearer,
  MonitorService? monitorService,
}) {
  _hostService = hostService ?? HostService();
  _settingsOverride = settings;
  _filesServiceOverride = filesService;
  _filesServiceFactory = filesServiceFactory;
  _imagePreviewOpener = imagePreviewOpener;
  _terminalProbe = terminalProbe;
  _filePicker = filePicker ?? _defaultPickFiles;
  _downloadCache = downloadCache ?? ServerOpsDownloadCache();
  _apiClientFactory = apiClientFactory;
  _monitorService = monitorService ?? MonitorService();
  _clearWebViewAuthCacheImpl =
      webViewAuthCacheClearer ?? _clearWebViewAuthCacheDefault;
}
