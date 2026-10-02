import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../design_system/app_tokens.dart';
import '../../account/data/personal_center_cache_service.dart';
import '../../backup/local_backup_service.dart';
import '../../comic/data/comic_sync_ops.dart';
import '../../comic/domain/comic_image_cache.dart';
import '../../comic/domain/comic_sync.dart';
import '../../comic/domain/comic_offline_downloader.dart';
import '../../comic/domain/comic_offline_prefs.dart';
import '../../comic/domain/comic_offline_store.dart';
import '../../comic/presentation/comic_offline_page.dart';

/// 数据设置：备份与恢复、清理缓存。
///
/// 逻辑整体搬自 `app_drawer.dart` 的 `_backupLocalData` / `_restoreLocalData`，
/// 一字未改地保留了两处关键行为，改动它们会造成静默的数据损失：
///
///  1. 导出后**当场回读自检**并按分类报数。只报总条数看不出「某一类整体缺失」，
///     用户会在卸载重装之后才发现备份不全，而那时已经不可逆。
///  2. 恢复成功后提示重启。内存缓存虽已失效，但已建好的页面（列表、阅读器）
///     不会自己重建，用户看到的可能还是旧画面，会以为恢复失败又导一次。
class DataSettingsPage extends StatefulWidget {
  const DataSettingsPage({
    super.key,
    this.cacheSizeProbe,
    this.cacheService,
    this.offlineStore,
    this.offlinePrefs,
    this.syncFactory,
  });

  /// 单测注入：离线库（不注入就走真实目录）。
  final ComicOfflineStore? offlineStore;

  /// 单测注入：离线下载偏好（仅 Wi-Fi）。
  final ComicOfflinePrefs? offlinePrefs;

  /// 单测注入：不注入就量真实的漫画图片缓存占用。
  ///
  /// 量大小要过 path_provider 的平台通道，纯 widget test 里没有插件；
  /// 真实现量不到时会**不显示数字**（而不是编一个）。
  final Future<int> Function()? cacheSizeProbe;

  /// 单测注入：不注入就走真实现（清图片/阅读器/漫画图片三类缓存）。
  final PersonalCenterCacheService? cacheService;

  /// 单测注入：跨设备同步服务（不注入就按手机上存的令牌现建；没配令牌 = null）。
  final Future<ComicSyncService?> Function()? syncFactory;

  @override
  State<DataSettingsPage> createState() => _DataSettingsPageState();
}

class _DataSettingsPageState extends State<DataSettingsPage> {
  /// 清理进行中：拦住重复点击，并给图标位一个转圈反馈。
  bool _clearing = false;

  /// 漫画图片缓存当前占用（null = 还没量出来，或这台机器量不到）。
  ///
  /// 为什么把它显示出来：它是「清理缓存」里唯一能报出确定数字的部分，
  /// 也是唯一会**悄悄涨**的部分 —— 它自己落在临时目录，不归图片缓存管理器管，
  /// 以前这一项清理完全没覆盖到它。
  int? _comicCacheBytes;

  late final ComicOfflineStore _offline =
      widget.offlineStore ?? ComicOfflineStore();
  late final ComicOfflinePrefs _offlinePrefs =
      widget.offlinePrefs ?? ComicOfflinePrefs();

  /// 跨设备同步的状态行 + 同步中（拦重复点击）。
  String _syncNote = '';
  bool _syncing = false;

  /// 离线内容占用（null = 还没量出来；量不到就不显示数字）。
  int? _offlineBytes;
  int _offlineBooks = 0;

  /// 「仅 Wi-Fi 下载」：默认 true（省流量那档）。
  bool _wifiOnly = true;

  @override
  void initState() {
    super.initState();
    _loadComicCacheSize();
    _loadOfflineUsage();
    unawaited(_loadSyncState());
  }

  /// 跨设备同步这一行：没配令牌就说清去哪儿配，配了就把"上次同步"摊开给用户看。
  Future<void> _loadSyncState() async {
    String note = '';
    try {
      final sync = await (widget.syncFactory ?? createComicSyncService)();
      if (sync == null) {
        note = '没配设备令牌（设置 → 服务器 → 设备令牌），不会同步';
      } else {
        final at = await sync.lastSyncAt();
        final msg = await sync.lastMessage();
        note = at == null
            ? '还没同步过（点一下立刻同步）'
            : '上次同步 ${_fmtTime(at)}${msg.isEmpty ? '' : ' · $msg'}';
      }
    } catch (_) {
      note = '同步状态读不出来（不影响看书）';
    }
    if (!mounted) return;
    setState(() => _syncNote = note);
  }

