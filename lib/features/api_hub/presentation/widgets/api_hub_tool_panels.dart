import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_cards.dart';

import '../../domain/public_api_models.dart';
import 'api_hub_widgets.dart';

class ApiHubCurrencyPanel extends StatelessWidget {
  const ApiHubCurrencyPanel({
    super.key,
    required this.amountController,
    required this.from,
    required this.to,
    required this.converted,
    required this.rates,
    required this.onFromChanged,
    required this.onToChanged,
    required this.onSubmit,
  });

  final TextEditingController amountController;
  final String from;
  final String to;
  final double? converted;
  final Map<String, double> rates;
  final ValueChanged<String> onFromChanged;
  final ValueChanged<String> onToChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final codes = const ['USD', 'CNY', 'EUR', 'JPY', 'HKD', 'GBP'];
    return ApiHubPanel(
      title: 'Frankfurter 汇率换算',
      subtitle: '免费外汇接口，适合工具页汇率能力',
      icon: Icons.currency_exchange_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '金额'),
                  onSubmitted: (_) => onSubmit(),
                ),
              ),
              const SizedBox(width: 8),
              ApiHubCurrencyDropDown(
                value: from,
                codes: codes,
                onChanged: onFromChanged,
              ),
              const SizedBox(width: 8),
              ApiHubCurrencyDropDown(
                value: to,
                codes: codes,
                onChanged: onToChanged,
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onSubmit,
            icon: const Icon(Icons.sync_alt_rounded),
            label: const Text('换算'),
          ),
          const SizedBox(height: 14),
          Text(
            converted == null
                ? '暂无换算结果'
                : '${amountController.text} $from ≈ ${converted!.toStringAsFixed(2)} $to',
            style: const TextStyle(
              color: AppTokens.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: rates.entries
                .map(
                  (e) => AppStatusPill(
                    label: '${e.key} ${e.value.toStringAsFixed(2)}',
                    icon: Icons.trending_up_rounded,
                    color: AppTokens.emerald,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class ApiHubHolidayPanel extends StatelessWidget {
  const ApiHubHolidayPanel({super.key, required this.holidays});

  final List<HolidayResult> holidays;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final upcoming = holidays.where((item) {
      final date = DateTime.tryParse(item.date);
      return date != null &&
          !date.isBefore(DateTime(now.year, now.month, now.day));
    }).toList();
    return ApiHubPanel(
      title: 'Nager.Date 节假日',
      subtitle: '${now.year} 年中国公开节假日，首页工作台可复用',
      icon: Icons.event_available_rounded,
      child: Column(
        children: [
          if (holidays.isEmpty)
            const AppEmptyState(
              title: '暂无节假日数据',
              message: '接口可能暂未提供当前地区',
              icon: Icons.event_busy_rounded,
            )
          else
            ...(upcoming.isEmpty ? holidays : upcoming).take(8).map((item) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: AppTokens.orange.withValues(alpha: 0.12),
                  child: const Icon(
                    Icons.event_available_rounded,
                    color: AppTokens.orange,
                  ),
                ),
                title: Text(item.localName),
                subtitle: Text('${item.date} · ${item.name}'),
              );
            }),
        ],
      ),
    );
  }
}

class ApiHubWeatherPanel extends StatelessWidget {
  const ApiHubWeatherPanel({
    super.key,
    required this.latController,
    required this.lonController,
    required this.weather,
    required this.onSubmit,
  });

  final TextEditingController latController;
  final TextEditingController lonController;
  final WeatherForecastResult? weather;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final weather = this.weather;
    return ApiHubPanel(
      title: 'Open-Meteo 天气预报',
      subtitle: '输入经纬度获取 3 天天气，默认上海',
      icon: Icons.wb_cloudy_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: latController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '纬度'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: lonController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '经度'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: onSubmit, child: const Text('查询')),
            ],
          ),
          const SizedBox(height: 12),
          if (weather == null)
            const AppEmptyState(
              title: '暂无天气',
              message: '输入坐标后查询',
              icon: Icons.wb_cloudy_rounded,
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppStatusPill(
                  label:
                      '当前 ${weather.currentTemperature?.toStringAsFixed(1) ?? '--'}°C',
                  icon: Icons.thermostat_rounded,
                  color: AppTokens.primaryBlue,
                ),
                AppStatusPill(
                  label:
                      '风速 ${weather.currentWindSpeed?.toStringAsFixed(1) ?? '--'} km/h',
                  icon: Icons.air_rounded,
                  color: AppTokens.emerald,
                ),
                AppStatusPill(
                  label: weather.timezone,
                  icon: Icons.public_rounded,
                  color: AppTokens.violet,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...weather.daily.map(ApiHubWeatherDailyTile.new),
          ],
        ],
      ),
    );
  }
}

