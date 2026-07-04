import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import '../../../../design_system/app_tokens.dart';
import '../../../../video_module.dart';
import '../../domain/admin_resource.dart';
import '../../domain/admin_resource_provider.dart';

/// 视频源资源提供者
///
/// 显示当前已加载的视频源（采集站）信息。
/// 视频源通过 [VideoModule.configureLicensedCatalogSource] 配置，
/// 由 [VideoController] 动态加载。
class VideoSourceResourceProvider implements ResourceProvider<ResourceData> {
  @override
  AdminResourceType get resourceType => AdminResourceType.videoSource;

  @override
  Future<List<ResourceData>> fetchAll(String? serverUrl, String? token) async {
    return [];
  }

  @override
  Future<ResourceData> create(
    String? serverUrl,
    String? token,
    Map<String, dynamic> data,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<ResourceData> update(
    String? serverUrl,
    String? token,
    String id,
    Map<String, dynamic> data,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String? serverUrl, String? token, String id) {
    throw UnimplementedError();
  }

  @override
  Widget buildListPage({
    required BuildContext context,
    String? serverUrl,
    String? token,
  }) {
    return const _VideoSourceTab();
  }
}

class _VideoSourceTab extends StatefulWidget {
  const _VideoSourceTab();

  @override
  State<_VideoSourceTab> createState() => _VideoSourceTabState();
}

class _VideoSourceTabState extends State<_VideoSourceTab> {
  // 展开详情跟踪
  final Set<String> _expandedSources = {};

  // 测试连通性状态
  final Map<String, bool> _testingSources = {};
  final Map<String, String> _testResults = {};

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VideoController>();
    final sources = controller.sources;
    final currentSource = controller.currentSource;

    return RefreshIndicator(
      onRefresh: () => _refreshSources(controller),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          // 采集站配置信息
          _buildConfigCard(),
          const SizedBox(height: 16),

          // 当前片源
          if (currentSource != null) ...[
            _buildCurrentSourceCard(currentSource),
            const SizedBox(height: 16),
          ],

          // 可用片源列表
          _buildSectionHeader(
            '可用片源（${sources.length}）',
            trailing: TextButton.icon(
              onPressed: () => _refreshSources(controller),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('刷新'),
            ),
          ),
          const SizedBox(height: 8),
          if (sources.isEmpty)
            _buildEmptyState()
          else
            ...sources.map((s) => _buildSourceCard(s, s.id == currentSource?.id, controller)),
        ],
      ),
    );
  }

  Future<void> _refreshSources(VideoController controller) async {
    final catalogUrl = await VideoModule.resolveWorkingCatalogUrl();
    if (catalogUrl == null) {
      _showSnack('未配置采集站');
      return;
    }
    await controller.initSources(catalogUrl);
    _showSnack('刷新完成');
  }

  Future<void> _testSource(String sourceId, String url) async {
    setState(() {
      _testingSources[sourceId] = true;
      _testResults.remove(sourceId);
    });
    try {
      final start = DateTime.now();
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      if (mounted) {
        setState(() {
          _testResults[sourceId] = '${response.statusCode} (${elapsed}ms)';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testResults[sourceId] = '不可达 ($e)';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _testingSources[sourceId] = false);
      }
    }
  }

  Future<void> _toggleSourceVisibility(VideoSource source) async {
    final currentlyHidden = VideoModule.isSourceManuallyHidden(source);
    await VideoModule.setSourceManualHidden(source, !currentlyHidden);
    if (mounted) {
      setState(() {});
      _showSnack(currentlyHidden ? '已显示：${source.name}' : '已隐藏：${source.name}');
    }
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _buildConfigCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.deepPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.live_tv_rounded, color: Colors.deepPurple),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '采集站片源',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '片源通过采集站 API 动态加载',
                    style: TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentSourceCard(VideoSource source) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEEF2FF), Color(0xFFE0E7FF)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.indigo.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.play_circle_fill_rounded, color: Colors.indigo, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '当前正在使用',
                  style: TextStyle(fontSize: 11, color: Colors.indigo),
                ),
                const SizedBox(height: 2),
                Text(
                  source.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.indigo,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {Widget? trailing}) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF101828),
          ),
        ),
        const Spacer(),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.deepPurple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.videocam_off_rounded, size: 32, color: Colors.deepPurple),
            ),
            const SizedBox(height: 16),
            const Text(
              '暂无可用片源',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '片源通过采集站自动加载',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => _refreshSources(context.read<VideoController>()),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('加载片源'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceCard(VideoSource source, bool isActive, VideoController controller) {
    final isExpanded = _expandedSources.contains(source.id);
    final manualHidden = VideoModule.isSourceManuallyHidden(source);
    final isTesting = _testingSources[source.id] ?? false;
    final testResult = _testResults[source.id];

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isActive ? Colors.deepPurple : const Color(0xFFE6EAF2),
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedSources.remove(source.id);
            } else {
              _expandedSources.add(source.id);
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 顶行：状态 + 名称 + 操作 ──
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: source.isAvailable ? Colors.green : Colors.grey.shade300,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          source.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        if (!source.isAvailable && source.hiddenReason.isNotEmpty)
                          Text(
                            '已隐藏（${source.hiddenReason}）',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.orange,
                            ),
                          ),
                        if (manualHidden)
                          const Text(
                            '手动隐藏',
                            style: TextStyle(fontSize: 12, color: Colors.orange),
                          ),
                      ],
                    ),
                  ),
                  // 隐藏/显示按钮
                  IconButton(
                    icon: Icon(
                      manualHidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                      size: 18,
                    ),
                    color: manualHidden ? AppTokens.emerald : AppTokens.textTertiary,
                    onPressed: () => _toggleSourceVisibility(source),
                    tooltip: manualHidden ? '显示源' : '隐藏源',
                    visualDensity: VisualDensity.compact,
                  ),
                  // 展开指示
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: AppTokens.textTertiary,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                source.url.isNotEmpty ? source.url : source.detailUrl,
                style: const TextStyle(fontSize: 12, color: Colors.black45),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              // ── 展开详情 ──
              if (isExpanded) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 10),
                _buildDetailRow('ID', source.id),
                _buildDetailRow('详情 URL', source.detailUrl),
                _buildDetailRow('失败次数', '${source.failCount}'),
                if (source.lastFailAt != null)
                  _buildDetailRow('上次失败', source.lastFailAt.toString()),
                if (testResult != null)
                  _buildDetailRow('连通性测试', testResult),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (!isTesting)
                      ActionChip(
                        avatar: const Icon(Icons.wifi_find_rounded, size: 16),
                        label: const Text('测试连通性'),
                        onPressed: () => _testSource(source.id, source.url),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    const SizedBox(width: 8),
                    if (isActive)
                      ActionChip(
                        avatar: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('刷新源'),
                        onPressed: () => _refreshSources(controller),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppTokens.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
