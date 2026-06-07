import 'package:flutter/material.dart';

import 'reader_controller.dart';

class ReaderTopBar extends StatelessWidget {
  const ReaderTopBar({
    super.key,
    required this.controller,
    required this.bgColor,
    required this.textColor,
    required this.onBack,
  });

  final ReaderController controller;
  final Color bgColor;
  final Color textColor;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      height: 56 + topInset,
      padding: EdgeInsets.only(top: topInset),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: textColor.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: textColor,
              size: 20,
            ),
            onPressed: onBack,
          ),
          Expanded(
            child: Text(
              controller.bookTitle,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
