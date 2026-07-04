import 'package:flutter/material.dart';

import '../../core/models.dart';
import 'package:box/design_system/widgets/app_page_scaffold.dart';
import 'reader_controller.dart';

class ReaderSettingsSheet extends StatelessWidget {
  const ReaderSettingsSheet({
    super.key,
    required this.controller,
    required this.bgColor,
    required this.textColor,
    required this.onModeChanged,
    required this.onSettingsChanged,
  });

  final ReaderController controller;
  final Color bgColor;
  final Color textColor;
  final ValueChanged<bool> onModeChanged;
  final ValueChanged<ReaderSettings> onSettingsChanged;

  Widget _themeButton({
    required String label,
    required Color backgroundColor,
    required Color labelColor, // 💡 新增：动态文字颜色参数
    required ReaderThemeMode mode,
    required ReaderSettings settings,
    required VoidCallback onPressed,
  }) {
    final selected = settings.themeMode == mode;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: labelColor, // 💡 使用传入的文字颜色
            side: BorderSide(
              color: selected ? Colors.orange : Colors.transparent,
              width: selected ? 1.5 : 0,
            ),
          ),
          onPressed: onPressed,
          child: Text(label),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeAnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final settings = controller.settings;

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '阅读设置',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),

                Row(
                  children: [
                    Text(
                      '翻页方式',
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ChoiceChip(
                      label: const Text('左右翻页'),
                      selected: !controller.isScrollMode,
                      showCheckmark: false,
                      selectedColor: Colors.orange.withValues(alpha: 0.18),
                      onSelected: (_) => onModeChanged(false),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('上下滑动'),
                      selected: controller.isScrollMode,
                      showCheckmark: false,
                      selectedColor: Colors.orange.withValues(alpha: 0.18),
                      onSelected: (_) => onModeChanged(true),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                Text(
                  '字体大小',
                  style: TextStyle(color: textColor.withValues(alpha: 0.75)),
                ),
                // 字号预设 Quick Pick
                Row(
                  children: const [14, 18, 22, 26].map((size) {
                    final selected = settings.fontSize == size;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 3),
                        child: ChoiceChip(
                          label: Text('${size == 14 ? "小" : size == 18 ? "中" : size == 22 ? "大" : "特大"}', style: TextStyle(fontSize: 11)),
                          selected: selected,
                          showCheckmark: false,
                          selectedColor: Colors.orange.withValues(alpha: 0.22),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          onSelected: (_) => onSettingsChanged(settings.copyWith(fontSize: size.toDouble())),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                // 微调滑条
                Slider(
                  value: settings.fontSize,
                  min: 14,
                  max: 30,
                  divisions: 16,
                  activeColor: Colors.orange,
                  inactiveColor: textColor.withValues(alpha: 0.2),
                  onChanged: (v) {
                    onSettingsChanged(settings.copyWith(fontSize: v));
                  },
                ),

                const SizedBox(height: 16),
                Text(
                  '行距',
                  style: TextStyle(color: textColor.withValues(alpha: 0.75)),
                ),
                Slider(
                  value: settings.lineHeight,
                  min: 1.2,
                  max: 3.0,
                  divisions: 18,
                  activeColor: Colors.orange,
                  inactiveColor: textColor.withValues(alpha: 0.2),
                  onChanged: (v) {
                    onSettingsChanged(settings.copyWith(lineHeight: v));
                  },
                ),

                const SizedBox(height: 16),
                Text(
                  '字间距',
                  style: TextStyle(color: textColor.withValues(alpha: 0.75)),
                ),
                Slider(
                  value: settings.letterSpacing,
                  min: 0.0,
                  max: 1.0,
                  divisions: 10,
                  activeColor: Colors.orange,
                  inactiveColor: textColor.withValues(alpha: 0.2),
                  onChanged: (v) {
                    onSettingsChanged(settings.copyWith(letterSpacing: v));
                  },
                ),

                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      '字体',
                      style: TextStyle(color: textColor.withValues(alpha: 0.75)),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<String?>(
                      value: settings.fontFamily,
                      dropdownColor: bgColor,
                      hint: Text('系统默认', style: TextStyle(color: textColor.withValues(alpha: 0.6))),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('系统默认')),
                        DropdownMenuItem(value: 'serif', child: Text('衬线体')),
                        DropdownMenuItem(value: 'monospace', child: Text('等宽体')),
                      ],
                      onChanged: (v) {
                        onSettingsChanged(settings.copyWith(fontFamily: v));
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                // 亮度调节（半透明遮罩叠加层）
                Row(
                  children: [
                    Icon(Icons.brightness_6_rounded, size: 18, color: textColor.withValues(alpha: 0.7)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Slider(
                        value: settings.brightness,
                        min: 0.2,
                        max: 1.0,
                        divisions: 16,
                        activeColor: Colors.orange,
                        inactiveColor: textColor.withValues(alpha: 0.2),
                        onChanged: (v) {
                          onSettingsChanged(settings.copyWith(brightness: v));
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),
                // 屏幕常亮
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '阅读时保持屏幕常亮',
                    style: TextStyle(fontSize: 14, color: textColor.withValues(alpha: 0.8)),
                  ),
                  value: settings.keepScreenOn,
                  activeColor: Colors.orange,
                  onChanged: (v) {
                    onSettingsChanged(settings.copyWith(keepScreenOn: v));
                  },
                ),

                const SizedBox(height: 18),
                // 点击震动
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '翻页时震动反馈',
                    style: TextStyle(fontSize: 14, color: textColor.withValues(alpha: 0.8)),
                  ),
                  value: settings.enableHaptic,
                  activeColor: Colors.orange,
                  onChanged: (v) {
                    onSettingsChanged(settings.copyWith(enableHaptic: v));
                  },
                ),

                const SizedBox(height: 24),
                Row(
                  children: [
                    _themeButton(
                      label: '护眼',
                      backgroundColor: const Color(0xFFCBE5D2),
                      labelColor: Colors.black87, // 浅色背景用黑字
                      mode: ReaderThemeMode.warm,
                      settings: settings,
                      onPressed: () {
                        onSettingsChanged(
                          settings.copyWith(themeMode: ReaderThemeMode.warm),
                        );
                      },
                    ),
                    _themeButton(
                      label: '纸张',
                      backgroundColor: const Color(0xFFF1E9CE),
                      labelColor: Colors.black87, // 浅色背景用黑字
                      mode: ReaderThemeMode.paper,
                      settings: settings,
                      onPressed: () {
                        onSettingsChanged(
                          settings.copyWith(themeMode: ReaderThemeMode.paper),
                        );
                      },
                    ),
                    _themeButton(
                      label: '夜间',
                      backgroundColor: const Color(0xFF1E2028),
                      labelColor: const Color(0xFFD0C8B8),
                      mode: ReaderThemeMode.dark,
                      settings: settings,
                      onPressed: () {
                        onSettingsChanged(
                          settings.copyWith(themeMode: ReaderThemeMode.dark),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
