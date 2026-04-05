import 'package:flutter/material.dart';

import 'video-Pro/pages/video_home_page.dart';
import 'video-Pro/widgets/video_play_container.dart';

export 'video-Pro/video_module.dart';

export 'video-Pro/controller/aggregate_search_controller.dart';
export 'video-Pro/controller/history_controller.dart';
export 'video-Pro/controller/video_controller.dart';
export 'video-Pro/controller/video_search_controller.dart';

export 'video-Pro/models/aggregate_result.dart';
export 'video-Pro/models/history_item.dart';
export 'video-Pro/models/video_source.dart';
export 'video-Pro/models/vod_item.dart';

export 'video-Pro/pages/aggregate_search_page.dart';
export 'video-Pro/pages/video_detail_page.dart';
export 'video-Pro/pages/video_home_page.dart';
export 'video-Pro/pages/video_search_page.dart';
export 'video-Pro/pages/video_sliver_home.dart';

export 'video-Pro/services/video_api_service.dart';

export 'video-Pro/widgets/history_quick_view.dart';
export 'video-Pro/widgets/video_play_container.dart';

/// 兼容入口：Box 里直接打开视频列表页面
class VideoListPage extends StatelessWidget {
  const VideoListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const VideoHomePage();
  }
}

/// 独立播放器入口
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