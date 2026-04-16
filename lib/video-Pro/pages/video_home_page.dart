import 'package:flutter/material.dart';

import 'video_sliver_home.dart';

class VideoHomePage extends StatelessWidget {
  final String title;
  final bool showHistory;
  final VoidCallback? onSearchTap;

  const VideoHomePage({
    super.key,
    this.title = '视频',
    this.showHistory = true,
    this.onSearchTap,
  });

  @override
  Widget build(BuildContext context) {
    return VideoSliverHome(
      title: title,
      showHistory: showHistory,
      onSearchTap: onSearchTap,
    );
  }
}