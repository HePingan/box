import 'package:flutter/material.dart';

import '../../../design_system/app_tokens.dart';
import '../../core/novel_cache_manager.dart';

/// 缓存管理弹窗
///
/// 显示缓存统计并提供清除选项。
class NovelCacheDialog extends StatefulWidget {
  const NovelCacheDialog({super.key, required this.cacheManager});

  final NovelCacheManager cacheManager;

  @override
  State<NovelCacheDialog> createState() => _NovelCacheDialogState();
}

class _NovelCacheDialogState extends State<NovelCacheDialog> {
  NovelCacheStats? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await widget.cacheManager.getStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('清除缓存'),
        content: const Text('确定清除所有小说缓存吗？\n这将清除搜索结果、详情页和章节内容的本地缓存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        await widget.cacheManager.clear();
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('缓存已清除'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('清除失败: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '缓存管理',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_stats != null) ...[
              _buildStatRow('缓存文件', '${_stats!.totalKeys} 个'),
              _buildStatRow('占用空间', _stats!.formattedSize),
              if (_stats!.byNamespace.isNotEmpty)
                _buildStatRow('命名空间', _stats!.byNamespace.keys.join(', ')),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _handleClear,
                  icon: const Icon(Icons.delete_sweep_rounded),
                  label: const Text('清除全部缓存'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTokens.danger,
                  ),
                ),
              ),
            ] else ...[
              const Text('无法获取缓存信息'),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTokens.textSecondary,
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
