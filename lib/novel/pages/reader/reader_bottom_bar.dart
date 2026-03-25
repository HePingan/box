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

  Widget _action(
    IconData icon,
    String text,
    VoidCallback? onTap,
  ) {
    final disabled = onTap == null;

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: disabled ? 0.35 : 1.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 28,
              color: textColor,
            ),
            const SizedBox(height: 2),
            Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: BorderSide(
            color: textColor.withOpacity(0.08),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _action(Icons.format_list_bulleted, '目录', onDirectory),
          _action(
            Icons.skip_previous_rounded,
            '上一章',
            onPrev,
          ),
          _action(
            Icons.skip_next_rounded,
            '下一章',
            onNext,
          ),
          _action(Icons.settings_outlined, '设置', onSettings),
        ],
      ),
    );
  }
}