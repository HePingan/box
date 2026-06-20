import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import 'package:box/design_system/app_tokens.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:box/design_system/widgets/app_cards.dart';


import '../../domain/image_generator_models.dart';
import '../../domain/image_generator_preflight.dart';
import 'image_generator_shared_widgets.dart';

class ReferenceSection extends StatefulWidget {
  const ReferenceSection({
    super.key,
    required this.urls,
    required this.payloadField,
    required this.onUrlsChanged,
    required this.onPayloadFieldChanged,
  });

  final List<String> urls;
  final ImageReferencePayloadField payloadField;
  final ValueChanged<List<String>> onUrlsChanged;
  final ValueChanged<ImageReferencePayloadField> onPayloadFieldChanged;

  @override
  State<ReferenceSection> createState() => ReferenceSectionState();
}

class ReferenceSectionState extends State<ReferenceSection> {
  bool _expanded = true;
  bool _uploading = false;

  List<String> get _urls => widget.urls;
  void _addUrl(String url) {
    final updated = List<String>.from(_urls)..add(url);
    widget.onUrlsChanged(updated);
  }

  void _removeUrl(int index) {
    final updated = List<String>.from(_urls)..removeAt(index);
    widget.onUrlsChanged(updated);
  }

  void _addEmptyRow() {
    _addUrl('');
  }

