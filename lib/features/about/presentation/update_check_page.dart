import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../design_system/app_tokens.dart';
import '../../../update/manual_update_check.dart';

/// 关于页里的「检查更新」整页入口。
///
/// 为什么是一个页面而不是直接在关于页上触发：
/// 关于页是 ListView，点一下要么弹 SnackBar 要么原地转圈，两种都容易被
/// 当成「没反应」。给它一块独立的地方，进度和结论都有位置显示。
///
/// 检查逻辑走 [ManualUpdateCheck.run]（与抽屉共用同一份实现）。这里是整页、
/// 没有抽屉遮挡，所以用默认的 SnackBar 模式而不是 `resultInDialog`。
class UpdateCheckPage extends StatefulWidget {
  const UpdateCheckPage({
    super.key,
    this.versionOverride,
    this.onCheck,
  });

  /// 仅测试注入：widget test 里 [PackageInfo.fromPlatform] **既不抛异常也不返回**
  /// （实测会一直挂住），所以必须能注入，否则页面永远停在"读取中…"。
  final String? versionOverride;

  /// 仅测试注入：替换真实的检查动作，避免测试打网络。
  final Future<void> Function(BuildContext context)? onCheck;

  @override
  State<UpdateCheckPage> createState() => _UpdateCheckPageState();
}

class _UpdateCheckPageState extends State<UpdateCheckPage> {
  String? _version;
  bool _versionFailed = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    if (widget.versionOverride != null) {
      _version = widget.versionOverride;
    } else {
      _loadVersion();
    }
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = '${info.version}+${info.buildNumber}');
    } catch (_) {
      if (!mounted) return;
      setState(() => _versionFailed = true);
    }
  }

  String get _versionText {
    if (_version != null) return _version!;
    return _versionFailed ? '获取失败' : '读取中…';
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final override = widget.onCheck;
      if (override != null) {
        await override(context);
      } else {
        final info = await PackageInfo.fromPlatform();
        if (!mounted) return;
        // 整页场景没有抽屉遮挡，用默认 SnackBar 模式。
        await ManualUpdateCheck.run(context, info);
      }
    } catch (e) {
      if (!mounted) return;
      // 不静默：读不到包信息也要让用户看见原因，否则又是「点了没反应」。
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('检查更新失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.background,
      appBar: AppBar(
        title: const Text('检查更新'),
        backgroundColor: AppTokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTokens.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                ),
                child: const Icon(
                  Icons.system_update_outlined,
                  size: 36,
                  color: AppTokens.primaryBlue,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '当前版本 $_versionText',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '本应用不通过应用商店分发，更新由内置更新服务提供。\n'
                '安装包下载后会做完整性校验，校验不通过不会安装。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: AppTokens.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('update_check_button'),
                  onPressed: _checking ? null : _check,
                  child: _checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('检查更新'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
