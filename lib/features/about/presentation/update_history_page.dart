import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../design_system/app_tokens.dart';
import '../data/update_history_models.dart';
import '../data/update_history_repository.dart';

/// 历史更新说明页。
///
/// 降级处理是这个页面的重点，因为它依赖网络：
///  - 加载中：转圈；
///  - 失败：显示**具体原因**（网络/服务端/解析）+ 重试按钮，而不是一句"加载失败"；
///  - 空列表：说明"服务端暂无记录"，跟失败区分开 —— 两者用户该做的事不一样。
///
/// 刻意不缓存到本地：更新说明不是离线场景的必需信息，加一层缓存反而会出现
/// "显示的是三个月前的旧列表但用户以为是最新"的问题。
class UpdateHistoryPage extends StatefulWidget {
  const UpdateHistoryPage({
    super.key,
    this.repository,
    this.packageNameOverride,
  });

  /// 供测试注入。
  final UpdateHistoryRepository? repository;

  /// 仅测试注入：widget test 里 [PackageInfo.fromPlatform] **既不抛也不返回**
  /// （实测会一直挂住），不注入的话测试会超时而不是走失败分支。
  final String? packageNameOverride;

  @override
  State<UpdateHistoryPage> createState() => _UpdateHistoryPageState();
}

class _UpdateHistoryPageState extends State<UpdateHistoryPage> {
  late final UpdateHistoryRepository _repo =
      widget.repository ?? UpdateHistoryRepository();

  UpdateHistoryResult? _result;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // 包名必须跟着请求走：服务端按 package_name 过滤，写死常量会在改包名
    // （项目做过一次 applicationId 重命名）之后静默返回空列表。
    String? pkg = widget.packageNameOverride;
    if (pkg == null) {
      try {
        pkg = (await PackageInfo.fromPlatform()).packageName;
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _result = const UpdateHistoryResult.failure('读取应用包信息失败');
          _loading = false;
        });
        return;
      }
    }
    final result = await _repo.fetch(packageName: pkg);
    if (!mounted) return;
    setState(() {
      _result = result;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.background,
      appBar: AppBar(
        title: const Text('更新内容'),
        backgroundColor: AppTokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        key: ValueKey('update_history_loading'),
        child: CircularProgressIndicator(),
      );
    }

    final result = _result;
    if (result == null || result.isFailure) {
      return _buildError(result?.errorMessage ?? '未知错误');
    }

    if (result.entries.isEmpty) {
      return _buildEmpty();
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        key: const ValueKey('update_history_list'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: result.entries.length,
        itemBuilder: (_, i) => _HistoryCard(entry: result.entries[i]),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      key: const ValueKey('update_history_empty'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.inbox_outlined,
              size: 40,
              color: AppTokens.textTertiary,
            ),
            const SizedBox(height: 12),
            const Text(
              '服务端暂无历史更新记录',
              style: TextStyle(fontSize: 14, color: AppTokens.textSecondary),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _load, child: const Text('重新加载')),
          ],
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      key: const ValueKey('update_history_error'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: AppTokens.textTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.6,
                color: AppTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              key: const ValueKey('update_history_retry'),
              onPressed: _load,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry});

  final UpdateHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        border: Border.all(color: AppTokens.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTokens.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppTokens.radiusChip),
                ),
                child: Text(
                  'v${entry.versionName}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.primaryBlue,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (entry.publishedDateLabel != null)
                Text(
                  entry.publishedDateLabel!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTokens.textTertiary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            entry.displayTitle,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTokens.textPrimary,
            ),
          ),
          // changelog 是逐行的 List<String>：服务端存的是多行文本，
          // 拆行后才能渲染成条目，直接 join 会丢掉换行变成一坨。
          if (entry.changelog.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...entry.changelog.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  line,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.7,
                    color: AppTokens.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
