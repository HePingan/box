import 'dart:async';

import 'package:flutter/material.dart';

import '../../controller/video_controller.dart';
import '../../models/video_source.dart';
import '../../services/source_health_service.dart';
import '../../video_module.dart';
import '../../../design_system/app_tokens.dart';

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
                color: AppTokens.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: SafeArea(child: _SourcePickerBody(controller: controller)),
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
  final Map<String, SourceCheckResult> _liveResults =
      <String, SourceCheckResult>{};
  final Set<String> _checking = <String>{};
  bool _scanningAll = false;

  VideoController get controller => widget.controller;

  /// ① 的可见性层（自动隐藏坏源）与这个面板原先读的模型字段是**两套真相**：
  /// 面板改读同一处，才能显示「已自动隐藏 · 原因」并给出恢复入口。
  SourceVisibilityRecord _visibilityOf(VideoSource source) =>
      VideoModule.getVisibilityRecord(source);

  bool _isHidden(VideoSource source) =>
      _visibilityOf(source).isHidden || source.isHidden;

  int _failCountOf(VideoSource source) {
    final recorded = _visibilityOf(source).failCount;
    return recorded > 0 ? recorded : source.failCount;
  }

  @override
  void initState() {
    super.initState();
    // 可见性层是异步读盘的：读完刷新一次标签，别让面板停留在旧状态。
    unawaited(
      VideoModule.ensureVisibilityLoaded().then((_) {
        if (mounted) setState(() {});
      }),
    );
  }

  /// 恢复一个被隐藏的源：自动隐藏与手动隐藏都清掉，连续失败计数一并归零，
  /// 否则恢复完 failCount 还在 3 以上，面板仍判它不可用。
  Future<void> _restore(VideoSource source) async {
    await VideoModule.setSourceAutoHidden(source, false, failCount: 0);
    await VideoModule.setSourceManualHidden(source, false);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已恢复「${source.name}」，下次搜索会重新用它')));
  }

  /// 点一个不可用的源时给的说明：优先说清「为什么不可用」。
  String _deadReason(VideoSource source) {
    final record = _visibilityOf(source);
    if (record.autoHidden) {
      final why = record.lastReason?.trim();
      return (why == null || why.isEmpty)
          ? '已被自动隐藏，点右侧「恢复」可用'
          : '已被自动隐藏（$why），点右侧「恢复」可用';
    }
    if (record.manualHidden || source.isHidden) {
      return '已被隐藏，点右侧「恢复」可用';
    }
    return '源站已失效，暂不可用';
  }

  /// Health from real signals: a fresh live probe wins, else persisted
  /// failCount / hidden state from the catalog.
  _SourceHealth _healthOf(VideoSource source) {
    if (_checking.contains(source.id)) return _SourceHealth.checking;

    // 被隐藏的源：不管临时探测多好，它都不会进搜索 —— 标签必须说实话。
    final record = _visibilityOf(source);
    if (record.isHidden || source.isHidden) return _SourceHealth.down;

    final live = _liveResults[source.id];
    if (live != null) {
      return live.success ? _SourceHealth.healthy : _SourceHealth.down;
    }

    // 先读 ① 的可见性层（搜索真正在用的那套），再兜底模型字段。
    if (record.failCount >= 3) return _SourceHealth.down;
    if (record.failCount > 0) return _SourceHealth.warning;

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
        return '近期失败 ${_failCountOf(source)} 次';
      case _SourceHealth.down:
        final record = _visibilityOf(source);
        if (record.isHidden) {
          final verb = record.autoHidden ? '已自动隐藏' : '已手动隐藏';
          final why = record.lastReason?.trim();
          return (why == null || why.isEmpty) ? verb : '$verb · $why';
        }
        if (source.isHidden) {
          return source.hiddenReason == 'auto' ? '已自动隐藏' : '已隐藏';
        }
        final live = _liveResults[source.id];
        if (live != null) return live.message;
        return '连续失败 ${_failCountOf(source)} 次';
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
        return AppTokens.textTertiary;
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

  /// 排序权重：可用/未检测优先，失败次之，已死沉底。
  /// 让“点了是空白”的死源不再挤在列表中段。
  int _healthSortRank(_SourceHealth health) {
    switch (health) {
      case _SourceHealth.healthy:
        return 0;
      case _SourceHealth.checking:
        return 1;
      case _SourceHealth.unknown:
        return 2;
      case _SourceHealth.warning:
        return 3;
      case _SourceHealth.down:
        return 4;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 稳定排序：先按健康度分档(死源沉底)，同档内保持目录原始顺序。
    final sources = List<VideoSource>.of(controller.sources);
    final autoHiddenCount = sources
        .where((s) => _visibilityOf(s).autoHidden)
        .length;
    final originalIndex = <String, int>{
      for (var i = 0; i < controller.sources.length; i++)
        controller.sources[i].id: i,
    };
    sources.sort((a, b) {
      final rankDiff = _healthSortRank(
        _healthOf(a),
      ).compareTo(_healthSortRank(_healthOf(b)));
      if (rankDiff != 0) return rankDiff;
      return (originalIndex[a.id] ?? 0).compareTo(originalIndex[b.id] ?? 0);
    });
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
                      autoHiddenCount > 0
                          ? '共 ${sources.length} 个片源，$autoHiddenCount 个已自动隐藏（可恢复）'
                          : '当前可切换 ${sources.length} 个片源，选择后立即应用',
                      style: TextStyle(
                        color: AppTokens.textSecondary,
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
              // 已确证失效(实测 down)的源置灰，点击时给出明确提示而非
              // 静默切过去看空白。未检测/失败中的源仍可正常切换。
              final isDead = health == _SourceHealth.down;

              return Opacity(
                opacity: isDead ? 0.55 : 1.0,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {
                    if (isDead) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '「${source.name}」${_deadReason(source)}',
                          ),
                        ),
                      );
                      return;
                    }
                    Navigator.pop(context);
                    controller.setCurrentSource(source);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.blue.withValues(alpha: 0.07)
                          : AppTokens.surfaceMuted,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: selected
                            ? Colors.blue.withValues(alpha: 0.22)
                            : AppTokens.cardBorder,
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
                                style: TextStyle(
                                  color: AppTokens.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        // 被隐藏（含 ① 自动隐藏）的源：给恢复入口，别让用户只能干看着。
                        if (_isHidden(source))
                          SizedBox(
                            height: 30,
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => _restore(source),
                              icon: const Icon(Icons.restore_rounded, size: 15),
                              label: const Text(
                                '恢复',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          )
                        else if (selected)
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
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
