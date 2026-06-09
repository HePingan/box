import 'package:flutter/material.dart';

import 'package:box/plugin_manager.dart';

class HomeFeatureCardItem {
  const HomeFeatureCardItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    this.status,
    this.onTap,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final String? status;
  final HomePluginTap? onTap;

  factory HomeFeatureCardItem.fromPlugin(HomePlugin plugin) {
    return HomeFeatureCardItem(
      id: plugin.id,
      title: plugin.title,
      subtitle: plugin.subtitle,
      icon: plugin.icon,
      gradient: [plugin.color, plugin.color.withValues(alpha: 0.68)],
      status: '插件',
      onTap: plugin.onTap,
    );
  }
}

class HomeQuickAction {
  const HomeQuickAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class HomeCategoryTab {
  const HomeCategoryTab(this.label, this.icon, this.area);

  final String label;
  final IconData icon;
  final HomePluginArea area;
}
