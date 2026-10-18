import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../design_system/app_tokens.dart';

/// 图片工具（压缩 / 转格式 / 水印 / 拼接）共用的底座。
///
/// 四个面板的骨架完全一样：选图 → 预览参数 → 处理 → 保存到相册。
/// 差别只在「处理」那一步，所以把骨架收在这里，各面板只写一个
/// `Future<List<File>> Function(List<File>)`（或单图版本）。
///
/// 为什么用 `image` 包而不是 `dart:ui`：`dart:ui` 的 `ImageByteFormat` **只有 png**，
/// 没有 JPEG 编码，所以"把图压小""转成 jpg"这两类事用 Canvas 根本做不到
/// （PNG 无损，原尺寸重编码只会更大）。九宫格切图不需要这些，所以它仍走 dart:ui。
class ImageToolScaffold extends StatefulWidget {
  const ImageToolScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.pickLimit,
    required this.onProcess,
    required this.controls,
    this.processLabel = '处理',
    this.initialHint,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  /// 最多能选几张（1 = 单选，用于压缩/转格式/水印；多张用于拼接）。
  final int pickLimit;

  /// 处理动作：拿到已选文件，返回要展示/保存的结果。
  final Future<List<File>> Function(List<File> picked) onProcess;

  /// 参数控件（各工具自己决定放什么）。
  final Widget Function(BuildContext) controls;

  final String processLabel;

  /// 选图前的提示（比如"水印只支持英文数字"，提前说清楚比处理完才说好）。
  final String? initialHint;

  @override
  State<ImageToolScaffold> createState() => _ImageToolScaffoldState();
}

class _ImageToolScaffoldState extends State<ImageToolScaffold> {
  final List<XFile> _picked = [];
  List<File> _results = const [];
  String? _error;
  bool _busy = false;

  Future<void> _pick() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final picker = ImagePicker();
      if (widget.pickLimit <= 1) {
        final one = await picker.pickImage(source: ImageSource.gallery);
        if (!mounted) return;
        setState(() {
          _picked
            ..clear()
            ..addAll(one == null ? const [] : [one]);
          _results = const [];
          _busy = false;
        });
        return;
      }

      final many = await picker.pickMultiImage(limit: widget.pickLimit);
      if (!mounted) return;
      setState(() {
        _picked
          ..clear()
          ..addAll(many.take(widget.pickLimit));
        _results = const [];
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '选图失败：$e';
        _busy = false;
      });
    }
  }

  Future<void> _process() async {
    if (_picked.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final files = <File>[];
      for (final x in _picked) {
        final f = File(x.path);
        if (await f.exists()) files.add(f);
      }
      if (files.isEmpty) {
        if (!mounted) return;
        setState(() {
          _error = '选中的图片读不到了（可能已被移动或删除）';
          _busy = false;
        });
        return;
      }

      final out = await widget.onProcess(files);
      if (!mounted) return;
      setState(() {
        _results = out;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '处理失败：$e';
        _busy = false;
      });
    }
  }

  Future<void> _saveAll() async {
    if (_results.isEmpty) return;
    setState(() => _busy = true);
    var ok = 0;
    String? failure;
    for (final f in _results) {
      try {
        await Gal.putImage(f.path);
        ok++;
      } catch (e) {
        failure ??= '$e';
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);

    if (ok == _results.length) {
      _toast('已保存 $ok 张到相册');
    } else if (ok == 0) {
      _toast('保存失败：${failure ?? '未知原因'}');
    } else {
      // 部分成功也要如实说，不能报「已保存」让人以为全好了。
      _toast('只保存了 $ok / ${_results.length} 张，其余失败：${failure ?? '未知原因'}');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTokens.surfaceMuted,
            borderRadius: BorderRadius.circular(AppTokens.radiusCard),
            border: Border.all(color: AppTokens.cardBorder),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 20, color: AppTokens.primaryBlue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: AppTokens.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.initialHint != null) ...[
          const SizedBox(height: 10),
          Text(
            widget.initialHint!,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppTokens.textTertiary,
            ),
          ),
        ],
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _busy ? null : _pick,
          icon: const Icon(Icons.image_outlined),
          label: Text(_picked.isEmpty ? '选择图片' : '重新选择（已选 ${_picked.length} 张）'),
        ),
        if (_picked.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ThumbStrip(files: _picked),
          const SizedBox(height: 12),
          widget.controls(context),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _process,
            child: Text(widget.processLabel),
          ),
        ],
        if (_busy) const Padding(
          padding: EdgeInsets.only(top: 14),
          child: LinearProgressIndicator(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppTokens.danger)),
        ],
        if (_results.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            '处理完成，共 ${_results.length} 张',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          _ResultGrid(files: _results),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _busy ? null : _saveAll,
            icon: const Icon(Icons.download_rounded),
            label: Text('全部保存到相册（${_results.length} 张）'),
          ),
        ],
      ],
    );
  }
}

/// 已选图片的小缩略图条。
class _ThumbStrip extends StatelessWidget {
  const _ThumbStrip({required this.files});

  final List<XFile> files;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: files.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(files[i].path),
            width: 72,
            height: 72,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 72,
              height: 72,
              color: AppTokens.surfaceMuted,
              child: Icon(
                Icons.broken_image_outlined,
                color: AppTokens.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 处理结果网格（点开可看大图）。
class _ResultGrid extends StatelessWidget {
  const _ResultGrid({required this.files});

  final List<File> files;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: files.length,
      itemBuilder: (context, i) => GestureDetector(
        onTap: () => _preview(context, files[i]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(files[i], fit: BoxFit.cover),
        ),
      ),
    );
  }

  void _preview(BuildContext context, File file) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black),
          body: Center(
            child: InteractiveViewer(
              child: Image.file(file, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}

/// 把结果写到应用缓存目录下的独立子目录，返回文件。
///
/// 为什么要落盘而不是留在内存：`Gal.putImage` 需要一个真实文件路径；
/// 大图（几十 MB）留在内存里也容易把低端机顶掉。
Future<File> writeImageToolResult(
  Uint8List bytes,
  String name, {
  String bucket = 'image_tools',
}) async {
  final base = await getApplicationCacheDirectory();
  final dir = Directory(p.join(base.path, bucket));
  if (!await dir.exists()) await dir.create(recursive: true);
  final file = File(p.join(dir.path, name));
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

/// 读一张图并解码（`image` 包）。解不出来时抛一个有话说的异常。
Future<img.Image> decodePickedImage(File file) async {
  final bytes = await file.readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw FormatException('这个文件不是可识别的图片格式（${p.basename(file.path)}）');
  }
  return decoded;
}