  Future<void> _pickImage() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    try {
      final source = await showDialog<ImagePickerSource>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('选择图片来源'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          actionsPadding: const EdgeInsets.only(bottom: 8, right: 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, ImagePickerSource.camera),
              child: const Row(
                children: [
                  Icon(Icons.camera_alt_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('拍照'),
                ],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, ImagePickerSource.gallery),
              child: const Row(
                children: [
                  Icon(Icons.photo_library_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('相册'),
                ],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, ImagePickerSource.file),
              child: const Row(
                children: [
                  Icon(Icons.insert_drive_file_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('文件'),
                ],
              ),
            ),
          ],
        ),
      );
      if (source == null) return;
      String? imagePath;
      String? filePath;
      if (source == ImagePickerSource.camera ||
          source == ImagePickerSource.gallery) {
        final picked = await ImagePicker().pickImage(
          source: source == ImagePickerSource.camera
              ? ImageSource.camera
              : ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 85,
        );
        imagePath = picked?.path;
      } else {
        final result = await FilePicker.pickFiles(
          type: FileType.image,
        );
        filePath = result?.files.single.path;
      }
      final localPath = imagePath ?? filePath;
      if (localPath == null || localPath.isEmpty) return;
      if (kIsWeb) {
        _addUrl(localPath);
      } else {
        final bytes = await File(localPath).readAsBytes();
        final b64 = base64Encode(bytes);
        final ext = localPath.split('.').last.toLowerCase();
        final mime = ext == 'jpg' || ext == 'jpeg'
            ? 'image/jpeg'
            : ext == 'png'
            ? 'image/png'
            : ext == 'gif'
            ? 'image/gif'
            : ext == 'webp'
            ? 'image/webp'
            : 'image/png';
        final dataUri = 'data:$mime;base64,$b64';
        _addUrl(dataUri);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('已添加图片（支持 base64 参考图）')));
        }
      }
    } catch (e) {
      debugPrint('_pickImage error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('选择图片失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nonEmptyCount = _urls.where((u) => u.trim().isNotEmpty).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppTokens.primaryBlue.withValues(alpha: 0.12),
                child: const Icon(
                  Icons.photo_library_rounded,
                  color: AppTokens.primaryBlue,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          '参考图',
                          style: TextStyle(
                            color: AppTokens.textPrimary,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        if (nonEmptyCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppTokens.primaryBlue.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$nonEmptyCount 张',
                              style: const TextStyle(
                                color: AppTokens.primaryBlue,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      nonEmptyCount > 0
                          ? '已添加 $nonEmptyCount 张参考图（点击${_expanded ? "收起" : "展开"}）'
                          : '支持 URL / 上传图片',
                      style: const TextStyle(
                        color: AppTokens.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _uploading ? null : _pickImage,
                icon: _uploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_rounded, size: 20),
                tooltip: '上传图片',
                style: IconButton.styleFrom(
                  backgroundColor: AppTokens.primaryBlue.withValues(
                    alpha: 0.08,
                  ),
                  foregroundColor: AppTokens.primaryBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.expand_more_rounded, size: 16),
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          ImageGeneratorReferenceCard(
            urls: _urls,
            payloadField: widget.payloadField,
            onUrlsChanged: widget.onUrlsChanged,
            onPayloadFieldChanged: widget.onPayloadFieldChanged,
            onAddUrl: _addEmptyRow,
            onRemoveUrl: _removeUrl,
            onPickImage: _pickImage,
          ),
        ],
      ],
    );
  }
}

/// Compact generated image tile.

class GeneratedImageTileCompact extends StatelessWidget {
  const GeneratedImageTileCompact({
    super.key,
    required this.item,
    required this.onCopy,
    required this.onDownload,
    required this.prompt,
    required this.negativePrompt,
    required this.parameterSummary,
  });

  final GeneratedImageResult item;
  final ValueChanged<String> onCopy;
  final ValueChanged<String> onDownload;
  final String prompt;
  final String negativePrompt;
  final String parameterSummary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7ECF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail
          SmartImageLoader(
            url: item.image,
            isDataUrl: item.isDataUrl,
            fallbackUrl: item.rawUrl,
          ),
          if (item.revisedPrompt != null && item.revisedPrompt!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '修订: ${item.revisedPrompt}',
              style: const TextStyle(
                color: AppTokens.textSecondary,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          // Action buttons - compact row
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                onPressed: () => onDownload(item.image),
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('保存', style: TextStyle(fontSize: 12)),
              ),
              OutlinedButton.icon(
                onPressed: () => onCopy(item.image),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: Text(
                  item.isDataUrl ? '复制URL' : '复制',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (item.rawUrl != null)
                OutlinedButton.icon(
                  onPressed: () => onCopy(item.rawUrl!),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('原始', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact history section.

class HistorySectionCompact extends StatelessWidget {
  const HistorySectionCompact({
    super.key,
    required this.history,
    required this.onRestore,
    required this.onCopy,
    required this.onClear,
  });

  final List<ImageGenerationHistoryItem> history;
  final ValueChanged<ImageGenerationHistoryItem> onRestore;
  final ValueChanged<String> onCopy;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.history_rounded,
              size: 16,
              color: AppTokens.textSecondary,
            ),
            const SizedBox(width: 6),
            const Text(
              '最近生成',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            const Spacer(),
            TextButton(
              onPressed: onClear,
              child: const Text('清空', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ...history.map(
          (item) => HistoryTileCompact(
            item: item,
            onRestore: () => onRestore(item),
            onCopy: onCopy,
          ),
        ),
      ],
    );
  }
}


class HistoryTileCompact extends StatelessWidget {
  const HistoryTileCompact({
    super.key,
    required this.item,
    required this.onRestore,
    required this.onCopy,
  });

  final ImageGenerationHistoryItem item;
  final VoidCallback onRestore;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    final firstImage = item.images.isEmpty ? null : item.images.first;
    String? normalizedImage;
    try {
      if (firstImage != null) {
        final uri = Uri.parse(firstImage);
        normalizedImage = uri.replace(host: uri.host.toLowerCase()).toString();
      }
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE7ECF5)),
      ),
      child: Row(
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: firstImage == null
                ? Container(
                    width: 60,
                    height: 60,
                    color: const Color(0xFFEFF3F9),
                    child: const Icon(
                      Icons.image_not_supported_outlined,
                      size: 24,
                    ),
                  )
                : _buildThumbnail(normalizedImage!, context),
          ),
          const SizedBox(width: 8),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.prompt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_formatTime(item.createdAt)} · ${item.model} · ${item.images.length} 张',
                  style: const TextStyle(
                    color: AppTokens.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          // Actions
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_rounded, size: 18),
                onPressed: onRestore,
                tooltip: '复用',
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 16),
                onPressed: () => onCopy(item.prompt),
                tooltip: '复制',
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
  }

  Widget _buildThumbnail(String url, BuildContext ctx) {
    String? rawUrl;
    try {
      final uri = Uri.parse(url);
      if (uri.path.contains('/api/image/proxy')) {
        final extracted = uri.queryParameters['url'];
        if (extracted != null && extracted.isNotEmpty) {
          rawUrl = Uri.decodeComponent(extracted);
        }
      }
    } catch (_) {}
    String? normalizedRaw;
    if (rawUrl != null) {
      try {
        final uri = Uri.parse(rawUrl);
        normalizedRaw = uri.replace(host: uri.host.toLowerCase()).toString();
      } catch (_) {}
    }
    return GestureDetector(
      onTap: () => _showImageUrlDialog(url, ctx),
      child: CompactThumbnailImage(primaryUrl: url, rawUrl: normalizedRaw),
    );
  }

  void _showImageUrlDialog(String url, BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('图片链接'),
        content: SelectableText(url, style: const TextStyle(fontSize: 11)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('关闭'),
          ),
          OutlinedButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(dialogCtx);
              ScaffoldMessenger.of(
                ctx,
              ).showSnackBar(const SnackBar(content: Text('已复制链接')));
            },
            child: const Text('复制'),
          ),
        ],
      ),
    );
  }
}


