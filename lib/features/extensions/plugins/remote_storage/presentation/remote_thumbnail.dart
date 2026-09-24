// 列表行里的图片缩略图。
//
// 行为约定（都是"列表体验"的要求，不是可选项）：
// - **不闪、不跳**：加载中直接显示原来的通用图标（不显示 spinner），拿到字节后
//   才换成图；`gaplessPlayback` 保证替换时不闪白。
// - **失败即回退**：取不到、解码失败、格式不支持，一律回退通用图标——列表里绝不
//   显示错误或红叉（那是"看个文件名"的场景，不该被一张缩略图搅乱）。
// - **小内存**：按 [kThumbnailDecodeWidth] 降采样解码。不降采样的话，一张
//   4000×3000 的 JPEG 解码后是 48MB 位图，一屏十几行直接打满内存。
// - **不追生命周期**：加载完成后 widget 可能已经被回收（滚动出去了），
//   `mounted` 检查后再 setState。

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../domain/remote_storage_models.dart';

class RemoteThumbnail extends StatefulWidget {
  const RemoteThumbnail({
    super.key,
    required this.load,
    required this.placeholder,
    this.size = 40,
    this.borderRadius = 6,
  });

  /// 取字节；返回 null 表示取不到（回退占位）。
  final Future<Uint8List?> Function() load;

  /// 加载中与失败时显示的占位（调用方给的是原来的通用图标）。
  final Widget placeholder;

  final double size;
  final double borderRadius;

  @override
  State<RemoteThumbnail> createState() => _RemoteThumbnailState();
}

class _RemoteThumbnailState extends State<RemoteThumbnail> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RemoteThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 同一个行位置复用到别的图片上（ListView 复用）时重新取。
    if (oldWidget.key != widget.key) {
      _bytes = null;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.load();
      if (!mounted || bytes == null || bytes.isEmpty) return;
      setState(() => _bytes = bytes);
    } catch (_) {
      // 取图失败不冒泡：保持占位即可。
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return widget.placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Image.memory(
        bytes,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        // 关键：按物理像素宽度解码（128px），而不是按原图尺寸。
        cacheWidth: kThumbnailDecodeWidth,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, _, _) => widget.placeholder,
      ),
    );
  }
}
