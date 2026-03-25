import 'package:flutter/material.dart';

import '../../core/models.dart';
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
    return AnimatedBuilder(
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
                      style: TextStyle(color: textColor.withOpacity(0.75)),
                    ),
                    const SizedBox(width: 16),
                    ChoiceChip(
                      label: const Text('左右翻页'),
                      selected: !controller.isScrollMode,
                      showCheckmark: false,
                      selectedColor: Colors.orange.withOpacity(0.18),
                      onSelected: (_) => onModeChanged(false),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('上下滑动'),
                      selected: controller.isScrollMode,
                      showCheckmark: false,
                      selectedColor: Colors.orange.withOpacity(0.18),
                      onSelected: (_) => onModeChanged(true),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                Text(
                  '字体大小',
                  style: TextStyle(color: textColor.withOpacity(0.75)),
                ),
                Slider(
                  value: settings.fontSize,
                  min: 14,
                  max: 30,
                  divisions: 16,
                  activeColor: Colors.orange,
                  inactiveColor: textColor.withOpacity(0.2),
                  onChanged: (v) {
                    onSettingsChanged(settings.copyWith(fontSize: v));
                  },
                ),

                const SizedBox(height: 12),
                Text(
                  '行距',
                  style: TextStyle(color: textColor.withOpacity(0.75)),
                ),
                Slider(
                  value: settings.lineHeight,
                  min: 1.4,
                  max: 2.4,
                  divisions: 10,
                  activeColor: Colors.orange,
                  inactiveColor: textColor.withOpacity(0.2),
                  onChanged: (v) {
                    onSettingsChanged(settings.copyWith(lineHeight: v));
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
                      backgroundColor: const Color(0xFF141414),
                      labelColor: Colors.white70, // 💡 深色背景用白字
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