class ImageGeneratorRequestPreviewCardCompact extends StatelessWidget {
  const ImageGeneratorRequestPreviewCardCompact({
    super.key,
    required this.endpoint,
    required this.requestJson,
    required this.preflightItems,
    required this.onCopyRequestJson,
  });

  final String endpoint;
  final String requestJson;
  final List<ImageGeneratorPreflightItem> preflightItems;
  final VoidCallback onCopyRequestJson;

  @override
  Widget build(BuildContext context) {
    return ExpandableInfoCard(
      icon: Icons.fact_check_outlined,
      title: '请求预览',
      initialExpanded: false,
      children: [
        CodeBlock(label: 'Endpoint', content: endpoint),
        const SizedBox(height: 6),
        CodeBlock(label: 'JSON Body', content: requestJson, maxLines: 8),
        const SizedBox(height: 6),
        ...preflightItems.map(PreflightRowCompact.new),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: onCopyRequestJson,
          icon: const Icon(Icons.copy_all_rounded, size: 16),
          label: const Text('复制请求 JSON'),
        ),
      ],
    );
  }
}

/// Compact diagnostics card (collapsed by default).

class ImageGeneratorDiagnosticsCardCompact extends StatelessWidget {
  const ImageGeneratorDiagnosticsCardCompact({
    super.key,
    required this.diagnostics,
    required this.onCopyDiagnostics,
    required this.onCopyRequestJson,
  });

  final ImageGeneratorRequestDiagnostics? diagnostics;
  final VoidCallback? onCopyDiagnostics;
  final VoidCallback? onCopyRequestJson;

  @override
  Widget build(BuildContext context) {
    final item = diagnostics;
    final color = item == null
        ? AppTokens.textSecondary
        : item.success
        ? AppTokens.success
        : Colors.red;
    final icon = item == null
        ? Icons.history_toggle_off_rounded
        : item.success
        ? Icons.check_circle_rounded
        : Icons.error_rounded;

    return ExpandableInfoCard(
      icon: icon,
      title: item == null ? '诊断' : '诊断 · ${item.statusLabel}',
      initialExpanded: false,
      leadingColor: color,
      children: item == null
          ? [
              const Text(
                '暂无请求记录。诊断卡记录最近一次真实生成结果。',
                style: TextStyle(color: AppTokens.textSecondary, fontSize: 11),
              ),
            ]
          : [
              CodeBlock(label: 'Endpoint', content: item.endpoint),
              const SizedBox(height: 6),
              if (!item.success && item.message.isNotEmpty)
                CodeBlock(label: '错误', content: item.message, maxLines: 4),
              if (item.rawPreview.isNotEmpty) ...[
                const SizedBox(height: 6),
                CodeBlock(label: '响应摘要', content: item.rawPreview, maxLines: 4),
              ],
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  if (onCopyDiagnostics != null)
                    OutlinedButton.icon(
                      onPressed: onCopyDiagnostics,
                      icon: const Icon(Icons.assignment_rounded, size: 16),
                      label: const Text('诊断信息'),
                    ),
                  if (onCopyRequestJson != null)
                    OutlinedButton.icon(
                      onPressed: onCopyRequestJson,
                      icon: const Icon(Icons.copy_all_rounded, size: 16),
                      label: const Text('请求 JSON'),
                    ),
                ],
              ),
            ],
    );
  }
}

/// Merged request preview + diagnostics card.

class RequestDetailsCardCompact extends StatelessWidget {
  const RequestDetailsCardCompact({
    super.key,
    required this.endpoint,
    required this.requestJson,
    required this.preflightItems,
    required this.diagnostics,
    required this.onCopyRequestJson,
    required this.onCopyDiagnostics,
    this.onCopyDiagRequestJson,
  });

  final String endpoint;
  final String requestJson;
  final List<ImageGeneratorPreflightItem> preflightItems;
  final ImageGeneratorRequestDiagnostics? diagnostics;
  final VoidCallback onCopyRequestJson;
  final VoidCallback? onCopyDiagnostics;
  final VoidCallback? onCopyDiagRequestJson;

