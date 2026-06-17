import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_cards.dart';

import '../../domain/image_generator_models.dart';
import '../../domain/image_generator_preflight.dart';
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
    required this.platformBaseUrlController,
    required this.accessMode,
    required this.quickProfiles,
    required this.availableModels,
    required this.totalModelCount,
    required this.showingAllModels,
    required this.loadingModels,
    required this.modelListError,
    required this.onApplyQuickProfile,
    required this.onResetDraft,
    required this.onFetchModels,
    required this.onApplyModel,
    required this.onAccessModeChanged,
    required this.onToggleShowAllModels,
    required this.platformAccountLabel,
    required this.onReloadAccount,
  });

  final TextEditingController baseUrlController;
  final TextEditingController apiKeyController;
  final TextEditingController modelController;
  final TextEditingController platformBaseUrlController;
  final ImageGeneratorAccessMode accessMode;
  final List<ImageApiQuickProfile> quickProfiles;
  final List<String> availableModels;
  final int totalModelCount;
  final bool showingAllModels;
  final bool loadingModels;
  final String? modelListError;
  final ValueChanged<ImageApiQuickProfile> onApplyQuickProfile;
  final VoidCallback onResetDraft;
  final VoidCallback onFetchModels;
  final ValueChanged<String> onApplyModel;
  final ValueChanged<ImageGeneratorAccessMode> onAccessModeChanged;
  final VoidCallback? onToggleShowAllModels;
  final String? platformAccountLabel;
  final VoidCallback onReloadAccount;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Icons.tune_rounded,
            title: '接口配置',
            subtitle: accessMode == ImageGeneratorAccessMode.ownKey
                ? '自带 Key 直连接口；API Key 不保存'
                : '平台额度通过后端代理调用，前端不内置管理员 Key',
            trailing: TextButton.icon(
              onPressed: onResetDraft,
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('重置'),
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<ImageGeneratorAccessMode>(
            segments: ImageGeneratorAccessMode.values
                .map(
                  (mode) => ButtonSegment<ImageGeneratorAccessMode>(
                    value: mode,
                    label: Text(mode.label),
                    icon: Icon(
                      mode == ImageGeneratorAccessMode.ownKey
                          ? Icons.key_rounded
                          : Icons.admin_panel_settings_rounded,
                    ),
                  ),
                )
                .toList(),
            selected: {accessMode},
            onSelectionChanged: (values) => onAccessModeChanged(values.first),
          ),
          const SizedBox(height: 12),
          if (accessMode == ImageGeneratorAccessMode.ownKey) ...[
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
          ] else ...[
            TextField(
              controller: platformBaseUrlController,
              decoration: const InputDecoration(
                labelText: '平台服务地址',
                hintText: 'https://your-domain.com，例如后端额度代理',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: AppStatusPill(
                    label: platformAccountLabel == null
                        ? '未登录 Box 账号'
                        : '当前账号：$platformAccountLabel',
                    icon: platformAccountLabel == null
                        ? Icons.account_circle_outlined
                        : Icons.verified_user_rounded,
                    color: platformAccountLabel == null
                        ? AppTokens.warning
                        : AppTokens.success,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onReloadAccount,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('同步账号'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '平台额度模式会请求 /api/image/quota、/api/image/models、/api/image/generate；管理员 Key 必须只保存在后端。',
              style: TextStyle(color: AppTokens.textSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: modelController,
            decoration: InputDecoration(
              labelText: '模型',
              hintText: 'gpt-image-1',
              suffixIcon: IconButton(
                tooltip: '复制模型名',
                onPressed: () {
                  final text = modelController.text.trim();
                  if (text.isNotEmpty) {
                    Clipboard.setData(ClipboardData(text: text));
                  }
                },
                icon: const Icon(Icons.copy_rounded),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: loadingModels ? null : onFetchModels,
                  icon: loadingModels
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_sync_rounded, size: 18),
                  label: Text(
                    loadingModels
                        ? '获取中'
                        : accessMode == ImageGeneratorAccessMode.ownKey
                        ? '获取模型列表'
                        : '获取平台模型',
                  ),
                ),
              ),
              if (totalModelCount > 0) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onToggleShowAllModels,
                  child: Text(
                    showingAllModels ? '只看推荐' : '全部 $totalModelCount',
                  ),
                ),
              ],
            ],
          ),
          if (modelListError != null) ...[
            const SizedBox(height: 8),
            Text(
              modelListError!,
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (availableModels.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              showingAllModels ? '全部模型（点击填入）' : '推荐生图模型（点击填入）',
              style: const TextStyle(
                color: AppTokens.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: availableModels
                  .map(
                    (model) => ActionChip(
                      avatar: const Icon(Icons.smart_toy_outlined, size: 16),
                      label: Text(model),
                      tooltip: model,
                      onPressed: () => onApplyModel(model),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class ImageGeneratorPlatformQuotaCard extends StatelessWidget {
  const ImageGeneratorPlatformQuotaCard({
    super.key,
    required this.quota,
    required this.error,
    required this.platformBaseUrl,
    required this.accountLabel,
    required this.onRefresh,
  });

  final ImagePlatformQuota? quota;
  final String? error;
  final String platformBaseUrl;
  final String? accountLabel;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final item = quota;
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Icons.account_balance_wallet_rounded,
            title: '平台额度',
            subtitle: platformBaseUrl.isEmpty
                ? '请先填写平台服务地址'
                : '由后端统一保管管理员 Key、鉴权、扣减额度',
            trailing: FilledButton.tonalIcon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('刷新额度'),
            ),
          ),
          const SizedBox(height: 12),
          if (error != null && error!.trim().isNotEmpty) ...[
            Text(
              error!,
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppStatusPill(
                label: accountLabel == null ? '账号：未登录' : '账号：$accountLabel',
                icon: accountLabel == null
                    ? Icons.account_circle_outlined
                    : Icons.verified_user_rounded,
                color: accountLabel == null
                    ? AppTokens.warning
                    : AppTokens.success,
              ),
              AppStatusPill(
                label: item == null ? '剩余额度：未知' : '剩余额度：${item.remaining}',
                icon: Icons.bolt_rounded,
                color: item == null || item.hasQuota
                    ? AppTokens.success
                    : Colors.red,
              ),
              AppStatusPill(
                label: item == null ? '今日已用：未知' : '今日已用：${item.usedToday}',
                icon: Icons.today_rounded,
                color: AppTokens.primaryBlue,
              ),
              AppStatusPill(
                label: item == null ? '每日额度：未知' : '每日额度：${item.dailyLimit}',
                icon: Icons.event_available_rounded,
                color: AppTokens.violet,
              ),
            ],
          ),
          if (item?.message.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 10),
            Text(
              item!.message,
              style: const TextStyle(color: AppTokens.textSecondary),
            ),
          ],
          const SizedBox(height: 10),
          const Text(
            '安全说明：前端不会内置管理员 Key；真实扣费、限流、用户鉴权必须由平台后端完成。',
            style: TextStyle(color: AppTokens.textSecondary, fontSize: 12),
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

class ImageGeneratorReferenceCard extends StatelessWidget {
  const ImageGeneratorReferenceCard({
    super.key,
    required this.controller,
    required this.payloadField,
    required this.onPayloadFieldChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ImageReferencePayloadField payloadField;
  final ValueChanged<ImageReferencePayloadField> onPayloadFieldChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final value = controller.text.trim();
    final hasUrl = value.isNotEmpty;
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Icons.photo_filter_rounded,
            title: '参考图 / 图生图（实验）',
            subtitle: '选择字段后，请求 JSON 会携带公网参考图 URL',
            trailing: hasUrl
                ? TextButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    label: const Text('清空'),
                  )
                : null,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: '参考图 URL（可选）',
              hintText: 'https://.../reference.png，用于后续图生图/风格参考',
            ),
          ),
          const SizedBox(height: 10),
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
                ? '生成时会附加 JSON 字段：${payloadField.wireName} = 当前参考图 URL。'
                : '当前仅保存和预览参考图，不会发送给接口。',
            style: const TextStyle(
              color: AppTokens.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          if (hasUrl)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                value,
                width: double.infinity,
                height: 180,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  height: 110,
                  alignment: Alignment.center,
                  color: const Color(0xFFEFF3F9),
                  child: const Text('参考图预览失败，但 URL 会保存在草稿中'),
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE7ECF5)),
              ),
              child: const Text(
                '填写公网可访问图片 URL，并选择 image/reference_image/input_image 等中转兼容字段；不发送时仅作为草稿预览。',
                style: TextStyle(color: AppTokens.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

class ImageGeneratorRequestPreviewCard extends StatelessWidget {
  const ImageGeneratorRequestPreviewCard({
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
    return _SurfaceCard(
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        initiallyExpanded: false,
        leading: const CircleAvatar(
          radius: 18,
          backgroundColor: Color(0xFFEDE9FE),
          child: Icon(
            Icons.fact_check_outlined,
            color: AppTokens.violet,
            size: 19,
          ),
        ),
        title: const Text(
          '请求预览 / 预检',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: AppTokens.textPrimary,
          ),
        ),
        subtitle: const Text('本地静态检查，不真实请求接口，不会消耗额度'),
        children: [
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: onCopyRequestJson,
                  icon: const Icon(Icons.copy_all_rounded, size: 18),
                  label: const Text('复制请求 JSON'),
                ),
                const AppStatusPill(
                  label: 'Key 已隐藏',
                  icon: Icons.visibility_off_outlined,
                  color: AppTokens.success,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _CodePreview(label: 'Endpoint', content: endpoint),
          const SizedBox(height: 10),
          const _CodePreview(label: 'Authorization', content: 'Bearer ****'),
          const SizedBox(height: 10),
          _CodePreview(label: 'JSON Body', content: requestJson, maxLines: 12),
          const SizedBox(height: 12),
          ...preflightItems.map(_PreflightRow.new),
        ],
      ),
    );
  }
}

class _CodePreview extends StatelessWidget {
  const _CodePreview({
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
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(
            content,
            maxLines: maxLines,
            style: const TextStyle(
              color: Color(0xFFE2E8F0),
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class _PreflightRow extends StatelessWidget {
  const _PreflightRow(this.item);

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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.message,
              style: const TextStyle(
                color: AppTokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ImageGeneratorDiagnosticsCard extends StatelessWidget {
  const ImageGeneratorDiagnosticsCard({
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
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Icons.troubleshoot_rounded,
            title: '最近一次请求诊断',
            subtitle: item == null
                ? '生成后显示 endpoint、状态码、返回摘要，便于截图排查'
                : '${item.timeLabel} · ${item.statusLabel}',
          ),
          const SizedBox(height: 12),
          if (item == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE7ECF5)),
              ),
              child: const Text(
                '暂无真实请求记录。请求预览不会消耗额度，诊断卡只记录本页最近一次真实生成结果。',
                style: TextStyle(color: AppTokens.textSecondary),
              ),
            )
          else ...[
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.statusLabel,
                    style: TextStyle(color: color, fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  item.timeLabel,
                  style: const TextStyle(
                    color: AppTokens.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _CodePreview(label: 'Endpoint', content: item.endpoint),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppStatusPill(
                  label: '参考图：${item.referenceLabel}',
                  icon: Icons.photo_filter_rounded,
                  color: AppTokens.primaryBlue,
                ),
                if (item.success)
                  AppStatusPill(
                    label: '图片 ${item.imageCount} 张',
                    icon: Icons.image_rounded,
                    color: AppTokens.success,
                  ),
                if (item.success && item.resultFormat.isNotEmpty)
                  AppStatusPill(
                    label: item.resultFormat,
                    icon: Icons.link_rounded,
                    color: AppTokens.violet,
                  ),
              ],
            ),
            if (!item.success && item.message.isNotEmpty) ...[
              const SizedBox(height: 10),
              _CodePreview(label: '错误', content: item.message, maxLines: 6),
            ],
            if (item.rawPreview.isNotEmpty) ...[
              const SizedBox(height: 10),
              _CodePreview(
                label: '原始响应摘要',
                content: item.rawPreview,
                maxLines: 5,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: onCopyDiagnostics,
                  icon: const Icon(Icons.assignment_rounded, size: 18),
                  label: const Text('复制诊断信息'),
                ),
                OutlinedButton.icon(
                  onPressed: onCopyRequestJson,
                  icon: const Icon(Icons.copy_all_rounded, size: 18),
                  label: const Text('复制请求 JSON'),
                ),
              ],
            ),
          ],
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
    required this.currentPrompt,
    required this.currentNegativePrompt,
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
  final String currentPrompt;
  final String currentNegativePrompt;

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
          if (loading) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTokens.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppTokens.warning.withValues(alpha: 0.3),
                ),
              ),
              child: const Text(
                '⏳ 图片生成通常需要 1-5 分钟，请耐心等待。超时时间已调整为 5 分钟。',
                style: TextStyle(color: AppTokens.textPrimary, fontSize: 12),
              ),
            ),
          ],
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
              (item) => _GeneratedImageTile(
                item: item,
                onCopy: onCopy,
                prompt: currentPrompt,
                negativePrompt: currentNegativePrompt,
                parameterSummary: parameterSummary,
              ),
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

class _SmartImageLoader extends StatelessWidget {
  const _SmartImageLoader({
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
      return Image.memory(
        base64Decode(url.split(',').last),
        width: double.infinity,
        height: 260,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallback(context, normalizedUrl),
      );
    }

    // On web, use native <img> to avoid CORS issues
    if (kIsWeb) {
      return _WebImageWithFallback(
        url: normalizedUrl,
        fallbackUrl: normalizedFallback,
      );
    }

    return _NetworkImageWithFallback(
      primaryUrl: normalizedUrl,
      fallbackUrl: normalizedFallback,
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
class _WebImageWithFallback extends StatefulWidget {
  const _WebImageWithFallback({required this.url, required this.fallbackUrl});

  final String url;
  final String? fallbackUrl;

  @override
  State<_WebImageWithFallback> createState() => _WebImageWithFallbackState();
}

class _WebImageWithFallbackState extends State<_WebImageWithFallback> {
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
      child: ClipRRect(
        child: Image.network(
          _currentUrl,
          width: double.infinity,
          height: 260,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            if (!_triedFallback) {
              // First error: try fallback URL
              WidgetsBinding.instance.addPostFrameCallback((_) => _onError());
              return Container(
                width: double.infinity,
                height: 260,
                color: const Color(0xFFEFF3F9),
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

class _NetworkImageWithFallback extends StatefulWidget {
  const _NetworkImageWithFallback({
    required this.primaryUrl,
    required this.fallbackUrl,
  });

  final String primaryUrl;
  final String? fallbackUrl;

  @override
  State<_NetworkImageWithFallback> createState() =>
      _NetworkImageWithFallbackState();
}

class _NetworkImageWithFallbackState extends State<_NetworkImageWithFallback> {
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
    return LayoutBuilder(
      builder: (context, constraints) {
        return Image.network(
          _currentUrl,
          width: double.infinity,
          height: 260,
          fit: BoxFit.cover,
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return Container(
              width: double.infinity,
              height: 260,
              color: const Color(0xFFEFF3F9),
              child: Center(
                child: CircularProgressIndicator(
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded /
                            progress.expectedTotalBytes!
                      : null,
                ),
              ),
            );
          },
          errorBuilder: (_, __, ___) {
            if (!_triedFallback && widget.fallbackUrl != null) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _tryFallback(),
              );
              return Container(
                width: double.infinity,
                height: 260,
                color: const Color(0xFFEFF3F9),
                child: const Center(child: CircularProgressIndicator()),
              );
            }
            return _buildFallback(context);
          },
        );
      },
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

class _GeneratedImageTile extends StatelessWidget {
  const _GeneratedImageTile({
    required this.item,
    required this.onCopy,
    required this.prompt,
    required this.negativePrompt,
    required this.parameterSummary,
  });

  final GeneratedImageResult item;
  final ValueChanged<String> onCopy;
  final String prompt;
  final String negativePrompt;
  final String parameterSummary;

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
            child: _SmartImageLoader(
              url: item.image,
              isDataUrl: item.isDataUrl,
              fallbackUrl: item.rawUrl,
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
          if (item.isDataUrl)
            const Text(
              '提示：data URL 内容较长，复制 Markdown/HTML 可能不适合粘贴到聊天窗口。',
              style: TextStyle(color: AppTokens.textSecondary, fontSize: 12),
            ),
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
              OutlinedButton.icon(
                onPressed: () => onCopy('![](${item.image})'),
                icon: const Icon(Icons.integration_instructions_rounded),
                label: const Text('复制 Markdown'),
              ),
              OutlinedButton.icon(
                onPressed: () => onCopy(
                  '<img src="${item.image}" alt="AI generated image" />',
                ),
                icon: const Icon(Icons.code_rounded),
                label: const Text('复制 HTML'),
              ),
              OutlinedButton.icon(
                onPressed: () => onCopy(_buildShareText()),
                icon: const Icon(Icons.description_outlined),
                label: const Text('复制参数'),
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

  String _buildShareText() {
    final buffer = StringBuffer()
      ..writeln('Prompt:')
      ..writeln(prompt.isEmpty ? '（空）' : prompt)
      ..writeln()
      ..writeln('参数: $parameterSummary')
      ..writeln('图片: ${item.image}');
    if (negativePrompt.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Negative prompt:')
        ..writeln(negativePrompt.trim());
    }
    if (item.revisedPrompt != null && item.revisedPrompt!.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('修订提示词:')
        ..writeln(item.revisedPrompt!.trim());
    }
    return buffer.toString().trim();
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
                    headers: {'Origin': ''},
                    errorBuilder: (_, __, ___) => Container(
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
