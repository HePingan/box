import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:box/design_system/app_tokens.dart';
import '../../domain/image_generator_preflight.dart';

import '../../domain/image_generator_models.dart';

/// Source for picking a reference image.
enum ImagePickerSource { camera, gallery, file }

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppTokens.radiusXl),
        border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
        boxShadow: AppTokens.shadowMd(),
      ),
      child: child,
    );
  }
}

/// Collapsible section header with chevron indicator.

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.expanded = true,
    this.trailing,
    this.onToggle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool expanded;
  final Widget? trailing;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: AppTokens.primaryBlue.withValues(alpha: 0.12),
              child: Icon(icon, color: AppTokens.primaryBlue, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppTokens.textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: 8),
                        trailing!,
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppTokens.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedRotation(
              turns: expanded ? 0 : -0.25,
              duration: const Duration(milliseconds: 200),
              child: const Icon(
                Icons.expand_more_rounded,
                size: 20,
                color: AppTokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A collapsible section that toggles content visibility.

class CollapsibleSection extends StatefulWidget {
  const CollapsibleSection({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
    this.initialExpanded = true,
    this.trailing,
    this.onToggle,
    this.headerPadding = const EdgeInsets.fromLTRB(0, 0, 0, 0),
    this.contentPadding = const EdgeInsets.only(top: 4),
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final bool initialExpanded;
  final Widget? trailing;
  final VoidCallback? onToggle;
  final EdgeInsetsGeometry headerPadding;
  final EdgeInsetsGeometry contentPadding;

  @override
  State<CollapsibleSection> createState() => CollapsibleSectionState();
}

class CollapsibleSectionState extends State<CollapsibleSection>
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
      if (_expanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
    widget.onToggle?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SectionHeader(
          icon: widget.icon,
          title: widget.title,
          subtitle: widget.subtitle,
          expanded: _expanded,
          trailing: widget.trailing,
          onToggle: _toggle,
        ),
        SizeTransition(
          sizeFactor: _animation,
          alignment: Alignment.topCenter,
          child: Padding(
            padding: widget.contentPadding,
            child: Column(children: widget.children),
          ),
        ),
      ],
    );
  }
}


class SmartImageLoader extends StatelessWidget {
  const SmartImageLoader({
    super.key,
    required this.url,
    required this.isDataUrl,
    this.fallbackUrl,
  });

  final String url;
  final bool isDataUrl;
  final String? fallbackUrl;

  @override
  Widget build(BuildContext context) {
    // Normalize URL: OSS providers require lowercase bucket names
    String normalizedUrl = url;
    String? normalizedFallback = fallbackUrl;
    try {
      final uri = Uri.parse(url);
      normalizedUrl = uri.replace(host: uri.host.toLowerCase()).toString();
      if (normalizedFallback != null) {
        final fallbackUri = Uri.parse(normalizedFallback);
        normalizedFallback = fallbackUri
            .replace(host: fallbackUri.host.toLowerCase())
            .toString();
      }
    } catch (_) {}

    if (isDataUrl) {
      return _buildImage(
        child: Image.memory(
          base64Decode(url.split(',').last),
          width: double.infinity,
          height: 260,
          fit: BoxFit.contain,
        ),
        errorBuilder: (_, _, _) => _buildFallback(context, normalizedUrl),
      );
    }

    // On web, try the raw (CORS-enabled) URL first, then fall back to proxy.
    // The proxy may return a 200 with placeholder/error HTML instead of
    // triggering the image errorBuilder, so we prefer the direct OSS URL.
    if (kIsWeb) {
      return WebImageWithFallback(
        // Primary: raw OSS URL (has CORS headers, loads directly in browser)
        // Fallback: proxy URL (may be needed for authenticated access)
        url: normalizedFallback ?? normalizedUrl,
        fallbackUrl: normalizedUrl,
      );
    }

    return NetworkImageWithFallback(
      primaryUrl: normalizedUrl,
      fallbackUrl: normalizedFallback,
    );
  }

  Widget _buildImage({
    required Widget child,
    required Widget Function(BuildContext, dynamic, dynamic) errorBuilder,
  }) {
    return Container(
      width: double.infinity,
      height: 260,
      color: const Color(0xFFEFF3F9),
      padding: const EdgeInsets.all(8),
      child: ClipRRect(borderRadius: BorderRadius.circular(14), child: child),
    );
  }

  Widget _buildFallback(BuildContext context, String imgUrl) {
    return Container(
      width: double.infinity,
      height: 260,
      color: const Color(0xFFEFF3F9),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.broken_image_outlined,
            size: 36,
            color: AppTokens.textSecondary,
          ),
          const SizedBox(height: 8),
          const Text(
            '图片加载失败，可能是跨域限制',
            style: TextStyle(color: AppTokens.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: imgUrl));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('图片链接已复制到剪贴板')));
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('复制链接'),
          ),
        ],
      ),
    );
  }
}