  @override
  Widget build(BuildContext context) {
    final diagSuccess = diagnostics?.success;
    final diagColor = diagnostics == null
        ? AppTokens.textSecondary
        : diagSuccess == true
        ? AppTokens.success
        : Colors.red;
    final diagIcon = diagnostics == null
        ? Icons.history_toggle_off_rounded
        : diagSuccess == true
        ? Icons.check_circle_rounded
        : Icons.error_rounded;

    return ExpandableInfoCard(
      icon: diagIcon,
      title: diagnostics == null
          ? '请求详情'
          : '请求详情 · ${diagnostics!.statusLabel}',
      leadingColor: diagColor,
      initialExpanded: false,
      children: [
        // Preflight checks
        ...preflightItems.map(PreflightRowCompact.new),
        if (preflightItems.isNotEmpty) const SizedBox(height: 6),
        // Code blocks
        CodeBlock(label: 'Endpoint', content: endpoint),
        const SizedBox(height: 4),
        CodeBlock(label: 'JSON Body', content: requestJson, maxLines: 6),
        if (diagnostics != null) ...[
          const SizedBox(height: 6),
          CodeBlock(label: 'Endpoint', content: diagnostics!.endpoint),
          const SizedBox(height: 4),
          if (!diagnostics!.success && diagnostics!.message.isNotEmpty)
            CodeBlock(label: '错误', content: diagnostics!.message, maxLines: 4),
          if (diagnostics!.rawPreview.isNotEmpty) ...[
            const SizedBox(height: 4),
            CodeBlock(
              label: '响应摘要',
              content: diagnostics!.rawPreview,
              maxLines: 4,
            ),
          ],
        ],
        const SizedBox(height: 6),
        // Copy buttons
        Wrap(
          spacing: 6,
          children: [
            OutlinedButton.icon(
              onPressed: onCopyRequestJson,
              icon: const Icon(Icons.copy_all_rounded, size: 16),
              label: const Text('复制请求 JSON'),
            ),
            if (onCopyDiagnostics != null)
              OutlinedButton.icon(
                onPressed: onCopyDiagnostics,
                icon: const Icon(Icons.assignment_rounded, size: 16),
                label: const Text('诊断信息'),
              ),
            if (onCopyDiagRequestJson != null)
              OutlinedButton.icon(
                onPressed: onCopyDiagRequestJson,
                icon: const Icon(Icons.copy_all_rounded, size: 16),
                label: const Text('诊断 JSON'),
              ),
          ],
        ),
      ],
    );
  }
}

/// Compact platform quota card.

class ImageGeneratorPlatformQuotaCardCompact extends StatelessWidget {
  const ImageGeneratorPlatformQuotaCardCompact({
    super.key,
    required this.quota,
    required this.error,
    required this.accountLabel,
    required this.onRefresh,
  });

  final ImagePlatformQuota? quota;
  final String? error;
  final String? accountLabel;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Icon(
              Icons.account_balance_wallet_rounded,
              size: 16,
              color: AppTokens.textSecondary,
            ),
            const SizedBox(width: 6),
            const Text(
              '平台额度',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 14),
              label: const Text('刷新', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        if (error != null && error!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            error!,
            style: const TextStyle(
              color: Colors.red,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            AppStatusPill(
              label: accountLabel == null ? '未登录' : accountLabel!,
              icon: accountLabel == null
                  ? Icons.account_circle_outlined
                  : Icons.verified_user_rounded,
              color: accountLabel == null
                  ? AppTokens.warning
                  : AppTokens.success,
            ),
            AppStatusPill(
              label: quota == null ? '额度：?' : '剩: ${quota!.remaining}',
              icon: Icons.bolt_rounded,
              color: quota == null || quota!.hasQuota
                  ? AppTokens.success
                  : Colors.red,
            ),
            AppStatusPill(
              label: quota == null ? '今日：?' : '今日: ${quota!.usedToday}',
              icon: Icons.today_rounded,
              color: AppTokens.primaryBlue,
            ),
          ],
        ),
      ],
    );
  }
}

/// Generic expandable info card for request preview / diagnostics.

class ExpandableInfoCard extends StatefulWidget {
  const ExpandableInfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.initialExpanded = false,
    this.leadingColor,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final bool initialExpanded;
  final Color? leadingColor;

  @override
  State<ExpandableInfoCard> createState() => ExpandableInfoCardState();
}

class ExpandableInfoCardState extends State<ExpandableInfoCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _animation;
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initialExpanded;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    if (_expanded) _controller.value = 1;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      _expanded ? _controller.forward() : _controller.reverse();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 16,
                  color: widget.leadingColor ?? AppTokens.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more_rounded, size: 16),
                ),
              ],
            ),
          ),
        ),
        SizeTransition(
          sizeFactor: _animation,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: widget.children,
          ),
        ),
      ],
    );
  }
}


