import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
    this.captureKey,
    this.isNew = false,
  });

  final GeneratedImageResult item;
  final ValueChanged<String> onCopy;
  final ValueChanged<String> onDownload;
  final String prompt;
  final String negativePrompt;
  final String parameterSummary;
  final GlobalKey? captureKey;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isNew
              ? AppTokens.primaryBlue.withValues(alpha: 0.4)
              : const Color(0xFFE7ECF5),
          width: isNew ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail — tap opens lightbox
          GestureDetector(
            onTap: () => _openLightbox(context),
            child: Stack(
              children: [
                RepaintBoundary(
                  key: captureKey,
                  child: SmartImageLoader(
                    url: item.image,
                    isDataUrl: item.isDataUrl,
                    fallbackUrl: item.rawUrl,
                  ),
                ),
                // 新标记
                if (isNew)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        gradient: AppTokens.blueGradient,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: AppTokens.primaryBlue.withValues(alpha: 0.4),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                // 预览按钮（hover/触摸时可见）
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.fullscreen_rounded,
                        size: 28,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (item.revisedPrompt != null &&
              item.revisedPrompt!.isNotEmpty) ...[
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
              _ActionChip(
                icon: Icons.download_rounded,
                label: '保存',
                onTap: () => onDownload(item.rawUrl ?? item.image),
              ),
              _ActionChip(
                icon: Icons.copy_rounded,
                label: item.isDataUrl ? '复制URL' : '复制',
                onTap: () => onCopy(item.image),
              ),
              if (item.rawUrl != null)
                _ActionChip(
                  icon: Icons.open_in_new_rounded,
                  label: '原始',
                  onTap: () => onCopy(item.rawUrl!),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _openLightbox(BuildContext context) {
    // Put the raw OSS URL first (works in browser), proxy URL as fallback
    final urls = <String>[];
    if (item.rawUrl != null && item.rawUrl!.isNotEmpty) {
      urls.add(item.rawUrl!);
    }
    if (item.image != item.rawUrl) {
      urls.add(item.image);
    }
    showImageLightbox(
      context,
      urls: urls,
      onDownload: onDownload,
      onCopy: onCopy,
    );
  }
}

/// 紧凑型操作按钮 — 与卡片风格一致
class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppTokens.textSecondary),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
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
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.delete_sweep_outlined, size: 16),
              label: const Text('清空', style: TextStyle(fontSize: 11)),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7ECF5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onRestore,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 多图缩略图
            _HistoryThumbnails(
              images: item.images,
              onCopy: onCopy,
            ),
            const SizedBox(width: 10),
            // 信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.prompt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // 参数徽章
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      if (item.model.isNotEmpty)
                        _HistoryBadge(label: item.model),
                      _HistoryBadge(label: item.size),
                      if (item.quality != 'standard')
                        _HistoryBadge(label: item.quality),
                      _HistoryBadge(
                        label: _formatTimeCompact(item.createdAt),
                        icon: Icons.access_time_rounded,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 恢复按钮
            Container(
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                gradient: AppTokens.blueGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onRestore,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.restore_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTimeCompact(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.month)}-${two(dt.day)}';
  }
}

/// 多图缩略图（支持 1 张大图 / 2×2 网格）
class _HistoryThumbnails extends StatelessWidget {
  final List<String> images;
  final ValueChanged<String> onCopy;

  const _HistoryThumbnails({
    required this.images,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          color: const Color(0xFFEFF3F9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.image_not_supported_outlined, size: 28),
      );
    }

    final limited = images.take(4).toList();

    return GestureDetector(
      onTap: () => showImageLightbox(
        context,
        urls: images.map(_resolveImageUrl).toList(),
        onCopy: onCopy,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: limited.length == 1
            ? SizedBox(
                width: 88,
                height: 88,
                child: CachedNetworkImage(
                  imageUrl: _normalizeUrl(limited.first),
                  fit: BoxFit.cover,
                  placeholder: (context, url) => _thumbPlaceholder,
                  errorWidget: (context, url, error) => _thumbError,
                ),
              )
            : SizedBox(
                width: 88,
                height: 88,
                child: GridView.count(
                  crossAxisCount: 2,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  mainAxisSpacing: 1,
                  crossAxisSpacing: 1,
                  children: limited
                      .map((url) => CachedNetworkImage(
                            imageUrl: _normalizeUrl(url),
                            fit: BoxFit.cover,
                            placeholder: (context, url) => _thumbPlaceholder,
                            errorWidget: (context, url, error) => _thumbError,
                          ))
                      .toList(),
                ),
              ),
      ),
    );
  }

  /// Lowercase the host and, if the URL is a proxy (`/api/image/proxy?url=…`),
  /// extract the underlying raw OSS URL so the thumbnail loads directly.
  String _normalizeUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.path.contains('/api/image/proxy')) {
        final extracted = uri.queryParameters['url'];
        if (extracted != null && extracted.isNotEmpty) {
          return Uri.decodeComponent(extracted);
        }
      }
      return uri.replace(host: uri.host.toLowerCase()).toString();
    } catch (_) {
      return url;
    }
  }

  Widget get _thumbPlaceholder => Container(
        color: const Color(0xFFEFF3F9),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );

  Widget get _thumbError => Container(
        color: const Color(0xFFEFF3F9),
        child: const Icon(Icons.broken_image_outlined, size: 18),
      );

  /// If [url] is a proxy URL (`/api/image/proxy?url=...`), extract the
  /// underlying raw OSS URL so the lightbox loads it directly.
  static String _resolveImageUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.path.contains('/api/image/proxy')) {
        final extracted = uri.queryParameters['url'];
        if (extracted != null && extracted.isNotEmpty) {
          return Uri.decodeComponent(extracted);
        }
      }
    } catch (_) {}
    return url;
  }
}

/// 历史条目参数徽章
class _HistoryBadge extends StatelessWidget {
  final String label;
  final IconData? icon;

  const _HistoryBadge({required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: AppTokens.textTertiary),
            const SizedBox(width: 2),
          ],
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppTokens.textSecondary,
            ),
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


