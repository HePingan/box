import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/video/controller/video_detail_controller.dart';
import 'package:box/video/controller/video_download_controller.dart';
import 'package:box/video/models/video_download_task.dart';
import 'package:box/video/pages/detail/detail_models.dart';
import 'package:box/video/pages/video_downloads_page.dart';

/// Episode picker for a single play line. A task always maps to the selected
/// line so an episode selection never accidentally queues duplicate sources.
class VideoDownloadBottomSheet extends StatefulWidget {
  const VideoDownloadBottomSheet({super.key});

  @override
  State<VideoDownloadBottomSheet> createState() =>
      _VideoDownloadBottomSheetState();
}

class _VideoDownloadBottomSheetState extends State<VideoDownloadBottomSheet>
    with SingleTickerProviderStateMixin {
  final Set<int> _selectedEpisodes = <int>{};
  bool _loading = true;
  bool _submitting = false;
  int _selectedLineIndex = 0;
  List<DetailPlayLine> _playLines = const <DetailPlayLine>[];
  late final AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    // Listen for detail controller updates so episodes appear even if
    // the API call hasn't finished when the bottom sheet opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final detailController = context.read<VideoDetailController>();
      detailController.addListener(_onDetailChanged);
      _load(detailController);
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _onDetailChanged() {
    if (!mounted) return;
    final detailController = context.read<VideoDetailController>();
    if (_playLines.isNotEmpty && !detailController.isLoading) return;
    _load(detailController);
  }

  Future<void> _load(VideoDetailController detailController) async {
    if (!mounted) return;
    final newLines = detailController.playLines
        .where((line) => line.episodes.isNotEmpty)
        .toList(growable: false);
    final changed = newLines.length != _playLines.length ||
        (newLines.isNotEmpty &&
            _playLines.isNotEmpty &&
            newLines[0].name != _playLines[0].name);
    if (!changed && detailController.isLoading == _loading) return;
    setState(() {
      _playLines = newLines;
      _selectedLineIndex = _playLines.isEmpty
          ? 0
          : detailController.selectedLineIndex.clamp(0, _playLines.length - 1);
      _loading = detailController.isLoading;
      _fadeController.forward();
    });
  }

  DetailPlayLine? get _selectedLine =>
      _playLines.isEmpty ? null : _playLines[_selectedLineIndex];

  void _selectLine(int index) {
    setState(() {
      _selectedLineIndex = index;
      _selectedEpisodes.clear();
    });
  }

  void _toggleAll() {
    final episodeCount = _selectedLine?.episodes.length ?? 0;
    setState(() {
      if (_selectedEpisodes.length == episodeCount) {
        _selectedEpisodes.clear();
      } else {
        _selectedEpisodes
          ..clear()
          ..addAll(List<int>.generate(episodeCount, (index) => index));
      }
    });
  }

  Future<void> _enqueueSelected() async {
    if (_submitting) return;
    // Capture the parent navigator context BEFORE popping the modal.
    final parentNavigator = Navigator.of(context);
    late final VideoDownloadController downloadController;
    late final VideoDetailController detailController;
    try {
      downloadController = context.read<VideoDownloadController>();
      detailController = context.read<VideoDetailController>();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加载失败：$e')));
      return;
    }
    final line = _selectedLine;
    if (line == null || _selectedEpisodes.isEmpty) {
      setState(() => _submitting = false);
      return;
    }

    setState(() => _submitting = true);
    final source = detailController.source;
    final detail = detailController.fullDetail;
    var queuedCount = 0;
    for (final episodeIndex in _selectedEpisodes.toList()..sort()) {
      final episode = line.episodes[episodeIndex];
      final task = VideoDownloadTask(
        id: '${source.id}|${detail?.vodId ?? '0'}|L$_selectedLineIndex|E${episode.url.hashCode}',
        sourceId: source.id,
        vodId: (detail?.vodId ?? 0).toString(),
        vodName: detail?.vodName ?? source.name,
        vodPic: detail?.vodPic ?? '',
        sourceName: source.name,
        episodeName: episode.name,
        mediaUrl: episode.url,
        referer: source.detailUrl,
        createdAt: DateTime.now(),
      );
      try {
        final ok = await downloadController.enqueue(task);
        if (ok) queuedCount++;
      } catch (e) {
        // continue with other episodes
      }
    }

    if (!mounted) return;
    if (queuedCount == 0) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未能创建下载任务，请稍后重试')));
      return;
    }

    // Pop the bottom sheet first, then navigate on the parent navigator.
    parentNavigator.pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已加入下载队列（$queuedCount 集），正在打开下载管理…'),
        duration: const Duration(seconds: 3),
      ),
    );
    // Wait a frame after pop so the modal's route is fully removed.
    await Future.delayed(Duration.zero);
    if (mounted) {
      try {
        parentNavigator.push(
          MaterialPageRoute(builder: (_) => const VideoDownloadsPage()),
        );
      } catch (e) {
        // Navigator might be closed; show feedback on current page instead.
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已加入下载队列（$queuedCount 集）')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final line = _selectedLine;
    final episodeCount = line?.episodes.length ?? 0;
    final allSelected =
        episodeCount > 0 && _selectedEpisodes.length == episodeCount;

    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text(
                  '选择要下载的集数',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppTokens.textPrimary,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: episodeCount == 0 ? null : _toggleAll,
                  child: Text(allSelected ? '取消全选' : '全选'),
                ),
              ],
            ),
          ),
          if (_playLines.length > 1)
            SizedBox(
              height: 38,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: _playLines.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) => ChoiceChip(
                  label: Text(_playLines[index].name),
                  selected: index == _selectedLineIndex,
                  onSelected: (_) => _selectLine(index),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : line == null
                ? const Center(
                    child: Text(
                      '暂无可下载的集数',
                      style: TextStyle(color: AppTokens.textSecondary),
                    ),
                  )
                : FadeTransition(
                    opacity: _fadeController,
                    child: GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 1.6,
                          ),
                      itemCount: episodeCount,
                      itemBuilder: (context, index) {
                        final selected = _selectedEpisodes.contains(index);
                        return InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => setState(() {
                            if (selected) {
                              _selectedEpisodes.remove(index);
                            } else {
                              _selectedEpisodes.add(index);
                            }
                          }),
                          child: Container(
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFF3B82F6)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              line.episodes[index].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? Colors.white
                                    : AppTokens.textPrimary,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            child: ElevatedButton(
              onPressed: _selectedEpisodes.isEmpty || _submitting
                  ? null
                  : _enqueueSelected,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text('下载 ${_selectedEpisodes.length} 集'),
            ),
          ),
        ],
      ),
    );
  }
}
