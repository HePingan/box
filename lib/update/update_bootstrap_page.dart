import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'update_dialog.dart';
import 'update_service.dart';
import 'update_models.dart';

class UpdateBootstrapPage extends StatefulWidget {
  final Widget nextPage;
  final String appId;
  final String checkUrl;
  final String platform;
  final String channel;

  /// 强更检查失败时是否允许进入主界面
  final bool allowProceedOnCheckFailure;

  const UpdateBootstrapPage({
    super.key,
    required this.nextPage,
    required this.appId,
    required this.checkUrl,
    required this.platform,
    required this.channel,
    this.allowProceedOnCheckFailure = true,
  });

  @override
  State<UpdateBootstrapPage> createState() => _UpdateBootstrapPageState();
}

class _UpdateBootstrapPageState extends State<UpdateBootstrapPage> {
  bool _loading = true;
  String? _error;
  bool _navigated = false;

  PackageInfo? _packageInfo;
  UpdateManifest? _manifest;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    if (kIsWeb) {
      _goNext();
      return;
    }

    try {
      final info = await PackageInfo.fromPlatform();
      _packageInfo = info;

      final currentCode = int.tryParse(info.buildNumber) ?? 0;

      final manifest = await UpdateService.instance.checkUpdate(
        checkUrl: widget.checkUrl,
        appId: widget.appId,
        platform: widget.platform,
        channel: widget.channel,
        versionCode: currentCode,
        packageName: info.packageName,
      );

      if (!mounted) return;

      if (manifest == null) {
        if (widget.allowProceedOnCheckFailure) {
          _goNext();
        } else {
          setState(() {
            _loading = false;
            _error = '无法获取更新信息';
          });
        }
        return;
      }
_manifest = manifest;

      // ==========================================
      // 🔥 终极铁门：硬性物理拦截！
      // 只要服务端的版本号 <= 手机自己现在的版本号，
      // 直接假装无事发生，放行进首页，绝不允许后续的弹窗判断运行！
      // ==========================================
      if (manifest.latestVersionCode <= currentCode) {
        _goNext();
        return;
      }

      final force = manifest.needForceUpdate(currentCode);
      final hasNew = manifest.hasNewVersion(currentCode);

      if (force || hasNew) {
        await _showUpdateDialog(force: force);
        return;
      }

      _goNext();
    } catch (e) {
      if (!mounted) return;

      if (widget.allowProceedOnCheckFailure) {
        _goNext();
      } else {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _showUpdateDialog({required bool force}) async {
    if (!mounted) return;
    final info = _packageInfo!;
    final manifest = _manifest!;

    await showDialog(
      context: context,
      barrierDismissible: !force,
      builder: (_) {
        return UpdateDialog(
          manifest: manifest,
          currentVersionName: info.version,
          currentVersionCode: int.tryParse(info.buildNumber) ?? 0,
          force: force,
        );
      },
    );

    // 非强制更新时，关闭后进入
    if (!force) {
      _goNext();
    }
  }

  void _goNext() {
    if (_navigated || !mounted) return;
    _navigated = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => widget.nextPage),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F8FC),
        body: Center(
          child: _loading
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 14),
                    Text('正在检查版本...'),
                  ],
                )
              : _error == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () {
                              setState(() {
                                _loading = true;
                                _error = null;
                              });
                              _bootstrap();
                            },
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }
}