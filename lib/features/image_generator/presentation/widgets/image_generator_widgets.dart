import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_cards.dart';

import '../../domain/image_generator_models.dart';
import '../../domain/image_generator_presets.dart';

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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

class ImageGeneratorHeader extends StatelessWidget {
  const ImageGeneratorHeader({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'AI 生图工坊',
                style: TextStyle(
                  color: AppTokens.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'OpenAI 兼容 Images API · 文生图增强版',
                style: TextStyle(color: AppTokens.textSecondary),
              ),
            ],
          ),
        ),
        const AppStatusPill(
          label: '插件页',
          icon: Icons.extension_rounded,
          color: AppTokens.violet,
        ),
      ],
    );
  }
}

class ImageGeneratorConfigCard extends StatelessWidget {
  const ImageGeneratorConfigCard({
    super.key,
    required this.baseUrlController,
    required this.apiKeyController,
    required this.modelController,
    required this.quickProfiles,
    required this.onApplyQuickProfile,
    required this.onResetDraft,
  });

  final TextEditingController baseUrlController;
  final TextEditingController apiKeyController;
  final TextEditingController modelController;
  final List<ImageApiQuickProfile> quickProfiles;
  final ValueChanged<ImageApiQuickProfile> onApplyQuickProfile;
  final VoidCallback onResetDraft;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Icons.tune_rounded,
            title: '接口配置',
            subtitle: 'Base URL、模型和提示词会自动记住；API Key 不保存',
            trailing: TextButton.icon(
              onPressed: onResetDraft,
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('重置'),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: quickProfiles
                .map(
                  (profile) => ActionChip(
                    avatar: const Icon(Icons.flash_on_rounded, size: 16),
                    label: Text(profile.title),
                    tooltip: profile.description,
                    onPressed: () => onApplyQuickProfile(profile),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: baseUrlController,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              hintText: 'https://api.openai.com/v1 或中转地址',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: apiKeyController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'API Key',
              hintText: 'sk-...（仅本次使用，不保存）',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: modelController,
            decoration: const InputDecoration(
              labelText: '模型',
              hintText: 'gpt-image-1',
            ),
          ),
        ],
      ),
    );
  }
}

class ImageGeneratorPromptCard extends StatelessWidget {
  const ImageGeneratorPromptCard({
    super.key,
    required this.promptController,
    required this.negativeController,
    required this.presets,
    required this.onAppendStyle,
    required this.onApplyPreset,
    required this.onOptimizePrompt,
  });

  final TextEditingController promptController;
  final TextEditingController negativeController;
  final List<ImagePromptPreset> presets;
  final ValueChanged<String> onAppendStyle;
  final ValueChanged<ImagePromptPreset> onApplyPreset;
  final VoidCallback onOptimizePrompt;

  @override
  Widget build(BuildContext context) {
    final styles = const [
      '写实摄影，柔和自然光，细节丰富',
      '二次元插画，干净线稿，高级配色',
      '赛博朋克城市，霓虹灯，电影感构图',
      '国风插画，水墨质感，东方美学',
      '产品海报，极简背景，商业摄影',
      'App 图标，圆角，3D 质感，纯色背景',
      '电商主图，白底，主体突出，高转化率',
      '社交媒体封面，强视觉中心，大胆配色',
    ];

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Icons.auto_awesome_rounded,
            title: '提示词',
            subtitle: '描述主体、风格、镜头、光线、构图和用途',
            trailing: FilledButton.tonalIcon(
              onPressed: onOptimizePrompt,
              icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
              label: const Text('优化'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 118,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: presets.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final preset = presets[index];
                return _PromptPresetCard(
                  preset: preset,
                  onTap: () => onApplyPreset(preset),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: promptController,
            minLines: 5,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Prompt',
              alignLabelWithHint: true,
              hintText: '例如：一张用于工具箱 App 的 AI 生图入口海报，蓝紫渐变，玻璃拟态，科技感...',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: styles
                .map(
                  (style) => ActionChip(
                    label: Text(style.split('，').first),
                    avatar: const Icon(Icons.add_rounded, size: 16),
                    onPressed: () => onAppendStyle(style),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: negativeController,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Negative prompt（可选）',
              hintText: '例如：低清晰度、畸形手指、文字错误、水印',
            ),
          ),
        ],
      ),
    );
  }
}

class _PromptPresetCard extends StatelessWidget {
  const _PromptPresetCard({required this.preset, required this.onTap});

