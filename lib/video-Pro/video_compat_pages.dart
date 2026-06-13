import 'package:flutter/material.dart';

import 'pages/video_home_page.dart';
import 'widgets/video_play_container.dart';

/// 兼容入口：Box 里直接打开视频列表页面。
///
/// 保留旧类名给历史 import 使用，实际实现归入视频模块内部。
class VideoListPage extends StatelessWidget {
  const VideoListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const VideoHomePage();
  }
}

/// 独立播放器兼容入口。
class VideoPlayerPage extends StatelessWidget {
  final String url;
  final String title;
  final String vodId;
  final String vodPic;
  final String sourceId;
  final String sourceName;
  final String episodeName;
  final int initialPosition;

  const VideoPlayerPage({
    super.key,
    required this.url,
    required this.title,
    this.vodId = '',
    this.vodPic = '',
    this.sourceId = '',
    this.sourceName = '',
    this.episodeName = '正片',
    this.initialPosition = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: VideoPlayContainer(
        url: url,
        title: title,
        vodId: vodId,
        vodPic: vodPic,
        sourceId: sourceId,
        sourceName: sourceName,
        episodeName: episodeName,
        initialPosition: initialPosition,
      ),
    );
  }
}