typedef ApiHubImagePresetCallback =
    void Function({
      required String size,
      required String background,
      required String foreground,
      String? text,
    });
typedef ApiHubAvatarPresetCallback =
    void Function({
      required String name,
      required String background,
      required String foreground,
    });
typedef ApiHubCoverPresetCallback =
    void Function({
      required String width,
      required String height,
      required String seed,
    });

class ApiHubShortLinkPanel extends StatelessWidget {
  const ApiHubShortLinkPanel({
    super.key,
    required this.controller,
    required this.result,
    required this.onSubmit,
    required this.onApplyPublicApisPreset,
    required this.onApplyLocalPreviewPreset,
    required this.onCopy,
    required this.onApplyQrPreset,
  });
  final TextEditingController controller;
  final ShortLinkResult? result;
  final VoidCallback onSubmit;
  final VoidCallback onApplyPublicApisPreset;
  final VoidCallback onApplyLocalPreviewPreset;
  final ValueChanged<String> onCopy;
  final ValueChanged<String> onApplyQrPreset;
  @override
  Widget build(BuildContext context) {
    final result = this.result;
    return ApiHubPanel(
      title: 'CleanURI 短链接生成',
      subtitle: '把长链接压缩为短链，再一键转二维码，适合手机分享 Web/APK/API 地址',
      icon: Icons.link_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('public-apis'),
                avatar: const Icon(Icons.code_rounded, size: 16),
                onPressed: onApplyPublicApisPreset,
              ),
              ActionChip(
                label: const Text('本机 Web 预览'),
                avatar: const Icon(Icons.phone_android_rounded, size: 16),
                onPressed: onApplyLocalPreviewPreset,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ApiHubSearchRow(
            controller: controller,
            label: '长链接，例如 https://example.com/path',
            buttonLabel: '生成短链',
            onSubmit: onSubmit,
          ),
          const SizedBox(height: 12),
          if (result == null)
            const AppEmptyState(
              title: '暂无短链接',
              message: '输入完整 URL 后生成短链；免费接口可能限流',
              icon: Icons.link_rounded,
            )
          else ...[
            _ApiHubUrlResultBlock(
              label: '短链接',
              primaryText: result.shortUrl,
              secondaryText: result.originalUrl,
              primaryFontSize: 18,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => onCopy(result.shortUrl),
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('复制短链'),
                ),
                OutlinedButton.icon(
                  onPressed: () => onApplyQrPreset(result.shortUrl),
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: const Text('转二维码'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class ApiHubQrPanel extends StatelessWidget {
  const ApiHubQrPanel({
    super.key,
    required this.textController,
    required this.sizeController,
    required this.result,
    required this.onSubmit,
    required this.onApplySizePreset,
    required this.onApplyTextPreset,
    required this.onCopyContent,
    required this.onCopyUrl,
  });
  final TextEditingController textController;
  final TextEditingController sizeController;
  final QrCodeResult? result;
  final VoidCallback onSubmit;
  final ValueChanged<String> onApplySizePreset;
  final void Function(String text, {String? size}) onApplyTextPreset;
  final ValueChanged<String> onCopyContent;
  final ValueChanged<String> onCopyUrl;
  @override
  Widget build(BuildContext context) {
    final result = this.result;
    return ApiHubPanel(
      title: 'QR Server 二维码生成',
      subtitle: '把文本、链接或 APK 下载地址生成二维码，适合手机扫码测试',
      icon: Icons.qr_code_2_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('220×220 标准'),
                avatar: const Icon(Icons.qr_code_rounded, size: 16),
                onPressed: () => onApplySizePreset('220x220'),
              ),
              ActionChip(
                label: const Text('360×360 分享'),
                avatar: const Icon(Icons.ios_share_rounded, size: 16),
                onPressed: () => onApplySizePreset('360x360'),
              ),
              ActionChip(
                label: const Text('public-apis'),
                avatar: const Icon(Icons.code_rounded, size: 16),
                onPressed: () => onApplyTextPreset(
                  'https://github.com/public-apis/public-apis',
                  size: '260x260',
                ),
              ),
              ActionChip(
                label: const Text('本机 Web 预览'),
                avatar: const Icon(Icons.phone_android_rounded, size: 16),
                onPressed: () => onApplyTextPreset('http://127.0.0.1:8080/'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: textController,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '文本 / URL'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: sizeController,
                  decoration: const InputDecoration(labelText: '尺寸'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: onSubmit, child: const Text('生成')),
            ],
          ),
          const SizedBox(height: 12),
          if (result == null)
            const AppEmptyState(
              title: '暂无二维码',
              message: '输入文本或链接后生成二维码图片',
              icon: Icons.qr_code_2_rounded,
            )
          else ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE7ECF5)),
                ),
                child: Image.network(
                  result.url,
                  width: 190,
                  height: 190,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox(
                    width: 190,
                    height: 190,
                    child: Center(child: Text('二维码预览加载失败')),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(
              result.url,
              style: const TextStyle(
                color: AppTokens.primaryBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => onCopyContent(result.text),
                  icon: const Icon(Icons.copy_all_rounded),
                  label: const Text('复制内容'),
                ),
                OutlinedButton.icon(
                  onPressed: () => onCopyUrl(result.url),
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('复制图片 URL'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class ApiHubAvatarPanel extends StatelessWidget {
  const ApiHubAvatarPanel({
    super.key,
    required this.nameController,
    required this.sizeController,
    required this.bgController,
    required this.fgController,
    required this.result,
    required this.onSubmit,
    required this.onApplyPreset,
    required this.onCopy,
    required this.onApplyQrPreset,
  });
  final TextEditingController nameController;
  final TextEditingController sizeController;
  final TextEditingController bgController;
  final TextEditingController fgController;
  final AvatarResult? result;
  final VoidCallback onSubmit;
  final ApiHubAvatarPresetCallback onApplyPreset;
  final ValueChanged<String> onCopy;
  final ValueChanged<String> onApplyQrPreset;
  @override
  Widget build(BuildContext context) {
    final result = this.result;
    return ApiHubPanel(
      title: 'UI Avatars 头像生成',
      subtitle: '国内网络实测 1 秒左右可用，按名称生成 PNG 头像',
      icon: Icons.account_circle_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('蓝色 Box'),
                avatar: const Icon(Icons.person_rounded, size: 16),
                onPressed: () => onApplyPreset(
                  name: 'Box API',
                  background: '2563eb',
                  foreground: 'ffffff',
                ),
              ),
              ActionChip(
                label: const Text('绿色 User'),
                avatar: const Icon(Icons.badge_rounded, size: 16),
                onPressed: () => onApplyPreset(
                  name: 'Mock User',
                  background: '10b981',
                  foreground: 'ffffff',
                ),
              ),
              ActionChip(
                label: const Text('深色 Dev'),
                avatar: const Icon(Icons.terminal_rounded, size: 16),
                onPressed: () => onApplyPreset(
                  name: 'Dev Tool',
                  background: '111827',
                  foreground: 'f8fafc',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: '名称 / Seed'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: sizeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '尺寸'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: bgController,
                  decoration: const InputDecoration(labelText: '背景 HEX'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: fgController,
                  decoration: const InputDecoration(labelText: '文字 HEX'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: onSubmit, child: const Text('生成')),
            ],
          ),
          const SizedBox(height: 12),
          if (result == null)
            const AppEmptyState(
              title: '暂无头像',
              message: '输入名称后生成头像 URL',
              icon: Icons.account_circle_rounded,
            )
          else ...[
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.network(
                  result.url,
                  width: 150,
                  height: 150,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 150,
                    height: 150,
                    alignment: Alignment.center,
                    color: const Color(0xFFF1F5F9),
                    child: const Text('头像预览加载失败'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(
              result.url,
              style: const TextStyle(
                color: AppTokens.primaryBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => onCopy(result.url),
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('复制 URL'),
                ),
                OutlinedButton.icon(
                  onPressed: () => onApplyQrPreset(result.url),
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: const Text('转二维码'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class ApiHubCoverPanel extends StatelessWidget {
  const ApiHubCoverPanel({
    super.key,
    required this.widthController,
    required this.heightController,
    required this.seedController,
    required this.result,
    required this.onSubmit,
    required this.onApplyPreset,
    required this.onCopy,
    required this.onApplyQrPreset,
  });
  final TextEditingController widthController;
  final TextEditingController heightController;
  final TextEditingController seedController;
  final CoverImageResult? result;
  final VoidCallback onSubmit;
  final ApiHubCoverPresetCallback onApplyPreset;
  final ValueChanged<String> onCopy;
  final ValueChanged<String> onApplyQrPreset;
  @override
  Widget build(BuildContext context) {
    final result = this.result;
    return ApiHubPanel(
      title: 'Picsum 随机封面 / 测试封面',
      subtitle: '生成可复用的横图、竖图、内容封面 URL，适合 Flutter UI 占位',
      icon: Icons.photo_size_select_actual_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('横版 640×360'),
                avatar: const Icon(Icons.crop_landscape_rounded, size: 16),
                onPressed: () => onApplyPreset(
                  width: '640',
                  height: '360',
                  seed: 'box-landscape',
                ),
              ),
              ActionChip(
                label: const Text('封面 360×540'),
                avatar: const Icon(Icons.book_rounded, size: 16),
                onPressed: () => onApplyPreset(
                  width: '360',
                  height: '540',
                  seed: 'box-cover',
                ),
              ),
              ActionChip(
                label: const Text('头像背景 512×512'),
                avatar: const Icon(Icons.square_rounded, size: 16),
                onPressed: () => onApplyPreset(
                  width: '512',
                  height: '512',
                  seed: 'box-square',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widthController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '宽度'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: heightController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '高度'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: seedController,
                  decoration: const InputDecoration(labelText: 'Seed'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: onSubmit, child: const Text('生成')),
            ],
          ),
          const SizedBox(height: 12),
          if (result == null)
            const AppEmptyState(
              title: '暂无随机封面',
              message: '选择预设或输入尺寸后生成测试封面图',
              icon: Icons.photo_size_select_actual_rounded,
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                result.url,
                width: double.infinity,
                height: 190,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  height: 150,
                  alignment: Alignment.center,
                  color: const Color(0xFFF1F5F9),
                  child: const Text('封面预览加载失败，可复制 URL 使用'),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(
              result.url,
              style: const TextStyle(
                color: AppTokens.primaryBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => onCopy(result.url),
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('复制 URL'),
                ),
                OutlinedButton.icon(
                  onPressed: () => onApplyQrPreset(result.url),
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: const Text('转二维码'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class ApiHubDummyImagePanel extends StatelessWidget {
  const ApiHubDummyImagePanel({
    super.key,
    required this.sizeController,
    required this.textController,
    required this.bgController,
    required this.fgController,
    required this.result,
    required this.onSubmit,
    required this.onApplyPreset,
    required this.onCopy,
  });
  final TextEditingController sizeController;
  final TextEditingController textController;
  final TextEditingController bgController;
  final TextEditingController fgController;
  final DummyImageResult? result;
  final VoidCallback onSubmit;
  final ApiHubImagePresetCallback onApplyPreset;
  final ValueChanged<String> onCopy;
  @override
  Widget build(BuildContext context) {
    final result = this.result;
    return ApiHubPanel(
      title: 'DummyImage 占位图生成器',
      subtitle: '生成可复制的占位图 URL，适合 UI 原型、封面占位和测试数据',
      icon: Icons.image_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('600×360 蓝底'),
                avatar: const Icon(Icons.aspect_ratio_rounded, size: 16),
                onPressed: () => onApplyPreset(
                  size: '600x360',
                  background: '2563eb',
                  foreground: 'ffffff',
                ),
              ),
              ActionChip(
                label: const Text('800×450 黑底'),
                avatar: const Icon(Icons.movie_rounded, size: 16),
                onPressed: () => onApplyPreset(
                  size: '800x450',
                  background: '111827',
                  foreground: 'ffffff',
                ),
              ),
              ActionChip(
                label: const Text('1080×1920 竖屏'),
                avatar: const Icon(Icons.phone_android_rounded, size: 16),
                onPressed: () => onApplyPreset(
                  size: '1080x1920',
                  background: 'f1f5f9',
                  foreground: '0f172a',
                  text: 'Mobile Preview',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: sizeController,
                  decoration: const InputDecoration(labelText: '尺寸，如 600x360'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: textController,
                  decoration: const InputDecoration(labelText: '图片文字'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: bgController,
                  decoration: const InputDecoration(labelText: '背景色 HEX'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: fgController,
                  decoration: const InputDecoration(labelText: '文字色 HEX'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: onSubmit, child: const Text('生成')),
            ],
          ),
          const SizedBox(height: 12),
          if (result == null)
            const AppEmptyState(
              title: '暂无占位图',
              message: '输入尺寸和文字后生成图片 URL',
              icon: Icons.image_rounded,
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                result.url,
                width: double.infinity,
                height: 180,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  height: 120,
                  alignment: Alignment.center,
                  color: const Color(0xFFF1F5F9),
                  child: const Text('图片预览加载失败，可复制 URL 使用'),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(
              result.url,
              style: const TextStyle(
                color: AppTokens.primaryBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => onCopy(result.url),
              icon: const Icon(Icons.copy_rounded),
              label: const Text('复制 URL'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ApiHubUrlResultBlock extends StatelessWidget {
  const _ApiHubUrlResultBlock({
    required this.label,
    required this.primaryText,
    this.secondaryText,
    this.primaryFontSize = 16,
  });
  final String label;
  final String primaryText;
  final String? secondaryText;
  final double primaryFontSize;
  @override
  Widget build(BuildContext context) {
    final secondaryText = this.secondaryText;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7ECF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTokens.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          SelectableText(
            primaryText,
            style: TextStyle(
              color: AppTokens.primaryBlue,
              fontSize: primaryFontSize,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (secondaryText != null) ...[
            const SizedBox(height: 8),
            Text(
              secondaryText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTokens.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
