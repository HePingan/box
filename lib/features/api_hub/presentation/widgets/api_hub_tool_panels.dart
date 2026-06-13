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
