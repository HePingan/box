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
      height: 56 + topInset,
      padding: EdgeInsets.only(top: topInset),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(
            color: textColor.withOpacity(0.08),
            width: 1,
          ),
        ),
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