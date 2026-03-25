import 'dart:async';

import 'package:flutter/material.dart';

import 'reader_controller.dart';

class ReaderContinuousView extends StatelessWidget {
  const ReaderContinuousView({
    super.key,
    required this.controller,
    required this.scrollController,
    required this.topPadding,
    required this.textColor,
    required this.onLoadNextChapter,
  });

  final ReaderController controller;
  final ScrollController scrollController;
  final double topPadding;
  final Color textColor;
  final Future<void> Function() onLoadNextChapter;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis != Axis.vertical) return false;

        if (notification.metrics.extentAfter < 2000 &&
            !controller.loadingNextScroll &&
            controller.canGoNext) {
          unawaited(onLoadNextChapter());
        }

        return false;
      },
      child: ListView.builder(
        controller: scrollController,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
        itemCount: controller.scrollItems.length + 1,
        itemBuilder: (context, index) {
          if (controller.scrollItems.isEmpty) {
            return Padding(
              padding: EdgeInsets.only(top: topPadding + 120),
              child: Center(
                child: CircularProgressIndicator(
                  color: textColor.withOpacity(0.35),
                  strokeWidth: 2.5,
                ),
              ),
            );
          }

          if (index == controller.scrollItems.length) {
            final isLastInWholeBook =
                controller.scrollItems.last.index >= controller.totalChapters - 1;

            if (isLastInWholeBook) {
              return Padding(
                padding: const EdgeInsets.only(top: 60, bottom: 40),
                child: Center(
                  child: Text(
                    '—— 全书完 ——',
                    style: TextStyle(
                      color: textColor.withOpacity(0.4),
                      letterSpacing: 2,
                    ),
                  ),
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.only(top: 50, bottom: 50),
              child: Center(
                child: CircularProgressIndicator(
                  color: textColor.withOpacity(0.35),
                  strokeWidth: 2.5,
                ),
              ),
            );
          }

          final item = controller.scrollItems[index];

          return Container(
            key: item.key,
            padding: EdgeInsets.only(top: index == 0 ? topPadding + 16 : 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 30),
                Text(
                  item.content,
                  style: TextStyle(
                    fontSize: controller.settings.fontSize,
                    height: controller.settings.lineHeight,
                    letterSpacing: 0.6,
                    color: textColor,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}