/// Web-specific image loader that avoids CORS restrictions by relying
/// on the browser's native <img> tag (which doesn't require CORS headers).
class WebImageWithFallback extends StatefulWidget {
  const WebImageWithFallback({super.key, required this.url, required this.fallbackUrl});

  final String url;
  final String? fallbackUrl;

  @override
  State<WebImageWithFallback> createState() => WebImageWithFallbackState();
}

class WebImageWithFallbackState extends State<WebImageWithFallback> {
  late String _currentUrl;
  bool _triedFallback = false;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
  }

  void _onError() {
    if (!_triedFallback &&
        widget.fallbackUrl != null &&
        widget.fallbackUrl!.isNotEmpty) {
      setState(() {
        _currentUrl = widget.fallbackUrl!;
        _triedFallback = true;
      });
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 260,
      color: const Color(0xFFEFF3F9),
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: CachedNetworkImage(
          imageUrl: _currentUrl,
          width: double.infinity,
          height: 260,
          fit: BoxFit.contain,
          placeholder: (_, _) => Container(
            color: Colors.transparent,
            child: const Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (_, _, _) {
            if (!_triedFallback) {
              // First error: try fallback URL
              WidgetsBinding.instance.addPostFrameCallback((_) => _onError());
              return Container(
                color: Colors.transparent,
                child: const Center(child: CircularProgressIndicator()),
              );
            }
            return _buildFallback(context, _currentUrl);
          },
        ),
      ),
    );
  }

  Widget _buildFallback(BuildContext context, String imgUrl) {
    return Container(
      width: double.infinity,
      height: 260,
      color: const Color(0xFFEFF3F9),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.broken_image_outlined,
            size: 36,
            color: AppTokens.textSecondary,
          ),
          const SizedBox(height: 8),
          const Text(
            '图片加载失败，可能是跨域限制',
            style: TextStyle(color: AppTokens.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: imgUrl));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('图片链接已复制到剪贴板')));
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('复制链接'),
          ),
        ],
      ),
    );
  }
}

class NetworkImageWithFallback extends StatefulWidget {
  const NetworkImageWithFallback({
    super.key,
    required this.primaryUrl,
    required this.fallbackUrl,
  });

  final String primaryUrl;
  final String? fallbackUrl;

  @override
  State<NetworkImageWithFallback> createState() =>
      NetworkImageWithFallbackState();
}

class NetworkImageWithFallbackState extends State<NetworkImageWithFallback> {
  late String _currentUrl;
  bool _triedFallback = false;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.primaryUrl;
  }

  void _tryFallback() {
    if (!_triedFallback &&
        widget.fallbackUrl != null &&
        widget.fallbackUrl!.isNotEmpty) {
      setState(() {
        _currentUrl = widget.fallbackUrl!;
        _triedFallback = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 260,
      color: const Color(0xFFEFF3F9),
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: CachedNetworkImage(
          imageUrl: _currentUrl,
          width: double.infinity,
          height: 260,
          fit: BoxFit.contain,
          placeholder: (_, _) => Container(
            color: Colors.transparent,
            child: const Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (_, _, _) {
            if (!_triedFallback && widget.fallbackUrl != null) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _tryFallback(),
              );
              return Container(
                color: Colors.transparent,
                child: const Center(child: CircularProgressIndicator()),
              );
            }
            return _buildFallback(context);
          },
        ),
      ),
    );
  }

  Widget _buildFallback(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 260,
      color: const Color(0xFFEFF3F9),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.broken_image_outlined,
            size: 36,
            color: AppTokens.textSecondary,
          ),
          const SizedBox(height: 8),
          const Text(
            '图片加载失败，可能是跨域限制',
            style: TextStyle(color: AppTokens.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.primaryUrl));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('图片链接已复制到剪贴板')));
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('复制链接'),
          ),
        ],
      ),
    );
  }
}


class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppTokens.primaryBlue.withValues(alpha: 0.12),
          child: Icon(icon, color: AppTokens.primaryBlue, size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppTokens.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: AppTokens.textSecondary),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}




