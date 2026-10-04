import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../design_system/app_tokens.dart';
import '../../../update/manual_update_check.dart';
import '../../../video/controller/video_controller.dart';
import '../../../video/models/video_source.dart';
import '../../../video/services/line_reachability_store.dart';
import '../../../video/video_module.dart';
import '../../extensions/plugins/net_diag/presentation/net_diag_page.dart';

/// 「应用自检」——一页把散在各处的"哪儿坏了"收拢起来。
///
/// 为什么要有它（2026-10-03）：
/// - 扩展页原来那个「诊断」入口是拿一条**假书源**（`诊断模式`、空 url）去开
///   书源诊断页，等于诊断一条不存在的书源；那排快捷入口撤掉后，"哪儿坏了"
///   在 App 里彻底没有落点。
/// - 那四个信息本来就有，但各在一个角落：片源健康只在影视流程里（① 的自动隐藏）、
///   线路记忆只在详情页的线路 chip 上（②）、更新通道在关于页、网络诊断在插件列表里。
///
/// 三条硬规矩：
/// 1. **不编数字**。目录数取 `VideoController.sources`，隐藏数取
///    `VideoModule` 的可见性记录（与影视页选源面板同一份真相），线路数取
///    `LineReachabilityStore`；取不到就如实写"还没加载"，不写 0 冒充。
/// 2. **只读为主**。除用户亲手点的两个按钮（恢复被隐藏的源 / 清空线路记忆）
///    之外不改任何状态。
/// 3. **每个数字旁边说清它是谁**：片源健康跟选源面板同源、线路记忆 TTL 6 小时，
///    避免下一个"两套真相"。
class SelfCheckPage extends StatefulWidget {
  const SelfCheckPage({super.key});

  @override
  State<SelfCheckPage> createState() => _SelfCheckPageState();
}

class _SelfCheckPageState extends State<SelfCheckPage> {
  bool _loading = true;
  String _versionText = '读取中…';
  List<VideoSource> _sources = const [];
  List<VideoSource> _hidden = const [];
  Map<String, LineReachabilityRecord> _lines = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    // 先把 controller 取出来：下面有异步等待，跨过去再用 context 是不安全的。
    // （措辞里不要出现那个关键字：本仓 mounted 护栏测试是扫源码的，注释也会被骗到。）
    final controller = context.read<VideoController>();
    setState(() => _loading = true);

    // 线路记忆 + 可见性记录都是本地缓存，先确保读过盘再报数。
    await LineReachabilityStore.ensureLoaded();
    final sources = List<VideoSource>.from(controller.sources);
    final hidden = <VideoSource>[];
    for (final source in sources) {
      if (VideoModule.getVisibilityRecord(source).autoHidden) {
        hidden.add(source);
      }
    }

    // await 之后要重新确认页面还在：用户可能在读盘这段时间退出了这一页。
    if (!mounted) return;
    setState(() {
      _sources = sources;
      _hidden = hidden;
      _lines = LineReachabilityStore.records;
      _loading = false;
    });

