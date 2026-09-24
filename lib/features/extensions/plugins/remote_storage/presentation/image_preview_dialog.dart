// 图片预览对话框：相册式左右滑动（283 D5）。
//
// 以前只能看被点的那一张：看完退出、再点下一张，相册场景下就是反复"点开-退出"。
// 这里把同目录的图片按当前列表顺序做成 PageView，左右滑动连续看，标题显示
// "第几张 / 共几张"。
//
// 三个要点：
//   - **预取只做相邻一张**：图片预览要整张下载（20MB 上限），预取太多等于替用户
//     决定花流量；相邻一张是"滑动时就绪"和"别乱花流量"的折中。
//   - **失败/超大不阻塞滑动**：某一页取不到只影响那一页（显示原因，仍可滑走）；
//     否则一张坏图会把整个相册卡住。
//   - **缩放后接管拖动**：InteractiveViewer 放大后要能平移看细节；没放大时把
//     水平拖动让给 PageView，否则滑不动（这是 PageView + InteractiveViewer 的
//     经典冲突）。

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../application/remote_storage_service.dart';
import '../domain/remote_storage_models.dart';

/// 相邻预取范围（张）。
const int kGalleryPrefetchRadius = 1;

class ImagePreviewDialog extends StatefulWidget {
  const ImagePreviewDialog({
    super.key,
    required this.account,
    required this.entries,
    required this.initialIndex,
    this.onShare,
    this.onSaveToDevice,
  });

  final RemoteStorageAccount account;

  /// 可左右浏览的图片（调用方按当前列表顺序给）。
  final List<RemoteStorageEntry> entries;

  /// 起始下标（用户点的那张）。
  final int initialIndex;

  /// 「分享」/「保存到…」（284 P2）。
  ///
  /// 由调用方实现、而不是在对话框里直接做：写临时文件、系统 SAF 另存、SharePlus
  /// 这一整套流程属于浏览器页（它已有下载/导出的完整实现），在这里复制一份必然会
  /// 出现两套不一致的提示文案与大小判断。
  final Future<void> Function(RemoteStorageEntry entry, PreviewPayload payload)?
      onShare;
  final Future<void> Function(RemoteStorageEntry entry, PreviewPayload payload)?
      onSaveToDevice;

  @override
  State<ImagePreviewDialog> createState() => _ImagePreviewDialogState();
}

class _ImagePreviewDialogState extends State<ImagePreviewDialog> {
  late final PageController _controller;
  late int _index;

  /// 导出中：挡住重复点击（一次导出会写临时文件 + 起系统分享，连点会起两次）。
  bool _exporting = false;

  /// 路径 → 取图结果。同一个 Future 复用，滑动来回不会重复下载。
  final Map<String, Future<PreviewPayload>> _payloads = {};

  @override
  void initState() {
    super.initState();
    _index = widget.entries.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.entries.length - 1);
    _controller = PageController(initialPage: _index);
    _warmNeighbours();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<PreviewPayload> _payloadFor(int index) {
    final entry = widget.entries[index];
    return _payloads.putIfAbsent(
      entry.path,
      () => remoteStorageService().readImagePreview(widget.account, entry.path),
    );
  }

  /// 预取相邻张（并顺手丢掉远处的缓存，别把几十 MB 的图都攥在手里）。
  void _warmNeighbours() {
    for (var d = 1; d <= kGalleryPrefetchRadius; d++) {
      for (final i in [_index - d, _index + d]) {
        if (i >= 0 && i < widget.entries.length) {
          unawaited(_payloadFor(i).then((_) {}, onError: (_) {}));
        }
      }
    }
    final keep = <String>{
      for (var i = _index - kGalleryPrefetchRadius;
          i <= _index + kGalleryPrefetchRadius;
          i++)
        if (i >= 0 && i < widget.entries.length) widget.entries[i].path,
    };
    _payloads.removeWhere((path, _) => !keep.contains(path));
  }

  void _onPageChanged(int index) {
    setState(() => _index = index);
    _warmNeighbours();
  }

  /// 分享/保存当前这一张。字节已经在内存里（预览上限 20MB），不再下载第二次。
  Future<void> _export({required bool share}) async {
    final action = share ? widget.onShare : widget.onSaveToDevice;
    if (action == null || _exporting) return;
    final entry = widget.entries[_index];
    setState(() => _exporting = true);
    try {
      final payload = await _payloadFor(_index);
      if (!mounted) return;
      if (payload.oversize || payload.bytes.isEmpty) {
        _toast('这张图没有可导出的内容');
        return;
      }
      await action(entry, payload);
    } catch (e) {
      if (mounted) _toast(share ? '分享失败：$e' : '保存失败：$e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = widget.entries.length;
    if (total == 0) {
      return _message(context, '这张图不在当前列表里，返回后重试。');
    }
    final media = MediaQuery.maybeOf(context);
    final decodeWidth = media == null
        ? null
        : previewImageDecodeWidth(
            logicalWidth: media.size.width,
            devicePixelRatio: media.devicePixelRatio,
          );
    final maxHeight = media == null ? 420.0 : media.size.height * 0.7;

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: PageView.builder(
                controller: _controller,
                itemCount: total,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) => _GalleryImagePage(
                  future: _payloadFor(index),
                  decodeWidth: decodeWidth,
                  entry: widget.entries[index],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.entries[_index].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  if (total > 1)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        '${_index + 1} / $total',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (widget.onSaveToDevice != null)
                    TextButton(
                      onPressed: _exporting ? null : () => _export(share: false),
                      child: const Text('保存到…'),
                    ),
                  if (widget.onShare != null)
                    TextButton(
                      onPressed: _exporting ? null : () => _export(share: true),
                      child: const Text('分享'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _message(BuildContext context, String text) {
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 相册里的一页：加载中 / 失败 / 超大 / 图片本身。
class _GalleryImagePage extends StatefulWidget {
  const _GalleryImagePage({
    required this.future,
    required this.entry,
    this.decodeWidth,
  });

  final Future<PreviewPayload> future;
  final RemoteStorageEntry entry;
  final int? decodeWidth;

  @override
  State<_GalleryImagePage> createState() => _GalleryImagePageState();
}

class _GalleryImagePageState extends State<_GalleryImagePage> {
  final TransformationController _transform = TransformationController();

  /// 放大之后才允许平移：没放大时把水平拖动让给 PageView（否则滑不动）。
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransformChanged);
    _transform.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed == _zoomed) return;
    setState(() => _zoomed = zoomed);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PreviewPayload>(
      future: widget.future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox(
              height: 240,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snapshot.hasError) {
          return _note(context, '预览失败：${snapshot.error}\n可左右滑动看下一张');
        }
        final payload = snapshot.data!;
        if (payload.oversize) {
          return _note(
            context,
            '图片超过 ${formatRemoteBytes(kPreviewImageMaxBytes)}，已跳过预览。\n'
            '可下载后查看，或左右滑动看下一张',
          );
        }
        return InteractiveViewer(
          maxScale: 5,
          panEnabled: _zoomed,
          transformationController: _transform,
          child: Center(
            child: Image.memory(
              Uint8List.fromList(payload.bytes),
              fit: BoxFit.contain,
              gaplessPlayback: true,
              cacheWidth: widget.decodeWidth,
            ),
          ),
        );
      },
    );
  }

  Widget _note(BuildContext context, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
