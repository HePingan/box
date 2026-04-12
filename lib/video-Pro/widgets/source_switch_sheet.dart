import 'package:flutter/material.dart';
import '../models/video_source.dart';
import '../services/source_visibility_repository.dart';

class SourceSwitchSheet extends StatefulWidget {
  final List<VideoSource> sources;
  final SourceVisibilityRepository visibilityRepo;
  final VideoSource? currentSource;
  final Future<void> Function(VideoSource source) onSelectSource;
  final Future<void> Function(VideoSource source, bool hidden) onToggleHidden;
  final Future<void> Function() onScanAll;

  const SourceSwitchSheet({
    super.key,
    required this.sources,
    required this.visibilityRepo,
    required this.currentSource,
    required this.onSelectSource,
    required this.onToggleHidden,
    required this.onScanAll,
  });

  @override
  State<SourceSwitchSheet> createState() => _SourceSwitchSheetState();
}

class _SourceSwitchSheetState extends State<SourceSwitchSheet> {
  bool _showHidden = false;
  bool _isScanning = false;

  @override
  Widget build(BuildContext context) {
    final list = _showHidden
        ? widget.sources
        : widget.visibilityRepo.filterVisible(widget.sources);

    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),

            // 顶部操作栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text(
                    '切换视频源',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _isScanning
                        ? null
                        : () async {
                            setState(() => _isScanning = true);
                            try {
                              await widget.onScanAll();
                            } finally {
                              if (mounted) {
                                setState(() => _isScanning = false);
                              }
                            }
                          },
                    icon: _isScanning
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: Text(_isScanning ? '检测中' : '全量检测'),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('显示隐藏源'),
                  const Spacer(),
                  Switch(
                    value: _showHidden,
                    onChanged: (v) {
                      setState(() => _showHidden = v);
                    },
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            Expanded(
              child: ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final source = list[index];
                  final record = widget.visibilityRepo.getRecord(source);
                  final selected = widget.currentSource?.url == source.url;

                  return ListTile(
                    leading: Icon(
                      selected ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: selected ? Colors.blue : Colors.grey,
                    ),
                    title: Text(
                      source.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: record.isHidden ? Colors.grey : Colors.black,
                      ),
                    ),
                    subtitle: Text(
                      source.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: record.isHidden ? Colors.grey : Colors.black54,
                      ),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'select') {
                          await widget.onSelectSource(source);
                          if (mounted) Navigator.pop(context);
                        } else if (value == 'hide') {
                          await widget.onToggleHidden(source, true);
                          setState(() {});
                        } else if (value == 'show') {
                          await widget.onToggleHidden(source, false);
                          setState(() {});
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'select',
                          child: Text('使用此源'),
                        ),
                        PopupMenuItem(
                          value: record.manualHidden ? 'show' : 'hide',
                          child: Text(record.manualHidden ? '恢复显示' : '手动隐藏'),
                        ),
                      ],
                    ),
                    onTap: () async {
                      await widget.onSelectSource(source);
                      if (mounted) Navigator.pop(context);
                    },
                    onLongPress: () async {
                      await widget.onToggleHidden(source, !record.manualHidden);
                      setState(() {});
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}