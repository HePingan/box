import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_cards.dart';

import '../../application/public_api_registry.dart';
import '../../domain/public_api_models.dart';

class ApiHubDirectoryDetailBlock extends StatelessWidget {
  const ApiHubDirectoryDetailBlock({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7ECF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppTokens.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class ApiHubMetric extends StatelessWidget {
  const ApiHubMetric({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FD),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border: Border.all(color: const Color(0xFFE7ECF5)),
      ),
      child: Text(
        '$value $label',
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppTokens.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class ApiHubQuickChip extends StatelessWidget {
  const ApiHubQuickChip({
    super.key,
    required this.tool,
    required this.selected,
    required this.onTap,
  });

  final PublicApiToolDefinition tool;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? tool.color.withValues(alpha: 0.14)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            border: Border.all(
              color: selected
                  ? tool.color.withValues(alpha: 0.48)
                  : const Color(0xFFE7ECF5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(tool.icon, size: 17, color: tool.color),
              const SizedBox(width: 6),
              Text(
                tool.title,
                style: TextStyle(
                  color: selected ? tool.color : AppTokens.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ApiHubToolCard extends StatelessWidget {
  const ApiHubToolCard({
    super.key,
    required this.tool,
    required this.selected,
    required this.onTap,
  });

  final PublicApiToolDefinition tool;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 156,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? tool.color.withValues(alpha: 0.12) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? tool.color.withValues(alpha: 0.55)
                  : const Color(0xFFE9EEF7),
            ),
            boxShadow: selected ? AppTokens.shadowSm(color: tool.color) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: tool.color.withValues(alpha: 0.12),
                child: Icon(tool.icon, color: tool.color, size: 18),
              ),
              const SizedBox(height: 8),
              Text(
                tool.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTokens.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                tool.provider,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTokens.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ApiHubPanel extends StatelessWidget {
  const ApiHubPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    // 外壳用 Material 而不是 Container+BoxDecoration。
    //
    // 视觉完全一致（白底 + 26 圆角 + 描边 + 同一组阴影），但多了一件要紧的事：
    // 给面板内容提供 Material 语境。ListTile / ExpansionTile / InkWell 都把
    // 背景和水波纹画到最近的 Material 祖先上，之前那层白底 Container 会把它们
    // 盖掉 —— 「可用 API 清单」每行都可点却没有按压反馈，framework 还会抛
    // 「ListTile background color or ink splashes may be invisible」断言。
    // 修在外壳上，所有面板一次受益，不用每个面板各自包一层。
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        shadowColor: AppTokens.primaryBlue.withValues(alpha: 0.06),
        elevation: 1.5,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xFFE9EEF7)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSectionHeader(title: title, subtitle: subtitle, icon: icon),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class ApiHubSearchRow extends StatelessWidget {
  const ApiHubSearchRow({
    super.key,
    required this.controller,
    required this.label,
    required this.buttonLabel,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String label;
  final String buttonLabel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSubmit(),
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: const Icon(Icons.search_rounded),
            ),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton(onPressed: onSubmit, child: Text(buttonLabel)),
      ],
    );
  }
}

class ApiHubWeatherDailyTile extends StatelessWidget {
  const ApiHubWeatherDailyTile(this.item, {super.key});

  final WeatherDailyResult item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: AppTokens.primaryBlue.withValues(alpha: 0.12),
        child: const Icon(
          Icons.calendar_today_rounded,
          color: AppTokens.primaryBlue,
        ),
      ),
      title: Text(item.date),
      subtitle: Text(
        '最高 ${item.maxTemperature?.toStringAsFixed(1) ?? '--'}°C · 最低 ${item.minTemperature?.toStringAsFixed(1) ?? '--'}°C · code ${item.weatherCode ?? '--'}',
      ),
    );
  }
}

class ApiHubDictionaryMeaningTile extends StatelessWidget {
  const ApiHubDictionaryMeaningTile(this.meaning, {super.key});

  final DictionaryMeaningResult meaning;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: AppTokens.violet.withValues(alpha: 0.12),
        child: const Icon(Icons.text_fields_rounded, color: AppTokens.violet),
      ),
      title: Text(
        meaning.definition,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          meaning.partOfSpeech,
          meaning.example,
        ].where((e) => e.isNotEmpty).join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class ApiHubMockUserTile extends StatelessWidget {
  const ApiHubMockUserTile(this.user, {super.key, required this.onCopy});

  final MockUserResult user;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: user.image.isEmpty
            ? Container(
                width: 50,
                height: 50,
                color: AppTokens.emerald.withValues(alpha: 0.12),
                child: const Icon(Icons.person_rounded),
              )
            : Image.network(
                user.image,
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 50,
                  height: 50,
                  color: AppTokens.emerald.withValues(alpha: 0.12),
                  child: const Icon(Icons.person_rounded),
                ),
              ),
      ),
      title: Text(user.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (user.email.isNotEmpty) user.email,
          if (user.city.isNotEmpty) user.city,
          if (user.company.isNotEmpty) user.company,
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        onPressed: onCopy,
        icon: const Icon(Icons.copy_rounded),
        tooltip: '复制用户资料',
      ),
    );
  }
}

class ApiHubDirectoryEntryTile extends StatelessWidget {
  const ApiHubDirectoryEntryTile(this.entry, {super.key, required this.onTap});

  final PublicApiDirectoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: AppTokens.orange.withValues(alpha: 0.12),
        child: const Icon(Icons.cloud_done_rounded, color: AppTokens.orange),
      ),
      title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${entry.category} · ${entry.auth} · ${entry.https ? 'HTTPS' : 'HTTP'} · CORS ${entry.cors}\n'
        '${entry.description}\n'
        '${entry.url}',
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            entry.latencyMs == null ? '--ms' : '${entry.latencyMs}ms',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Icon(
            entry.isIntegrated
                ? Icons.check_circle_rounded
                : Icons.chevron_right_rounded,
            color: entry.isIntegrated
                ? AppTokens.emerald
                : AppTokens.textSecondary,
            size: 18,
          ),
        ],
      ),
      isThreeLine: true,
    );
  }
}

class ApiHubCurrencyDropDown extends StatelessWidget {
  const ApiHubCurrencyDropDown({
    super.key,
    required this.value,
    required this.codes,
    required this.onChanged,
  });

  final String value;
  final List<String> codes;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: value,
      items: codes
          .map((code) => DropdownMenuItem(value: code, child: Text(code)))
          .toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}
