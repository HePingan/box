import 'dart:io';

import 'package:flutter/material.dart';
import '../../../design_system/app_tokens.dart';
import '../domain/image_tool_compress.dart';
import 'image_tool_scaffold.dart';
import 'local_tool_panels.dart';

/// 图片压缩面板。
///
/// 分工：参数决策与编码在 [ImageToolCompress]（纯函数，单测覆盖），
/// 这里只收参数、调它、把结果交回底座去预览与保存。
class ImageCompressPanelBody extends StatefulWidget {
  const ImageCompressPanelBody({super.key});

  @override
  State<ImageCompressPanelBody> createState() => _ImageCompressPanelBodyState();
}

class _ImageCompressPanelBodyState extends State<ImageCompressPanelBody> {
  CompressPreset _preset = CompressPreset.balanced;

  /// 上一次处理的实况（原大小 → 压缩后大小），给用户一个"到底省了多少"。
  String? _lastOutcome;

  @override
  Widget build(BuildContext context) {
    return LocalToolCard(
      title: '图片压缩',
      subtitle: '按体积或画质目标缩小图片，压完比原图还大就保留原图',
      icon: Icons.compress_rounded,
      child: ImageToolScaffold(
        title: '图片压缩',
        subtitle: '选一张图，按预设压缩。不放大、不改变原始比例；'
            '如果压出来的文件反而更大，会直接告诉你并保留原图。',
        icon: Icons.compress_rounded,
        pickLimit: 1,
        processLabel: '开始压缩',
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
          '压缩预设',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppTokens.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        // 用 ChoiceChip 而不是 RadioListTile：后者的 groupValue/onChanged
        // 在 Flutter 3.32+ 已废弃（改用 RadioGroup），而本仓其他面板统一用
        // ChoiceChip，保持一致也更省事。
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final preset in CompressPreset.values)
              ChoiceChip(
                label: Text(preset.label, style: const TextStyle(fontSize: 12.5)),
                selected: _preset == preset,
                onSelected: (v) {
                  if (!v) return;
                  setState(() => _preset = preset);
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _preset.explanation,
          style: TextStyle(fontSize: 11.5, color: AppTokens.textTertiary),
        ),
        if (_lastOutcome != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTokens.softPanel(AppTokens.warning),
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

  /// 压缩一张图。
  ///
  /// 两条刻意的取舍：
  /// * 压完比原图大 → 返回原图文件，并把原因说清楚（用户要的是"变小"，
  ///   给他一个更大的文件等于没做到，但他也不该被告知"失败"）；
  /// * 尺寸没超限且体积已经很小时，不重编码（重编码只会引入代际损失）。
  Future<List<File>> _process(List<File> picked) async {
    final source = picked.first;
    final originalBytes = await source.length();
    final decoded = await decodePickedImage(source);

    final result = ImageToolCompress.run(
      image: decoded,
      preset: _preset,
      originalBytes: originalBytes,
    );

    if (!result.isWorthSaving) {
      if (mounted) {
        setState(() {
          _lastOutcome = '这张图压不动：压完 ${_kb(result.bytes.length)}，'
              '比原图 ${_kb(originalBytes)} 还大。已保留原图，不给你一个更大的文件。';
        });
      }
      // 返回原图：让 "保存到相册" 仍然可用（用户可能就是想把这张图存下来）。
      return [source];
    }

    final out = await writeImageToolResult(
      result.bytes,
      'compressed_${DateTime.now().millisecondsSinceEpoch}.${result.extension}',
    );
    if (mounted) {
      final saved = originalBytes - result.bytes.length;
      final pct = originalBytes == 0
          ? '0'
          : (saved / originalBytes * 100).toStringAsFixed(1);
      setState(() {
        _lastOutcome = '${_kb(originalBytes)} → ${_kb(result.bytes.length)}，'
            '省了 $pct%；输出 ${result.width}×${result.height}。';
      });
    }
    return [out];
  }

  static String _kb(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
