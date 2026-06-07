import 'package:flutter/material.dart';

import 'reader_controller.dart';

class ReaderBottomBar extends StatelessWidget {
  const ReaderBottomBar({
    super.key,
    required this.controller,
    required this.bgColor,
    required this.textColor,
    required this.onDirectory,
    required this.onPrev,
    required this.onNext,
    required this.onSettings,
  });

  final ReaderController controller;
  final Color bgColor;
  final Color textColor;
  final VoidCallback? onDirectory;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onSettings;

  Widget _action(IconData icon, String text, VoidCallback? onTap) {
    final disabled = onTap == null;

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: disabled ? 0.35 : 1.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: textColor),
            const SizedBox(height: 2),
            Text(text, style: TextStyle(fontSize: 12, color: textColor)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.only(top: 14, bottom: 18),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: textColor.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _action(Icons.format_list_bulleted, '目录', onDirectory),
          _action(Icons.skip_previous_rounded, '上一章', onPrev),
          _action(Icons.skip_next_rounded, '下一章', onNext),
          _action(Icons.settings_outlined, '设置', onSettings),
        ],
      ),
    );
  }
}
