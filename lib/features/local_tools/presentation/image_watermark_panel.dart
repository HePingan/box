import 'dart:io';

import 'package:flutter/material.dart';

import '../../../design_system/app_tokens.dart';
import '../domain/image_tool_watermark.dart';
import 'image_tool_scaffold.dart';
import 'local_tool_panels.dart';

/// 文字水印面板。
///
/// **必须在输入框下方就写明"只支持英文数字"**：位图字体没有汉字字形，
/// 输入中文会一个像素都画不出来。等用户点完"添加水印"看到空白再说，
/// 是让人重试三次才明白的那种设计。
class ImageWatermarkPanelBody extends StatefulWidget {
  const ImageWatermarkPanelBody({super.key});

  @override
  State<ImageWatermarkPanelBody> createState() =>
      _ImageWatermarkPanelBodyState();
}

class _ImageWatermarkPanelBodyState extends State<ImageWatermarkPanelBody> {
  final _textCtrl = TextEditingController(text: 'SAMPLE');
  WatermarkAnchor _anchor = WatermarkAnchor.bottomRight;
  double _opacity = 0.6;
  int _scale = 2;
  String? _lastOutcome;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: '水印添加',
      subtitle: '给照片加一行文字水印，九宫格定位、可调大小与透明度',
      icon: Icons.branding_watermark_outlined,
      child: ImageToolScaffold(
        title: '水印添加',
        subtitle: '在图片上加一行文字。字是位图字体，只支持英文、数字与常见符号。',
        icon: Icons.branding_watermark_outlined,
        pickLimit: 1,
        processLabel: '添加水印',
        controls: (ctx) => _controls(ctx),
        onProcess: _process,
      ),
    );
  }

  Widget _controls(BuildContext context) {
    final text = _textCtrl.text;
    final renders = ImageToolWatermark.textRenders(text);
    final empty = text.trim().isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _textCtrl,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: '水印文字',
            helperText: '只支持英文 / 数字 / 符号 —— 内置位图字体没有汉字字形',
            helperMaxLines: 2,
            errorText: empty
                ? '不能为空'
                : (renders ? null : '这段文字含中文等非 ASCII 字符，画出来会是一片空白'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '位置',
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
            for (final a in WatermarkAnchor.values)
              ChoiceChip(
                label: Text(a.label, style: const TextStyle(fontSize: 12)),
                selected: _anchor == a,
                onSelected: (v) {
                  if (!v) return;
                  setState(() => _anchor = a);
                },
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '字号',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppTokens.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _scale.toDouble(),
                min: 1,
                max: 3,
                divisions: 2,
                label: ['小', '中', '大'][_scale - 1],
                onChanged: (v) => setState(() => _scale = v.round()),
              ),
            ),
            Text(['小', '中', '大'][_scale - 1],
                style: const TextStyle(fontSize: 12)),
          ],
        ),
        Text(
          '不透明度 ${(_opacity * 100).round()}%',
          style: TextStyle(fontSize: 12.5, color: AppTokens.textSecondary),
        ),
        Slider(
          value: _opacity,
          min: 0.1,
          max: 1.0,
          divisions: 9,
          onChanged: (v) => setState(() => _opacity = v),
        ),
        if (_lastOutcome != null) ...[
          const SizedBox(height: 8),
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
    final text = _textCtrl.text.trim();

    final watermarked = ImageToolWatermark.apply(
      image: decoded,
      text: text,
      anchor: _anchor,
      opacity: _opacity,
      scale: _scale,
    );

    final bytes = ImageToolWatermark.encode(watermarked);
    final out = await writeImageToolResult(
      bytes,
      'watermark_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    if (mounted) {
      setState(() {
        _lastOutcome = '已加「$text」到${_anchor.label}，'
            '输出 ${watermarked.width}×${watermarked.height}';
      });
    }
    return [out];
  }
}
