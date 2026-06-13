import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_cards.dart';

import '../../domain/image_generator_models.dart';

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({
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
                'OpenAI 兼容 Images API · 文生图 MVP',
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
  });

  final TextEditingController baseUrlController;
  final TextEditingController apiKeyController;
  final TextEditingController modelController;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.tune_rounded,
            title: '接口配置',
            subtitle: 'API Key 仅用于当前页面请求，第一版不做持久化保存',
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
              hintText: 'sk-...',
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
    required this.onAppendStyle,
  });

  final TextEditingController promptController;
  final TextEditingController negativeController;
  final ValueChanged<String> onAppendStyle;

  @override
  Widget build(BuildContext context) {
    final styles = const [
      '写实摄影，柔和自然光，细节丰富',
      '二次元插画，干净线稿，高级配色',
      '赛博朋克城市，霓虹灯，电影感构图',
      '国风插画，水墨质感，东方美学',
      '产品海报，极简背景，商业摄影',
      'App 图标，圆角，3D 质感，纯色背景',
    ];

    return _SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.auto_awesome_rounded,
            title: '提示词',
            subtitle: '描述主体、风格、镜头、光线、构图和用途',
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
      padding: const EdgeInsets.all(16),
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
    required this.onGenerate,
    required this.onCopy,
  });

  final bool loading;
  final String? error;
  final List<GeneratedImageResult> results;
  final VoidCallback onGenerate;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: _SectionTitle(
                  icon: Icons.image_rounded,
                  title: '生成结果',
                  subtitle: '生成后可预览 URL 图片或 base64 data URL',
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

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