    // 版本号走插件通道，慢（测试环境里干脆没有）——单独补，
    // 不让它挡住上面那些本地事实的显示。
    unawaited(_loadVersion());
  }

  Future<void> _loadVersion() async {
    var versionText = '读不到（不影响使用）';
    try {
      final info = await PackageInfo.fromPlatform();
      versionText = '${info.version} (${info.buildNumber})';
    } catch (_) {
      // 测试环境没有插件通道：保持如实说明，别编一个版本号。
    }
    if (!mounted) return;
    setState(() => _versionText = versionText);
  }

  /// 冷启动直接进这里时目录多半还没加载：跑一次与影视页同一条加载路径。
  Future<void> _loadCatalog() async {
    final controller = context.read<VideoController>();
    await VideoModule.ensureCatalogReady(controller);
    await _refresh();
  }

  Future<void> _restoreAllHidden() async {
    final count = _hidden.length;
    if (count == 0) return;
    for (final source in _hidden) {
      // 复位要把 failCount 一起归零，否则仍按"连续失败≥3"判不可用 —— 等于没恢复。
      await VideoModule.setSourceAutoHidden(
        source,
        false,
        reason: '用户在应用自检里恢复',
        failCount: 0,
      );
    }
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已恢复 $count 个被自动隐藏的片源')));
  }

  Future<void> _clearLines() async {
    final count = _lines.length;
    if (count == 0) return;
    await LineReachabilityStore.clear();
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已清空 $count 条线路记忆')));
  }

  Future<void> _checkUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      await ManualUpdateCheck.run(context, info, resultInDialog: true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('这个环境读不到应用版本，无法检查更新')));
    }
  }

  void _openNetDiag() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NetDiagPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.background,
      appBar: AppBar(
        title: const Text('应用自检'),
        backgroundColor: AppTokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(
            '这里只报实测到的状态；除了你自己点的按钮，不改任何东西。',
            style: TextStyle(
              color: AppTokens.textSecondary,
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          _section(
            icon: Icons.live_tv_rounded,
            color: AppTokens.primaryBlue,
            title: '片源目录与健康',
            // 与影视页「选源面板」读同一份可见性记录，免得出现两套真相。
            note: '与影视页选源面板同一份记录',
            rows: [
              _Row(
                label: '已加载片源',
                value: _loading
                    ? '读取中…'
                    : _sources.isEmpty
                    ? '还没加载'
                    : '${_sources.length} 个',
              ),
              _Row(
                label: '被自动隐藏',
                value: _loading
                    ? '读取中…'
                    : _hidden.isEmpty
                    ? '无'
                    : '${_hidden.length} 个 · ${_hiddenNames()}',
              ),
            ],
            actions: [
              _Action(
                label: _sources.isEmpty ? '立即加载片源' : '重新读一次',
                onPressed: _loading ? null : () => unawaited(_loadCatalog()),
              ),
              _Action(
                label: '恢复全部被隐藏的源',
                primary: true,
                onPressed: _loading || _hidden.isEmpty
                    ? null
                    : () => unawaited(_restoreAllHidden()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _section(
            icon: Icons.alt_route_rounded,
            color: AppTokens.emerald,
            title: '线路取流记忆',
            note: '按「源 + 线路名」记 6 小时，起播成功即清',
            rows: [
              _Row(
                label: '记住的线路',
                value: _loading ? '读取中…' : '${_lines.length} 条',
              ),
              _Row(
                label: '最近取不到流',
                value: _loading ? '读取中…' : '${_unreachableLineCount()} 条',
              ),
            ],
            actions: [
              _Action(
                label: '清空线路记忆',
                onPressed: _loading || _lines.isEmpty
                    ? null
                    : () => unawaited(_clearLines()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _section(
            icon: Icons.system_update_alt_rounded,
            color: AppTokens.violet,
            title: '更新通道',
            note: '只连我们自己的更新服务',
            rows: [
              _Row(label: '当前版本', value: _versionText),
              const _Row(label: '更新地址', value: AppConfig.updateCheckUrl),
            ],
            actions: [
              _Action(
                label: '检查更新',
                primary: true,
                onPressed: _loading ? null : () => unawaited(_checkUpdate()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _section(
            icon: Icons.network_check_rounded,
            color: AppTokens.rose,
            title: '网络诊断',
            note: 'DNS / TCP / TLS / HTTP 四项直连检测，结论可复制',
            rows: const [],
            actions: [_Action(label: '打开网络诊断', onPressed: _openNetDiag)],
          ),
        ],
      ),
    );
  }

  int _unreachableLineCount() =>
      _lines.values.where((record) => record.isRecentlyUnreachable()).length;

  String _hiddenNames() {
    const limit = 3;
    final names = _hidden.map((s) => s.name).take(limit).join('、');
    return _hidden.length > limit ? '$names…' : names;
  }

  Widget _section({
    required IconData icon,
    required Color color,
    required String title,
    required String note,
    required List<_Row> rows,
    required List<_Action> actions,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: AppTokens.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: AppTokens.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            note,
            style: TextStyle(
              color: AppTokens.textSecondary,
              fontSize: 11.5,
            ),
          ),
          if (rows.isNotEmpty) const SizedBox(height: 10),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 88,
                    child: Text(
                      row.label,
                      style: TextStyle(
                        color: AppTokens.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.value,
                      style: TextStyle(
                        color: AppTokens.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final action in actions)
                FilledButton(
                  onPressed: action.onPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: action.primary
                        ? color
                        : AppTokens.background,
                    foregroundColor: action.primary
                        ? Colors.white
                        : AppTokens.textPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: const Size(0, 36),
                  ),
                  child: Text(
                    action.label,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Row {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;
}

class _Action {
  const _Action({
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
}
