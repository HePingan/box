import 'dart:io';

import 'package:flutter/material.dart';

import '../../../design_system/app_tokens.dart';
import '../domain/image_tool_wallpaper.dart';
import 'image_tool_scaffold.dart';
import 'local_tool_panels.dart';

/// 壁纸提取面板：把一张图裁成手机/平板屏幕比例。
///
/// 名字叫"提取"，做的其实是**裁出能当壁纸的那块**（不是从网上抓壁纸）。
/// 页面文案要把这件事说明白，否则用户会期待一个图库。
class ImageWallpaperPanelBody extends StatefulWidget {
  const ImageWallpaperPanelBody({super.key});

  @override
  State<ImageWallpaperPanelBody> createState() =>
      _ImageWallpaperPanelBodyState();
}

class _ImageWallpaperPanelBodyState extends State<ImageWallpaperPanelBody> {
  WallpaperAspect _aspect = WallpaperAspect.phoneTall;
  WallpaperFocus _focus = WallpaperFocus.center;
  String? _lastOutcome;

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: '壁纸提取',
      subtitle: '把一张图裁成手机 / 平板屏幕比例，选保留哪一块',
      icon: Icons.wallpaper_rounded,
      child: ImageToolScaffold(
        title: '壁纸提取',
        subtitle: '选一张图，裁成屏幕比例。手机是 9:19.5 这类细长比例，'
            '直接设成壁纸会被系统拉伸或裁掉主体，所以先在这里裁好。',
        icon: Icons.wallpaper_rounded,
        pickLimit: 1,
        processLabel: '裁剪成壁纸',
        controls: (ctx) => _controls(ctx),
        onProcess: _process,
      ),
    );
  }

  Widget _controls(BuildContext context) {
    // 原来的图片比例决定"哪些方向有意义"：横图裁竖版只能左右移。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '目标比例',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppTokens.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final a in WallpaperAspect.values)
              ChoiceChip(
                label: Text(a.label, style: const TextStyle(fontSize: 12)),
                selected: _aspect == a,
                onSelected: (v) {
                  if (!v) return;
                  setState(() => _aspect = a);
                },
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '保留位置',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppTokens.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            for (final f in WallpaperFocus.values)
              ChoiceChip(
                label: Text(f.label, style: const TextStyle(fontSize: 12)),
                selected: _focus == f,
                onSelected: (v) {
                  if (!v) return;
                  setState(() => _focus = f);
                },
              ),
          ],
        ),
        if (_lastOutcome != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTokens.softPanel(AppTokens.emerald),
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            ),
            child: Text(
              _lastOutcome!,
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ],
    );
  }

  Future<List<File>> _process(List<File> picked) async {
    final source = picked.first;
    final decoded = await decodePickedImage(source);

    final cropped = ImageToolWallpaper.crop(
      source: decoded,
      aspect: _aspect.ratio,
      focus: _focus,
    );

    final bytes = ImageToolWallpaper.encode(cropped);
    final out = await writeImageToolResult(
      bytes,
      'wallpaper_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    if (mounted) {
      setState(() {
        _lastOutcome = '已裁成 ${_aspect.label}：'
            '${cropped.width}×${cropped.height}（原图 '
            '${decoded.width}×${decoded.height}）';
      });
    }
    return [out];
  }
}
