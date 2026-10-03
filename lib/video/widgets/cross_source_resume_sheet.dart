import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/app_tokens.dart';
import '../../design_system/widgets/app_bottom_sheet.dart';
import '../models/video_source.dart';
import '../pages/video_detail_page.dart';
import '../services/cross_source_resume.dart';
import '../video_module.dart';

/// 换了源之后要带过去的东西：片名之外还有「上次看到哪一集、哪个位置」。
class CrossSourceResumeRequest {
  const CrossSourceResumeRequest({
    required this.vodName,
    this.episodeName = '',
    this.position = 0,
  });

  final String vodName;
  final String episodeName;
  final int position;
}

/// 「原片源已失效」时的那一句提示，**带一个换源入口** —— 不再是死胡同。
///
/// 一处实现，多处调用（首页续播 / 历史快捷视图 / 观看历史页 / 收藏页+收藏库）。
void showSourceGoneWithFallback(
  BuildContext context, {
  required List<VideoSource> sources,
  required CrossSourceResumeRequest request,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('该视频的片源已失效或被移除'),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: '换源找',
        onPressed: () => unawaited(
          showCrossSourceResumeSheet(
            context,
            sources: sources,
            request: request,
          ),
        ),
      ),
    ),
  );
}

/// 打开「换源找片」面板：在可用片源里找同一部片，找到就直接进详情页续播。
///
/// 搜索本身要 1~8s，所以进度做在面板里（而不是先关面板再等），
/// 面板自带三态：找中 → 找到（pop 出结果，由调用方跳页）→ 没找到（如实说明）。
Future<void> showCrossSourceResumeSheet(
  BuildContext context, {
  required List<VideoSource> sources,
  required CrossSourceResumeRequest request,
  CrossSourceMovieFinder finder = const CrossSourceMovieFinder(),
}) async {
  final hit = await showAppModalBottomSheet<CrossSourceHit>(
    context: context,
    builder: (_) => _CrossSourceResumeSheet(
      sources: sources,
      request: request,
      finder: finder,
    ),
  );
  if (hit == null || !context.mounted) return;

  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => VideoDetailPage(
        source: hit.source,
        vodId: hit.vodId,
        // 跨源续播：地址必然不同，只能按剧集名认同一集（认不上就从头播）。
        initialEpisodeName: request.episodeName.trim().isEmpty
            ? null
            : request.episodeName,
        initialPosition: request.position,
      ),
    ),
  );
}

class _CrossSourceResumeSheet extends StatefulWidget {
  const _CrossSourceResumeSheet({
    required this.sources,
    required this.request,
    required this.finder,
  });

  final List<VideoSource> sources;
  final CrossSourceResumeRequest request;
  final CrossSourceMovieFinder finder;

  @override
  State<_CrossSourceResumeSheet> createState() =>
      _CrossSourceResumeSheetState();
}

class _CrossSourceResumeSheetState extends State<_CrossSourceResumeSheet> {
  CrossSourceReport? _report;
  int _candidateCount = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    final candidates = VideoModule.visibleSourcesOf(widget.sources).length;
    if (mounted) setState(() => _candidateCount = candidates);

    final report = await widget.finder.find(
      sources: widget.sources,
      vodName: widget.request.vodName,
    );
    if (!mounted) return;

    if (report.hit != null) {
      Navigator.of(context).pop(report.hit);
      return;
    }
    setState(() => _report = report);
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return AppBottomSheetFrame(
      title: '换源找片',
      subtitle: '《${widget.request.vodName}》',
      child: report == null ? _searching() : _missed(report),
    );
  }

  Widget _searching() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceXl),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppTokens.spaceMd),
          Expanded(
            child: Text(
              '正在 $_candidateCount 个可用片源里找这部片…',
              style: const TextStyle(
                color: AppTokens.textSecondary,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _missed(CrossSourceReport report) {
    if (report.searched == 0) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '当前没有可用的片源（片源目录还没加载，或都被隐藏了）。'
            '先去影视页刷新一下片源，再回来试。',
            style: TextStyle(
              color: AppTokens.textSecondary,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppTokens.spaceLg),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      );
    }
    final failed = report.failedSources;
    final failedNote = failed.isEmpty
        ? '这些片源这次都答了，只是没有这部片。'
        : '其中 ${failed.length} 个这次没答上来（${failed.take(3).join('、')}'
              '${failed.length > 3 ? ' 等' : ''}），已记一笔，不影响它们继续用。';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '已在 ${report.searched} 个可用片源里找过，都没有《${widget.request.vodName}》。$failedNote',
          style: const TextStyle(
            color: AppTokens.textSecondary,
            fontSize: 13.5,
            height: 1.5,
          ),
        ),
        const SizedBox(height: AppTokens.spaceLg),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    );
  }
}