  final ImagePromptPreset preset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 168,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTokens.primaryBlue.withValues(alpha: 0.10),
              AppTokens.violet.withValues(alpha: 0.10),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTokens.primaryBlue.withValues(alpha: 0.16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 18,
                  color: AppTokens.primaryBlue,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    preset.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTokens.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              preset.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTokens.textSecondary,
                fontSize: 12,
              ),
            ),
            const Spacer(),
            Text(
              '${preset.size} · ${preset.quality}',
              style: const TextStyle(
                color: AppTokens.primaryBlue,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ImageGeneratorParamsCard extends StatelessWidget {
  const ImageGeneratorParamsCard({
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
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.aspect_ratio_rounded,
            title: '生成参数',
            subtitle: '优先兼容 OpenAI Images API，中转接口如不支持会返回明确错误',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ChoiceGroup<String>(
                label: '尺寸',
                value: size,
                values: const ['1024x1024', '1024x1536', '1536x1024'],
                onChanged: onSizeChanged,
              ),
              _ChoiceGroup<String>(
                label: '质量',
                value: quality,
                values: const ['auto', 'low', 'medium', 'high'],
                onChanged: onQualityChanged,
              ),
              _ChoiceGroup<String>(
                label: '格式',
                value: outputFormat,
                values: const ['png', 'jpeg', 'webp'],
                onChanged: onOutputFormatChanged,
              ),
              _ChoiceGroup<int>(
                label: '数量',
                value: count,
                values: const [1, 2, 3, 4],
                onChanged: onCountChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ImageGeneratorResultCard extends StatelessWidget {
  const ImageGeneratorResultCard({
    super.key,
    required this.loading,
    required this.error,
    required this.results,
    required this.history,
    required this.onGenerate,
    required this.onCopy,
    required this.onRestoreHistory,
    required this.onClearHistory,
    required this.parameterSummary,
  });

  final bool loading;
  final String? error;
  final List<GeneratedImageResult> results;
  final List<ImageGenerationHistoryItem> history;
  final VoidCallback onGenerate;
  final ValueChanged<String> onCopy;
  final ValueChanged<ImageGenerationHistoryItem> onRestoreHistory;
  final VoidCallback onClearHistory;
  final String parameterSummary;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: _SectionTitle(
                  icon: Icons.image_rounded,
                  title: '生成结果',
                  subtitle: '生成后自动写入最近记录，可快速复用提示词',
                ),
              ),
              FilledButton.icon(
                onPressed: loading ? null : onGenerate,
                icon: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_fix_high_rounded),
                label: Text(loading ? '生成中' : '开始生成'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTokens.primaryBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTokens.primaryBlue.withValues(alpha: 0.18),
              ),
            ),
            child: Text(
              '当前参数：$parameterSummary',
              style: const TextStyle(
                color: AppTokens.primaryBlue,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
              ),
              child: Text(
                error!,
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (results.isEmpty)
            const AppEmptyState(
              title: '暂无图片',
              message: '填入 API Key 和 Prompt 后开始生成',
              icon: Icons.image_search_rounded,
            )
          else
            ...results.map(
              (item) => _GeneratedImageTile(item: item, onCopy: onCopy),
            ),
          const SizedBox(height: 6),
          _HistorySection(
            history: history,
            onRestore: onRestoreHistory,
            onCopy: onCopy,
            onClear: onClearHistory,
          ),
        ],
      ),
    );
  }
}

class _GeneratedImageTile extends StatelessWidget {
  const _GeneratedImageTile({required this.item, required this.onCopy});

  final GeneratedImageResult item;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7ECF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(
              item.image,
              width: double.infinity,
              height: 260,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                height: 180,
                alignment: Alignment.center,
                color: const Color(0xFFEFF3F9),
                child: const Text('图片预览失败，可复制链接检查'),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SelectableText(
            item.isDataUrl ? 'data:image/...base64（已省略显示）' : item.image,
            style: const TextStyle(
              color: AppTokens.primaryBlue,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (item.revisedPrompt != null) ...[
            const SizedBox(height: 8),
            Text(
              '修订提示词：${item.revisedPrompt}',
              style: const TextStyle(color: AppTokens.textSecondary),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => onCopy(item.image),
                icon: const Icon(Icons.copy_rounded),
                label: Text(item.isDataUrl ? '复制 data URL' : '复制图片 URL'),
              ),
              if (item.rawUrl != null)
                OutlinedButton.icon(
                  onPressed: () => onCopy(item.rawUrl!),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('复制原始链接'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({
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
    if (history.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        _SectionTitle(
          icon: Icons.history_rounded,
          title: '最近生成',
          subtitle: '保留最近 12 条，不保存 API Key',
          trailing: TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: const Text('清空'),
          ),
        ),
        const SizedBox(height: 10),
        ...history.map(
          (item) => _HistoryTile(
            item: item,
            onRestore: () => onRestore(item),
            onCopy: onCopy,
          ),
        ),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7ECF5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: firstImage == null
                ? Container(
                    width: 58,
                    height: 58,
                    color: const Color(0xFFEFF3F9),
                    child: const Icon(Icons.image_not_supported_outlined),
                  )
                : Image.network(
                    firstImage,
                    width: 58,
                    height: 58,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 58,
                      height: 58,
                      color: const Color(0xFFEFF3F9),
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.prompt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatTime(item.createdAt)} · ${item.model} · ${item.size} · ${item.images.length} 张',
                  style: const TextStyle(
                    color: AppTokens.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onRestore,
                      icon: const Icon(Icons.replay_rounded, size: 18),
                      label: const Text('复用'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => onCopy(item.prompt),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('复制 Prompt'),
                    ),
                    if (firstImage != null)
                      OutlinedButton.icon(
                        onPressed: () => onCopy(firstImage),
                        icon: const Icon(Icons.link_rounded, size: 18),
                        label: const Text('复制图链'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
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

class _ChoiceGroup<T> extends StatelessWidget {
  const _ChoiceGroup({
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
