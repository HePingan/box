import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../app/app_routes.dart';
import '../../../config/app_config.dart';
import '../../../design_system/app_tokens.dart';
import '../../../design_system/settings_list.dart';
import '../../../update/update_last_check_store.dart';
import '../data/about_content.dart';
import '../data/legal_documents.dart';

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

  /// 真实包名（`top.hpa888.box`）。「更新来源与校验」里要显示它 ——
  /// 用户核对安装包时，包名比版本号更能说明「装的是不是这个应用」。
  /// 取不到就显示 `—`，不猜。
  String? _packageName;

  /// 上次更新检查的结论（现读现算，没有就显示原来的说明句）。
  UpdateLastCheck? _lastCheck;

  @override
  void initState() {
    super.initState();
    if (widget.versionOverride != null) {
      _version = widget.versionOverride;
    } else {
      _loadVersion();
    }
    _loadLastCheck();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = '${info.version}+${info.buildNumber}';
        _packageName = info.packageName;
      });
    } catch (_) {
      // 不静默：显示"获取失败"，否则报障时分不清"没显示"和"没读到"。
      if (!mounted) return;
      setState(() => _versionFailed = true);
    }
  }

  /// 读上次检查记录。读不到就保持 null（副标题回落到说明句），
  /// 不写「上次检查：--」这种占位 —— 看着像坏了。
  Future<void> _loadLastCheck() async {
    final last = await UpdateLastCheckStore.read();
    if (!mounted || last == null) return;
    setState(() => _lastCheck = last);
  }

  /// 「检查更新」的副标题：把上次检查的时间与结论摊在面上。
  ///
  /// 说法直接复用 [UpdateLastCheck.describe]（与检查当下的措辞逐字一致），
  /// 所以不会出现「关于页说已是最新、抽屉说有新版本」这种两套话。
  String get _updateCheckSubtitle {
    final last = _lastCheck;
    if (last == null) return '从官方更新服务器获取最新版本';
    return '上次检查 ${last.ageText(DateTime.now())} · ${last.describe()}';
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
                subtitle: _updateCheckSubtitle,
                // 检查完回来刷新副标题：用户刚点过，这里必须立刻反映结果。
                onTap: () => Navigator.of(context)
                    .pushNamed(AppRoutes.updateCheck)
                    .then((_) {
                      if (mounted) _loadLastCheck();
                    }),
              ),
              SettingsTile(
                icon: Icons.history_rounded,
                title: '更新内容',
                subtitle: '查看本版与历史版本的更新说明',
                onTap: () =>
                    Navigator.of(context).pushNamed(AppRoutes.updateHistory),
              ),
              SettingsTile(
                icon: Icons.verified_user_outlined,
                title: '更新来源与校验',
                subtitle: '更新从哪来、安装包怎么验',
                onTap: () => _showUpdateSource(context),
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
                onTap: () => Navigator.of(
                  context,
                ).pushNamed(AppRoutes.aboutIntroduction),
              ),
              SettingsTile(
                icon: Icons.shield_outlined,
                title: '权限说明',
                subtitle: '每项权限用来做什么、什么时候用到、怎么关',
                onTap: () =>
                    Navigator.of(context).pushNamed(AppRoutes.aboutPermissions),
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
                icon: Icons.workspace_premium_outlined,
                title: '开源许可与致谢',
                subtitle: AboutContent.licenseNote,
                onTap: () => _showLicenses(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsSection(
            title: '反馈与联系',
            children: [
              SettingsTile(
                icon: Icons.feedback_outlined,
                title: '问题反馈',
                subtitle: '在 GitHub Issues 上报问题、提建议（点击复制地址）',
                onTap: () => _copy(context, AboutContent.issuesUrl, '反馈地址已复制'),
              ),
              SettingsTile(
                icon: Icons.bug_report_outlined,
                title: '调试日志',
                subtitle: '出问题时复制日志发给开发者（报障的主要抓手）',
                onTap: () =>
                    Navigator.of(context).pushNamed(AppRoutes.debugLog),
              ),
              SettingsTile(
                icon: Icons.fact_check_outlined,
                title: '应用自检',
                subtitle: '出问题时先跑一遍：片源、线路、更新通道、网络',
                onTap: () => Navigator.of(context).pushNamed(AppRoutes.selfCheck),
              ),
              SettingsTile(
                icon: Icons.code_rounded,
                title: '项目源码',
                subtitle: 'GitHub 仓库（点击复制地址）',
                onTap: () => _copy(context, AboutContent.repoUrl, '仓库地址已复制'),
              ),
              SettingsTile(
                icon: Icons.mail_outline_rounded,
                title: '联系邮箱',
                subtitle: '$kLegalContact（点击复制）',
                onTap: () => _copy(context, kLegalContact, '邮箱已复制'),
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
                onTap: () => Navigator.of(
                  context,
                ).pushNamed(AppRoutes.legalUserAgreement),
              ),
              SettingsTile(
                icon: Icons.privacy_tip_outlined,
                title: '隐私政策',
                subtitle: '应用如何处理你的数据',
                onTap: () => Navigator.of(
                  context,
                ).pushNamed(AppRoutes.legalPrivacyPolicy),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '以上条款生效日期：$kLegalEffectiveDate',
              style: TextStyle(
                fontSize: 11,
                height: 1.6,
                color: AppTokens.textTertiary,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              onTap: () => _showDataLocations(context),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Column(
                  children: [
                    Text(
                      AboutContent.localDataNote,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.6,
                        color: AppTokens.textTertiary,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '点击看：数据都在哪 · 怎么清',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.6,
                        color: AppTokens.primaryBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
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

  /// 复制并**明确反馈**：静默复制等于没做，用户不知道成不成。
  void _copy(BuildContext context, String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// 更新来源与校验。
  ///
  /// 每一项都**从 [AppConfig] 现取**，不手抄常量 —— 通道、域名、算法改了，
  /// 这张表跟着改；手抄的说明迟早会变成一处没人维护的过期承诺。
  Future<void> _showUpdateSource(BuildContext context) async {
    final algorithm = AppConfig.updateSignatureAlgorithm
        .replaceAll('_', '-')
        .toUpperCase();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('更新来源与校验'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _sourceRow('更新通道', AppConfig.appChannel),
              _sourceRow('检查地址', AppConfig.updateCheckUrl),
              _sourceRow('下载域名', AppConfig.updateDownloadAllowedHosts),
              _sourceRow('清单校验', '$algorithm 签名 + SHA-256 完整性'),
              _sourceRow('安装包名', _packageName ?? '—'),
              _sourceRow('当前版本', _versionText),
              const SizedBox(height: 12),
              const Text(
                '应用只从上面的域名下载更新；清单签名或 SHA-256 校验不通过时'
                '不会安装 —— 宁可不更新，也不装来源不明的安装包。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: AppTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Widget _sourceRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppTokens.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: AppTokens.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 开源许可与致谢：用 Flutter 自带的 [showLicensePage]，它自动汇总 Flutter
  /// 与全部依赖（含间接依赖）的许可 —— 手工维护一张清单必然会过期。
  void _showLicenses(BuildContext context) {
    showLicensePage(
      context: context,
      applicationName: AboutContent.appName,
      applicationVersion: _version,
      applicationIcon: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          Icons.all_inbox_rounded,
          size: 40,
          color: AppTokens.blueGradient.colors.first,
        ),
      ),
    );
  }

  /// 页脚那句「数据在哪」点开的明细。
  ///
  /// 每一行都对着代码事实写：本地持久化都落在应用私有存储（Hive/SharedPreferences/
  /// 应用目录），清除入口写的是应用里**真有的**那个入口 —— 比如「清理缓存」只清图片
  /// 与阅读器临时缓存、不删登录信息与题库（这条写在它自己的确认弹窗里），所以这里
  /// 必须说清差别，不能让用户以为点一下就把书架清空了。
  Future<void> _showDataLocations(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('你的数据都在哪'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _DataRow(
                category: '收藏 · 播放历史 · 播放进度',
                where: '只在这台手机上',
                how: '在各列表里删除；「清理缓存」不会动它们',
              ),
              _DataRow(
                category: '书架 · 阅读进度 · 书源',
                where: '只在这台手机上',
                how: '书架里长按删除；书源在「书源管理」里删',
              ),
              _DataRow(
                category: '题库 · 错题',
                where: '只在这台手机上',
                how: '题库页里删除',
              ),
              _DataRow(
                category: '下载内容 · 图片缓存',
                where: '只在这台手机上',
                how: '设置 → 数据设置 → 清理缓存（只清图片与阅读器临时缓存）',
              ),
              _DataRow(
                category: '调试日志',
                where: '只在这台手机上',
                how: '调试日志页里清空',
              ),
              _DataRow(
                category: '备份文件',
                where: '你导出时选的目录',
                how: '在文件管理器里自己删',
              ),
              _DataRow(
                category: '账号与云同步（登录后才会有）',
                where: '服务端',
                how: '设置里停止同步；彻底删除请邮件联系',
              ),
              SizedBox(height: 4),
              Text(
                '应用不参与系统的备份与换机迁移（清单里 allowBackup=false），'
                '所以上面这些数据不会随系统备份被带走 —— 换机请用「备份与恢复」导出。'
                '详细说明见《隐私政策》第三条。',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.6,
                  color: AppTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).pushNamed(AppRoutes.legalPrivacyPolicy);
            },
            child: const Text('看《隐私政策》'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
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
            style: TextStyle(fontSize: 12, color: AppTokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 「你的数据都在哪」弹窗里的一行：类别 / 在哪 / 怎么清。
class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.category,
    required this.where,
    required this.how,
  });

  final String category;
  final String where;
  final String how;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            category,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '在哪：$where',
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.5,
              color: AppTokens.textSecondary,
            ),
          ),
          Text(
            '怎么清：$how',
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.5,
              color: AppTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