class ChoiceGroup<T> extends StatelessWidget {
  const ChoiceGroup({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: values
            .map(
              (item) => DropdownMenuItem<T>(value: item, child: Text('$item')),
            )
            .toList(),
        onChanged: (item) {
          if (item != null) onChanged(item);
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Compact components for the three-block collapsible layout
// ═══════════════════════════════════════════════════════════

/// Compact params row: 4 dropdowns in a wrap, fits mobile screen.

class ParamsRow extends StatelessWidget {
  const ParamsRow({
    super.key,
    required this.size,
    required this.quality,
    required this.outputFormat,
    required this.count,
    required this.onSizeChanged,
    required this.onQualityChanged,
    required this.onOutputFormatChanged,
    required this.onCountChanged,
  });

  final String size;
  final String quality;
  final String outputFormat;
  final int count;
  final ValueChanged<String> onSizeChanged;
  final ValueChanged<String> onQualityChanged;
  final ValueChanged<String> onOutputFormatChanged;
  final ValueChanged<int> onCountChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        CompactDropdown<String>(
          label: '尺寸',
          value: size,
          values: const ['1024x1024', '1024x1536', '1536x1024'],
          onChanged: onSizeChanged,
        ),
        CompactDropdown<String>(
          label: '质量',
          value: quality,
          values: const ['auto', 'low', 'medium', 'high'],
          onChanged: onQualityChanged,
        ),
        CompactDropdown<String>(
          label: '格式',
          value: outputFormat,
          values: const ['png', 'jpeg', 'webp'],
          onChanged: onOutputFormatChanged,
        ),
        CompactDropdown<int>(
          label: '数量',
          value: count,
          values: const [1, 2, 3, 4],
          onChanged: (v) => onCountChanged(v),
        ),
      ],
    );
  }
}


class CompactDropdown<T> extends StatelessWidget {
  const CompactDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: DropdownButtonFormField<T>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 11),
          filled: true,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        items: values
            .map(
              (item) => DropdownMenuItem(
                value: item,
                child: Text('$item', style: const TextStyle(fontSize: 12)),
              ),
            )
            .toList(),
        onChanged: (item) {
          if (item != null) onChanged(item);
        },
      ),
    );
  }
}

/// Compact reference image section.
/// Compact reference image section with multi-image support.

class ImageGeneratorReferenceCard extends StatelessWidget {
  const ImageGeneratorReferenceCard({
    super.key,
    required this.urls,
    required this.payloadField,
    required this.onUrlsChanged,
    required this.onPayloadFieldChanged,
    required this.onAddUrl,
    required this.onRemoveUrl,
    this.onPickImage,
  });

  final List<String> urls;
  final ImageReferencePayloadField payloadField;
  final ValueChanged<List<String>> onUrlsChanged;
  final ValueChanged<ImageReferencePayloadField> onPayloadFieldChanged;
  final VoidCallback onAddUrl;
  final ValueChanged<int> onRemoveUrl;
  final VoidCallback? onPickImage;