  /// 点一下立刻同步：结果如实回报（没配令牌 / 同步失败都要说人话）。
  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    String text;
    try {
      final sync = await (widget.syncFactory ?? createComicSyncService)();
      if (sync == null) {
        text = '没配设备令牌：设置 → 服务器 → 设备令牌';
      } else {
        final r = await sync.syncNow();
        text = r.skipped
            ? r.message
            : (r.ok ? '同步完成：${r.message}' : '同步失败：${r.message}');
      }
    } catch (e) {
      text = '同步失败：$e';
    }
    if (!mounted) return;
    setState(() => _syncing = false);
    await _loadSyncState();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
    );
  }

  /// 时间给人看的（今天只给时分，其它给月-日 时:分）。
  String _fmtTime(DateTime t) {
    final local = t.toLocal();
    final now = DateTime.now();
    String two(int v) => v < 10 ? '0$v' : '$v';
    final hm = '${two(local.hour)}:${two(local.minute)}';
    if (local.year == now.year && local.month == now.month && local.day == now.day) {
      return hm;
    }
    return '${local.month}-${local.day} $hm';
  }

  Future<void> _loadOfflineUsage() async {
    int? bytes;
    var books = 0;
    // 离线库得先预热（一次平台通道往返）。没预热就**不量**：硬量会在拿不到
    // 平台实现的环境里一直挂着，而这一行只是"顺便显示个数字"。
    await _offline.warmUp();
    if (_offline.readyRoot == null) {
      // 量不出来就不显示数字（显示一个假数字比不显示更糟）。
      if (!mounted) return;
      setState(() => _offlineBytes = null);
      return;
    }
    try {
      bytes = await _offline.totalBytes();
      books = (await _offline.books()).where((b) => b.doneCount > 0).length;
    } catch (_) {
      // 量不到就不显示数字（显示假数字比不显示更糟）。
    }
    bool wifiOnly;
    try {
      wifiOnly = await _offlinePrefs.wifiOnly();
    } catch (_) {
      wifiOnly = true;
    }
    if (!mounted) return;
    setState(() {
      _offlineBytes = bytes;
      _offlineBooks = books;
      _wifiOnly = wifiOnly;
    });
  }

  Future<void> _loadComicCacheSize() async {
    int? bytes;
    try {
      bytes = await (widget.cacheSizeProbe ?? ComicImageCache.diskUsage)();
    } catch (_) {
      // 量不出来就不显示数字（平台通道不可用/外部存储异常时是这样）：
      // 显示一个假数字比不显示更糟。
    }
    if (!mounted || bytes == null) return;
    setState(() => _comicCacheBytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.background,
      appBar: AppBar(
        title: const Text('数据设置'),
        backgroundColor: AppTokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppTokens.surface,
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              border: Border.all(color: AppTokens.divider),
            ),
            child: Column(
              children: [
                _DataTile(
                  icon: Icons.backup_outlined,
                  title: '备份本地数据',
                  subtitle: '收藏、历史、下载、书架书源与阅读进度、本地题库',
                  onTap: () => _backupLocalData(context),
                ),
                const Divider(height: 1, color: AppTokens.divider),
                _DataTile(
                  icon: Icons.settings_backup_restore_outlined,
                  title: '恢复本地数据',
                  subtitle: '重装后导入此前导出的备份',
                  onTap: () => _restoreLocalData(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AppTokens.surface,
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              border: Border.all(color: AppTokens.divider),
            ),
            child: Column(
              children: [
                _DataTile(
                  icon: Icons.download_for_offline_outlined,
                  title: '离线下载',
                  subtitle: _offlineBytes == null
                      ? '管理下载到本机的漫画（断网也能读）'
                      : _offlineBooks == 0
                      ? '还没下载过漫画；在漫画详情页点「下载」'
                      : '$_offlineBooks 本书 · 占用 ${_fmtBytes(_offlineBytes!)}',
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ComicOfflinePage(store: _offline, downloader: null),
                      ),
                    );
                    // 回来重新量一次（用户可能刚在里面删了东西）。
                    await _loadOfflineUsage();
                  },
                ),
                const Divider(height: 1, color: AppTokens.divider),
                _DataTile(
                  icon: Icons.sync_outlined,
                  title: '跨设备同步',
                  subtitle: _syncNote.isEmpty ? '收藏与阅读进度在几台设备间对齐' : _syncNote,
                  busy: _syncing,
                  onTap: _syncing ? null : () => unawaited(_syncNow()),
                ),
                const Divider(height: 1, color: AppTokens.divider),
                // 外面那层 Container 有底色：SwitchListTile 必须有自己的 Material，
                // 否则 Flutter 会断言"背景与墨水效果可能看不见"（测试里直接判失败）。
                Material(
                  color: Colors.transparent,
                  child: SwitchListTile(
                    dense: true,
                    value: _wifiOnly,
                    onChanged: (v) async {
                      setState(() => _wifiOnly = v);
                      await _offlinePrefs.setWifiOnly(v);
                      if (!v) {
                        // 从"仅 Wi-Fi"改成"不限网络"：正在等 Wi-Fi 的任务该自己接着下，
                        // 否则用户改了设置还得再去点一次「这次用流量」（同一类"点了没反应"）。
                        ComicOfflineDownloader.shared().allowNetworkOnce();
                      }
                    },
                    title: const Text('只在 Wi-Fi 下下载'),
                    subtitle: const Text('默认开：整本漫画可能有几个 GB'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 单独一组：上面两项动的是用户数据本身，这一项只是释放空间。
          // 混在一起容易让人以为清缓存也会动到备份内容。
          Container(
            decoration: BoxDecoration(
              color: AppTokens.surface,
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              border: Border.all(color: AppTokens.divider),
            ),
            child: _DataTile(
              icon: Icons.cleaning_services_outlined,
              title: '清理缓存',
              subtitle: _comicCacheBytes == null
                  ? '释放图片与阅读器临时缓存占用的空间'
                  : '释放图片与阅读器临时缓存占用的空间'
                        '（其中在线漫画图片 ${_fmtBytes(_comicCacheBytes!)}）',
              busy: _clearing,
              onTap: _clearing ? null : _clearCache,
            ),
          ),
        ],
      ),
    );
  }

  /// 清理可再生缓存。
  ///
  /// 实现搬自 `personal_center_page.dart` 的 `_clearCache`，行为一字未改：
  /// 先弹确认框讲清边界。用户最怕的是「清缓存把我的书和题库清了」，
  /// 所以文案必须写明不动登录信息、离线书籍和题库。
  /// 不收 context 参数：本方法跨 await 用 State.context，并以 State.mounted
  /// 守卫。传外部 context 再判 State.mounted 是两个不相关的生命周期，
  /// analyzer 会（正确地）报 use_build_context_synchronously。
  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清理缓存'),
        content: const Text('仅清除图片（含在线漫画图片）和阅读器临时缓存，不会删除登录信息、离线书籍或题库数据。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clearing = true);
    try {
      final freed = await (widget.cacheService ?? PersonalCenterCacheService())
          .clearRegenerableCaches();
      // 报出释放了多少：用户按这一下就是想腾空间，一个「已清理」看不出到底有没有用。
      // freed 只统计漫画图片那部分 —— 另外两类（图片缓存管理器、阅读器内存）给不出
      // 「释放了多少」，不编数字。
      final detail = freed > 0
          ? '（漫画图片释放 ${_fmtBytes(freed)}）'
          : '（漫画图片本来没有占用）';
      if (mounted) _showSnack(context, '缓存已清理$detail');
      await _loadComicCacheSize();
    } catch (error) {
      if (mounted) _showSnack(context, '清理缓存失败：$error');
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  /// 字节数说人话（设置页只有一个地方用，不值得抽公共工具）。
  static String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final digits = value >= 100 ? 0 : (value >= 10 ? 1 : 2);
    return '${value.toStringAsFixed(digits)} ${units[unit]}';
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _backupLocalData(BuildContext context) async {
    _showSnack(context, '正在整理本地数据…');
    try {
      final file = await LocalBackupService.writeBackupToTemporaryFile();
      String summaryText;
      try {
        final summary = LocalBackupService.summarize(await file.readAsString());
        summaryText = summary.describe();
      } catch (_) {
        summaryText = '（自检未通过，请确认备份文件是否完整）';
      }
      if (!context.mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: 'Box 本地数据备份',
          text: '本次备份内容：$summaryText\n请妥善保存此备份文件；重装后可通过“恢复本地数据”导入。',
        ),
      );
      if (context.mounted) _showSnack(context, '备份内容：$summaryText');
    } catch (_) {
      if (context.mounted) _showSnack(context, '备份失败，请稍后重试');
    }
  }

  Future<void> _restoreLocalData(BuildContext context) async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      final bytes = await file?.readAsBytes();
      if (bytes == null || bytes.isEmpty || !context.mounted) return;
      final count = await LocalBackupService.restoreBackupBytes(bytes);
      if (context.mounted) {
        _showSnack(context, '已恢复 $count 条本地记录，建议重启应用以刷新界面');
      }
    } on FormatException {
      if (context.mounted) _showSnack(context, '不是有效的 Box 本地数据备份文件');
    } catch (_) {
      if (context.mounted) _showSnack(context, '恢复失败，原数据未被清空');
    }
  }
}

class _DataTile extends StatelessWidget {
  const _DataTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// 置空即为停用（例如清理进行中）。
  final VoidCallback? onTap;

  /// 进行中：右侧箭头换成转圈，告诉用户点击已生效。
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppTokens.primaryBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (busy)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppTokens.textTertiary,
              ),
          ],
        ),
      ),
    );
  }
}
