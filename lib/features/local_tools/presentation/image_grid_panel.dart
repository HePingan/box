import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../design_system/app_tokens.dart';
import '../domain/local_tool_image_grid.dart';
import 'local_tool_panels.dart';

/// 九宫格切图的界面。
///
/// 分工：几何计算全在 [GridCutGeometry]（纯 Dart，单测覆盖边界与余数），
/// 这一层只做「选图 → 按给出的矩形裁 → 存」。
///
/// 为什么用 `dart:ui` 而不是引三方图像库：切图本质是「按矩形裁一块再编码」，
/// `instantiateImageCodec` + `Canvas` 就够了，不需要为它新增一个原生依赖
/// （构建环境受限时，新依赖是实打实的成本）。
class ImageGridPanelBody extends StatefulWidget {
  const ImageGridPanelBody({super.key});

  @override
  State<ImageGridPanelBody> createState() => _ImageGridPanelBodyState();
}

class _ImageGridPanelBodyState extends State<ImageGridPanelBody> {
  File? _source;
  ui.Image? _decoded;
  String? _error;
  bool _busy = false;

  int _rows = 3;
  int _cols = 3;

  /// 切好之后的结果（存到应用缓存目录，供预览与保存）。
  List<File> _pieces = const [];

  @override
  void dispose() {
    _decoded?.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final bytes = await picked.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();

      final suggested = GridCutGeometry.suggestGrid(
        frame.image.width,
        frame.image.height,
      );
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      _decoded?.dispose();
      setState(() {
        _source = File(picked.path);
        _decoded = frame.image;
        _rows = suggested.$1;
        _cols = suggested.$2;
        _pieces = const [];
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '读取图片失败：$e';
        _busy = false;
      });
    }
  }

  Future<void> _cut() async {
    final image = _decoded;
    if (image == null) return;

    if (!canSplitInto(
      width: image.width,
      height: image.height,
      rows: _rows,
      cols: _cols,
    )) {
      setState(() => _error = '这张图切 ${_rows}x$_cols 后每块不到 20px，没有意义');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rects = GridCutGeometry.split(
        width: image.width,
        height: image.height,
        rows: _rows,
        cols: _cols,
      );

      final dir = await getApplicationCacheDirectory();
      final outDir = Directory(
        p.join(dir.path, 'grid_cut', DateTime.now().millisecondsSinceEpoch.toString()),
      );
      await outDir.create(recursive: true);

      final files = <File>[];
      for (var i = 0; i < rects.length; i++) {
        final r = rects[i];
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawImageRect(
          image,
          ui.Rect.fromLTWH(
            r.left.toDouble(),
            r.top.toDouble(),
            r.width.toDouble(),
            r.height.toDouble(),
          ),
          ui.Rect.fromLTWH(0, 0, r.width.toDouble(), r.height.toDouble()),
          Paint()..filterQuality = FilterQuality.high,
        );
        final picture = recorder.endRecording();
        final piece = await picture.toImage(r.width, r.height);
        final data = await piece.toByteData(format: ui.ImageByteFormat.png);
        picture.dispose();
        piece.dispose();
        if (data == null) continue;

        final name = '${(i + 1).toString().padLeft(2, '0')}.png';
        final file = File(p.join(outDir.path, name));
        await file.writeAsBytes(data.buffer.asUint8List());
        files.add(file);
      }

      if (!mounted) return;
      setState(() {
        _pieces = files;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '切图失败：$e';
        _busy = false;
      });
    }
  }

  Future<void> _saveAll() async {
    if (_pieces.isEmpty) return;
    setState(() => _busy = true);
    var ok = 0;
    String? failure;
    for (final f in _pieces) {
      try {
        await Gal.putImage(f.path);
        ok++;
      } catch (e) {
        failure ??= '$e';
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);

    if (ok == _pieces.length) {
      _toast('已保存 $ok 张到相册');
    } else if (ok == 0) {
      _toast('保存失败：${failure ?? '未知原因'}');
    } else {
      // 部分成功也要如实说，不能报「已保存」让人以为全好了。
      _toast('只保存了 $ok / ${_pieces.length} 张，其余失败：${failure ?? '未知原因'}');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final image = _decoded;
    return LocalToolCard(
      title: '九宫格切图',
      subtitle: '无损按网格切开，行数列数可调，适合多图排版',
      icon: Icons.grid_on_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '把一张图按网格切开，适合发朋友圈 / 小红书的多图排版。'
            '切图是无损裁切：不缩放、不补边，几块拼回去与原图逐像素一致。',
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: AppTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.image_outlined),
            label: Text(_source == null ? '选择图片' : '换一张'),
          ),
          if (_busy) const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppTokens.danger)),
          ],
          if (image != null) ...[
            const SizedBox(height: 16),
            Text(
              '原图 ${image.width} × ${image.height}',
              style: TextStyle(fontSize: 12, color: AppTokens.textTertiary),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('行'),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: _rows.toDouble(),
                    min: 1,
                    max: 6,
                    divisions: 5,
                    label: '$_rows',
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                            _rows = v.round();
                            _pieces = const [];
                          }),
                  ),
                ),
                Text('$_rows'),
              ],
            ),
            Row(
              children: [
                const Text('列'),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: _cols.toDouble(),
                    min: 1,
                    max: 6,
                    divisions: 5,
                    label: '$_cols',
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                            _cols = v.round();
                            _pieces = const [];
                          }),
                  ),
                ),
                Text('$_cols'),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _cut,
              icon: const Icon(Icons.grid_on_rounded),
              label: Text('切成 ${_rows * _cols} 块'),
            ),
          ],
          if (_pieces.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              '切好了，共 ${_pieces.length} 块（点缩略图看大图）',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _cols.clamp(1, 6),
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                childAspectRatio: _aspectFor(image),
              ),
              itemCount: _pieces.length,
              itemBuilder: (context, i) => GestureDetector(
                onTap: () => _preview(_pieces[i]),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(_pieces[i], fit: BoxFit.cover),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _saveAll,
              icon: const Icon(Icons.download_rounded),
              label: Text('全部保存到相册（${_pieces.length} 张）'),
            ),
          ],
        ],
      ),
    );
  }

  /// 缩略图格子按「块」的真实长宽比排，避免正方形格子把长图压扁。
  double _aspectFor(ui.Image? image) {
    if (image == null || _rows <= 0 || _cols <= 0) return 1;
    final w = image.width / _cols;
    final h = image.height / _rows;
    if (h <= 0) return 1;
    return w / h;
  }

  void _preview(File file) {
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
