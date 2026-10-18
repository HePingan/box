import 'dart:io';

import 'package:flutter/material.dart';

import '../../../design_system/app_tokens.dart';
import '../domain/image_tool_convert.dart';
import 'image_tool_scaffold.dart';
import 'local_tool_panels.dart';

/// 格式转换面板。
///
/// JPEG 不支持透明：源图带 alpha 时必须**明确**告诉用户会怎么处理
/// （铺白底 / 铺黑底 / 换成 PNG），而不是悄悄丢掉透明通道。
class ImageConvertPanelBody extends StatefulWidget {
  const ImageConvertPanelBody({super.key});

  @override
  State<ImageConvertPanelBody> createState() => _ImageConvertPanelBodyState();
}

class _ImageConvertPanelBodyState extends State<ImageConvertPanelBody> {
  ConvertFormat _format = ConvertFormat.jpg;
  FlattenColor _flatten = FlattenColor.white;
  String? _lastOutcome;

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: '格式转换',
      subtitle: 'PNG / JPEG / WebP / BMP 互转，透明的处理方式由你定',
      icon: Icons.swap_horiz_rounded,
      child: ImageToolScaffold(
        title: '格式转换',
        subtitle: '选一张图转成其它格式。透明图转 JPEG 需要选一个底色 —— '
            'JPEG 没有透明通道，不选就等于随机丢透明，所以这里必须让你看见。',
        icon: Icons.swap_horiz_rounded,
        pickLimit: 1,
        processLabel: '转换',
        controls: (ctx) => _controls(ctx),
        onProcess: _process,
      ),
    );
  }

  Widget _controls(BuildContext context) {
    // 只有会丢透明的目标格式才显示底色选项：给 PNG 也显示是噪音。
    final needsFlatten = _format.dropsAlpha;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '目标格式',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppTokens.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final f in ConvertFormat.values)
              ChoiceChip(
                label: Text(f.label, style: const TextStyle(fontSize: 12.5)),
                selected: _format == f,
                onSelected: (v) {
                  if (!v) return;
                  setState(() => _format = f);
                },
              ),
          ],
        ),
        if (needsFlatten) ...[
          const SizedBox(height: 14),
          Text(
            '透明区域的底色',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final c in FlattenColor.values)
                ChoiceChip(
                  label: Text(c.label, style: const TextStyle(fontSize: 12.5)),
                  selected: _flatten == c,
                  onSelected: (v) {
                    if (!v) return;
                    setState(() => _flatten = c);
                  },
                ),
            ],
          ),
        ],
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

    final result = ImageToolConvert.run(
      image: decoded,
      format: _format,
      flatten: _flatten,
    );

    final out = await writeImageToolResult(
      result.bytes,
      'converted_${DateTime.now().millisecondsSinceEpoch}.${result.extension}',
    );
    if (mounted) {
      setState(() {
        final note = result.hadAlpha && _format.dropsAlpha
            ? '（原图有透明区域，已铺${_flatten.label}底）'
            : '';
        _lastOutcome = '已转成 ${_format.label}：'
            '${result.width}×${result.height}$note';
      });
    }
    return [out];
  }
}
