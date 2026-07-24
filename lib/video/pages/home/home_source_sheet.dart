import 'package:flutter/material.dart';

import '../../controller/video_controller.dart';
import '../../models/video_source.dart';
import '../../services/source_health_service.dart';

Future<void> showHomeSourcePickerSheet(
  BuildContext context,
  VideoController controller,
) async {
  if (controller.sources.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('暂无可切换的片源')));
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxHeight = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : MediaQuery.of(context).size.height * 0.75;

            return Container(
              constraints: BoxConstraints(maxHeight: maxHeight * 0.92),
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: SafeArea(
                child: _SourcePickerBody(controller: controller),
              ),
            );
          },
        ),
      );
    },
  );
}

/// Real playback-chain health status derived from persisted source state.
enum _SourceHealth { healthy, warning, down, unknown, checking }

class _SourcePickerBody extends StatefulWidget {
  const _SourcePickerBody({required this.controller});

  final VideoController controller;

  @override
  State<_SourcePickerBody> createState() => _SourcePickerBodyState();
}

class _SourcePickerBodyState extends State<_SourcePickerBody> {
  static const SourceHealthService _healthService = SourceHealthService();

  /// Live-check overrides keyed by source id. Absent = show persisted state.
  final Map<String, SourceCheckResult> _liveResults = <String, SourceCheckResult>{};
  final Set<String> _checking = <String>{};
  bool _scanningAll = false;

  VideoController get controller => widget.controller;

  /// Health from real signals: a fresh live probe wins, else persisted
  /// failCount / hidden state from the catalog.
  _SourceHealth _healthOf(VideoSource source) {
    if (_checking.contains(source.id)) return _SourceHealth.checking;

    final live = _liveResults[source.id];
    if (live != null) {
      return live.success ? _SourceHealth.healthy : _SourceHealth.down;
    }

    if (source.isHidden) return _SourceHealth.down;
    if (source.failCount >= 3) return _SourceHealth.down;
    if (source.failCount > 0) return _SourceHealth.warning;
    // No failures recorded yet — genuinely unknown until probed.
    return _SourceHealth.unknown;
  }

  String _healthLabel(VideoSource source, _SourceHealth health) {
    switch (health) {
      case _SourceHealth.checking:
        return '检测中';
      case _SourceHealth.healthy:
        return '可用';
      case _SourceHealth.warning:
        return '近期失败 ${source.failCount} 次';
      case _SourceHealth.down:
        final live = _liveResults[source.id];
        if (live != null) return live.message;
        if (source.isHidden) {
          return source.hiddenReason == 'auto' ? '已自动隐藏' : '已隐藏';
        }
        return '连续失败 ${source.failCount} 次';
      case _SourceHealth.unknown:
        return '未检测';
    }
  }

  Color _healthColor(_SourceHealth health) {
    switch (health) {
      case _SourceHealth.healthy:
        return const Color(0xFF16A34A);
      case _SourceHealth.warning:
        return const Color(0xFFD97706);
      case _SourceHealth.down:
        return const Color(0xFFDC2626);
      case _SourceHealth.checking:
        return const Color(0xFF2563EB);
      case _SourceHealth.unknown:
        return Colors.black45;
    }
  }

  Future<void> _checkOne(VideoSource source) async {
    if (_checking.contains(source.id)) return;
    setState(() => _checking.add(source.id));
    try {
      final result = await _healthService.checkSource(source);
      if (!mounted) return;
      setState(() {
        _liveResults[source.id] = result;
        _checking.remove(source.id);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checking.remove(source.id));
    }
  }

  Future<void> _checkAll() async {
    if (_scanningAll) return;
    setState(() {
      _scanningAll = true;
      _checking.addAll(controller.sources.map((s) => s.id));
    });
    try {
      await _healthService.scanAll(
        controller.sources,
        includeDisabled: true,
        onEachResult: (result) async {
          if (!mounted) return;
          setState(() {
            _liveResults[result.source.id] = result;
            _checking.remove(result.source.id);
          });
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _scanningAll = false;
          _checking.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sources = controller.sources;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.live_tv_rounded, color: Colors.blue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '片源管理',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '当前可切换 ${sources.length} 个片源，选择后立即应用',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 30,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: _scanningAll ? null : _checkAll,
                  icon: _scanningAll
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.health_and_safety_rounded, size: 16),
                  label: Text(
                    _scanningAll ? '检测中' : '全部检测',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
            itemCount: sources.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final source = sources[index];
              final selected = source.id == controller.currentSource?.id;
              final subtitle = source.detailUrl.trim().isNotEmpty
                  ? source.detailUrl
                  : source.url;
              final health = _healthOf(source);
              final healthColor = _healthColor(health);

              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () {
                  Navigator.pop(context);
                  controller.setCurrentSource(source);
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.blue.withValues(alpha: 0.07)
                        : const Color(0xFFF7F8FA),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: selected
                          ? Colors.blue.withValues(alpha: 0.22)
                          : const Color(0xFFE6EAF2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked,
                        color: selected ? Colors.blue : Colors.grey,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    source.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: selected
                                          ? FontWeight.w900
                                          : FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _HealthBadge(
                                  color: healthColor,
                                  label: _healthLabel(source, health),
                                  checking: health == _SourceHealth.checking,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (selected)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            '使用中',
                            style: TextStyle(
                              color: Colors.blue,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        )
                      else
                        SizedBox(
                          height: 30,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: health == _SourceHealth.checking
                                ? null
                                : () => _checkOne(source),
                            child: const Text(
                              '检测',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HealthBadge extends StatelessWidget {
  const _HealthBadge({
    required this.color,
    required this.label,
    required this.checking,
  });

  final Color color;
  final String label;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (checking)
            SizedBox(
              width: 9,
              height: 9,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: color),
            )
          else
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
