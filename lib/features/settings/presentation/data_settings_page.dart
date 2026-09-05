import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../design_system/app_tokens.dart';
import '../../backup/local_backup_service.dart';

/// 数据设置：备份与恢复。
///
/// 逻辑整体搬自 `app_drawer.dart` 的 `_backupLocalData` / `_restoreLocalData`，
/// 一字未改地保留了两处关键行为，改动它们会造成静默的数据损失：
///
///  1. 导出后**当场回读自检**并按分类报数。只报总条数看不出「某一类整体缺失」，
///     用户会在卸载重装之后才发现备份不全，而那时已经不可逆。
///  2. 恢复成功后提示重启。内存缓存虽已失效，但已建好的页面（列表、阅读器）
///     不会自己重建，用户看到的可能还是旧画面，会以为恢复失败又导一次。
class DataSettingsPage extends StatelessWidget {
  const DataSettingsPage({super.key});

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
        ],
      ),
    );
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
        final summary = LocalBackupService.summarize(
          await file.readAsString(),
        );
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
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      final file = picked?.files.single;
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
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

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
