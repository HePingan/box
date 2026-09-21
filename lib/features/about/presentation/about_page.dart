import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../app/app_routes.dart';
import '../../../design_system/app_tokens.dart';
import '../../../design_system/settings_list.dart';
import '../data/about_content.dart';

/// 关于页。
///
/// 替代原来抽屉里的 `_showAboutDialog` 弹窗。做成设置式整页而不是弹窗，
/// 是因为需求要装的东西（版本信息、软件介绍、使用文档、推荐教程、历史更新、
/// 用户协议、隐私政策）在一个 AlertDialog 里放不下，硬塞会变成需要滚动的
/// 小窗口，比整页更难用。
///
/// 版本号获取用 [PackageInfo.fromPlatform]。在 widget test 里它**既不抛异常也
/// 不返回**，而是一直挂住（实测 4 分钟没结束）——想测失败分支必须自己 mock
/// `dev.fluttercommunity.plus/package_info` 通道让它抛。所以这里：
///  - 允许注入 [versionOverride] 供测试用；
///  - 拿不到时显示"获取失败"而不是空白，让问题看得见。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key, this.versionOverride});

  /// 仅测试注入。生产走 PackageInfo。
  final String? versionOverride;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String? _version;
  bool _versionFailed = false;

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
      // 不静默：显示"获取失败"，否则报障时分不清"没显示"和"没读到"。
      if (!mounted) return;
      setState(() => _versionFailed = true);
    }
  }

  String get _versionText {
    if (_version != null) return _version!;
    return _versionFailed ? '获取失败' : '读取中…';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.background,
      appBar: AppBar(
        title: const Text('关于'),
        backgroundColor: AppTokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _buildHeader(),
          SettingsSection(
            title: '版本信息',
            children: [
              SettingsTile(
                icon: Icons.info_outline_rounded,
                title: '当前版本',
                subtitle: null,
                onTap: null,
                trailingText: _versionText,
              ),
              SettingsTile(
                icon: Icons.system_update_outlined,
                title: '检查更新',
                subtitle: '从官方更新服务器获取最新版本',
                onTap: () =>
                    Navigator.of(context).pushNamed(AppRoutes.updateCheck),
              ),
              SettingsTile(
                icon: Icons.history_rounded,
                title: '更新内容',
                subtitle: '查看本版与历史版本的更新说明',
                onTap: () =>
                    Navigator.of(context).pushNamed(AppRoutes.updateHistory),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsSection(
            title: '帮助与说明',
            children: [
              SettingsTile(
                icon: Icons.apps_rounded,
                title: '软件介绍',
                subtitle: '这个应用能做什么',
                onTap: () => Navigator.of(context)
                    .pushNamed(AppRoutes.aboutIntroduction),
              ),
              SettingsTile(
                icon: Icons.menu_book_rounded,
                title: '使用文档',
                subtitle: '各功能怎么用',
                onTap: () =>
                    Navigator.of(context).pushNamed(AppRoutes.aboutGuide),
              ),
              SettingsTile(
                icon: Icons.school_outlined,
                title: '推荐教程',
                subtitle: '上手路线与常见问题',
                onTap: () =>
                    Navigator.of(context).pushNamed(AppRoutes.aboutTutorial),
              ),
              SettingsTile(
                icon: Icons.bug_report_outlined,
                title: '调试日志',
                subtitle: '出问题时复制日志发给开发者',
                onTap: () => Navigator.of(context).pushNamed(AppRoutes.debugLog),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsSection(
            title: '法律条款',
            children: [
              SettingsTile(
                icon: Icons.description_outlined,
                title: '用户协议',
                subtitle: '你已同意的使用条款',
                onTap: () => Navigator.of(context)
                    .pushNamed(AppRoutes.legalUserAgreement),
              ),
              SettingsTile(
                icon: Icons.privacy_tip_outlined,
                title: '隐私政策',
                subtitle: '应用如何处理你的数据',
                onTap: () => Navigator.of(context)
                    .pushNamed(AppRoutes.legalPrivacyPolicy),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Center(
            child: Text(
              AboutContent.disclaimerShort,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.6,
                color: AppTokens.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      alignment: Alignment.center,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: AppTokens.blueGradient,
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            ),
            child: const Icon(
              Icons.all_inbox_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            AboutContent.appName,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            AboutContent.tagline,
            style: TextStyle(
              fontSize: 12,
              color: AppTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