  @override
  Widget build(BuildContext context) {
    final validUrls = urls.where((u) => u.trim().isNotEmpty).toList();
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            icon: Icons.photo_library_rounded,
            title: '参考图 / 图生图（实验）',
            subtitle: '支持上传多张图片，添加后自动预览；选择字段后请求 JSON 会携带 URL',
          ),
          const SizedBox(height: 12),
          // 多图片列表
          ...List.generate(urls.length, (i) {
            final url = urls[i];
            final isNotEmpty = url.trim().isNotEmpty;
            final uriValid = Uri.tryParse(url.trim());
            final isValidUrl =
                isNotEmpty &&
                uriValid != null &&
                uriValid.hasScheme &&
                (uriValid.scheme == 'http' || uriValid.scheme == 'https');
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isNotEmpty && !isValidUrl
                        ? Colors.red.shade200
                        : const Color(0xFFE7ECF5),
                  ),
                ),
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    // 预览区域
                    if (isValidUrl)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CachedNetworkImage(
                          imageUrl: url.trim(),
                          width: double.infinity,
                          height: 140,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(
                            height: 80,
                            alignment: Alignment.center,
                            color: const Color(0xFFEFF3F9),
                            child: const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          ),
                          errorWidget: (_, _, _) => Container(
                            height: 80,
                            alignment: Alignment.center,
                            color: const Color(0xFFEFF3F9),
                            child: const Text('预览失败，URL 仍会保存'),
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: TextEditingController(text: url)
                              ..selection = TextSelection.collapsed(
                                offset: url.length,
                              ),
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: '图片 URL #${i + 1}',
                              hintText: 'https://...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            style: const TextStyle(fontSize: 13),
                            onChanged: (newValue) {
                              final updated = List<String>.from(urls);
                              updated[i] = newValue;
                              onUrlsChanged(updated);
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          onPressed: () => onRemoveUrl(i),
                          icon: const Icon(Icons.close_rounded, size: 20),
                          tooltip: '移除',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.red.withValues(alpha: 0.08),
                            foregroundColor: Colors.red.shade400,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
          // 添加图片按钮（优先触发文件选择，fallback 添加空行）
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPickImage ?? onAddUrl,
                  icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
                  label: const Text('添加图片'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: '添加 URL 输入',
                child: OutlinedButton(
                  onPressed: onAddUrl,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(40, 40),
                    padding: const EdgeInsets.all(0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Icon(Icons.link_rounded, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 字段选择
          DropdownButtonFormField<ImageReferencePayloadField>(
            initialValue: payloadField,
            decoration: const InputDecoration(labelText: '请求字段'),
            items: ImageReferencePayloadField.values
                .map(
                  (field) =>
                      DropdownMenuItem(value: field, child: Text(field.label)),
                )
                .toList(),
            onChanged: (field) {
              if (field != null) onPayloadFieldChanged(field);
            },
          ),
          const SizedBox(height: 8),
          Text(
            payloadField.shouldSend
                ? validUrls.isEmpty
                      ? '未添加有效 URL，生成时自动切为"不发送"。'
                      : '生成时会附加 JSON 字段：${payloadField.wireName} = ${validUrls.length > 1 ? "[${validUrls.length} 张图片 URL]" : "当前图片 URL"}。'
                : '当前仅保存和预览参考图，不会发送给接口。',
            style: const TextStyle(
              color: AppTokens.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}


class CompactThumbnailImage extends StatefulWidget {
  const CompactThumbnailImage({
    super.key,
    required this.primaryUrl,
    required this.rawUrl,
  });
  final String primaryUrl;
  final String? rawUrl;

  @override
  State<CompactThumbnailImage> createState() => CompactThumbnailImageState();
}

class CompactThumbnailImageState extends State<CompactThumbnailImage> {
  late String _currentUrl;
  bool _triedFallback = false;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.primaryUrl;
  }

  bool get _isDataUrl => _currentUrl.startsWith('data:image/');

  @override
  Widget build(BuildContext context) {
    // Handle data URIs directly (no retry needed)
    if (_isDataUrl) {
      try {
        final base64Data = _currentUrl.split(',').last;
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.memory(
            base64Decode(base64Data),
            width: 60,
            height: 60,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _buildPlaceholder(),
          ),
        );
      } catch (_) {
        return _buildPlaceholder();
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CachedNetworkImage(
        imageUrl: _currentUrl,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        httpHeaders: const {'Origin': ''},
        placeholder: (_, _) => _buildPlaceholder(),
        errorWidget: (_, _, _) {
          // Auto-retry with raw URL on first failure
          if (!_triedFallback &&
              widget.rawUrl != null &&
              widget.rawUrl!.isNotEmpty) {
            setState(() {
              _currentUrl = widget.rawUrl!;
              _triedFallback = true;
            });
            // Return a temporary placeholder while the new image loads
            return _buildPlaceholder();
          }
          return _buildPlaceholder();
        },
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFFEFF3F9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(
        Icons.image_outlined,
        size: 24,
        color: AppTokens.textSecondary,
      ),
    );
  }
}

/// Compact request preview card (collapsed by default).

class CodeBlock extends StatelessWidget {
  const CodeBlock({
    super.key,
    required this.label,
    required this.content,
    this.maxLines = 3,
  });
  final String label;
  final String content;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTokens.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            content,
            maxLines: maxLines,
            style: const TextStyle(
              color: Color(0xFFE2E8F0),
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}


class PreflightRowCompact extends StatelessWidget {
  const PreflightRowCompact(this.item, {super.key});
  final ImageGeneratorPreflightItem item;

  @override
  Widget build(BuildContext context) {
    final icon = switch (item.level) {
      ImageGeneratorPreflightLevel.ok => Icons.check_circle_rounded,
      ImageGeneratorPreflightLevel.warning => Icons.warning_amber_rounded,
      ImageGeneratorPreflightLevel.error => Icons.error_rounded,
    };
    final color = switch (item.level) {
      ImageGeneratorPreflightLevel.ok => AppTokens.success,
      ImageGeneratorPreflightLevel.warning => AppTokens.warning,
      ImageGeneratorPreflightLevel.error => Colors.red,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              item.message,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
