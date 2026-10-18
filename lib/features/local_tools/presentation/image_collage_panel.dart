import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../../design_system/app_tokens.dart';
import '../domain/image_tool_collage.dart';
import 'image_tool_scaffold.dart';
import 'local_tool_panels.dart';

/// 图片拼接面板。
///
/// 选 2-9 张，按网格拼成一张。每张图**等比缩放后居中留边**，
/// 不会被拉伸 —— 拉伸会让合照里的人脸变胖，是这类工具最常见的差评。
class ImageCollagePanelBody extends StatefulWidget {
  const ImageCollagePanelBody({super.key});

  @override
  State<ImageCollagePanelBody> createState() => _ImageCollagePanelBodyState();
}

class _ImageCollagePanelBodyState extends State<ImageCollagePanelBody> {
  /// null = 自动（按张数推荐列数）。
  int? _columns;
  String? _lastOutcome;

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: '图片拼接',
      subtitle: '把 2-9 张图拼成一张网格图，等比缩放不拉伸',
      icon: Icons.grid_view_rounded,
      child: ImageToolScaffold(
        title: '图片拼接',
        subtitle: '选多张图拼成一张。每张按等比缩放后居中留边，'
            '不会为了填满格子把图拉变形。',
        icon: Icons.grid_view_rounded,
        pickLimit: 9,
        processLabel: '拼接',
        controls: (ctx) => _controls(ctx),
        onProcess: _process,
      ),
    );
  }

  Widget _controls(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '列数',
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
            ChoiceChip(
              label: const Text('自动', style: TextStyle(fontSize: 12)),
              selected: _columns == null,
              onSelected: (v) {
                if (!v) return;
                setState(() => _columns = null);
              },
            ),
            for (final c in [1, 2, 3, 4])
              ChoiceChip(
                label: Text('$c 列', style: const TextStyle(fontSize: 12)),
                selected: _columns == c,
                onSelected: (v) {
                  if (!v) return;
                  setState(() => _columns = c);
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
    final decoded = <img.Image>[];
    for (final f in picked) {
      decoded.add(await decodePickedImage(f));
    }

    final columns = _columns ?? ImageToolCollage.suggestColumns(decoded.length);
    final result = ImageToolCollage.grid(
      images: decoded,
      columns: columns,
    );

    final bytes = ImageToolCollage.encode(result.image);
    final out = await writeImageToolResult(
      bytes,
      'collage_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    if (mounted) {
      setState(() {
        _lastOutcome = '拼好了：${result.columns} 列 × ${result.rows} 行，'
            '${result.width}×${result.height}';
      });
    }
    return [out];
  }
}
