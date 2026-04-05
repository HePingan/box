import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fijkplayer/fijkplayer.dart';
import 'package:provider/provider.dart';
import '../controller/history_controller.dart';

/// 文件功能：核心播放器组件 (含进度记忆与防盗链优化)
/// 特点：注入 User-Agent、自动保存历史、支持从上次位置起播
class VideoPlayContainer extends StatefulWidget {
  final String url;           // 当前播放的 M3U8/MP4 地址
  final String title;         // 视频标题
  final String vodId;         // 视频唯一ID
  final String vodPic;        // 视频封面图
  final String sourceId;      // 资源站ID
  final String sourceName;    // 资源站名称
  final String episodeName;   // 当前集数名称 (如: 第01集)
  final int initialPosition;  // 初始起播位置 (毫秒)，默认为 0

  const VideoPlayContainer({
    super.key,
    required this.url,
    required this.title,
    required this.vodId,
    required this.vodPic,
    required this.sourceId,
    required this.sourceName,
    required this.episodeName,
    this.initialPosition = 0,
  });

  @override
  State<VideoPlayContainer> createState() => _VideoPlayContainerState();
}

class _VideoPlayContainerState extends State<VideoPlayContainer> {
  final FijkPlayer _player = FijkPlayer();
  Timer? _progressTimer; // 定时器，用于低频触发进度保存

  @override
  void initState() {
    super.initState();
    _playVideo();
    _startProgressSaving();
  }

  // 1. 核心播放逻辑
  void _playVideo() async {
    // 关键优化：设置播放器 Header，解决由于防盗链导致的 403 播放失败
    // 使用 \n 分隔多个 Header
    await _player.setOption(FijkOption.formatCategory, "headers", 
      "User-Agent: okhttp/3.12.11\n"
      "Referer: https://api.wujinapi.com/\n"
      "Accept: */*");

    // 针对直播/点播 HLS 的稳定性优化
    await _player.setOption(FijkOption.formatCategory, "reconnect", 5); // 失败自动重连次数
    await _player.setOption(FijkOption.playerCategory, "enable-accurate-seek", 1); // 精准寻时
    await _player.setOption(FijkOption.playerCategory, "framedrop", 1); // 允许跳帧以同步音画
    await _player.setOption(FijkOption.playerCategory, "start-on-prepared", 1); // 准备就绪立即播放

    // 加载数据源
    await _player.setDataSource(widget.url, autoPlay: true);

    // 2. 断点续看逻辑：如果历史进度大于 0，则自动跳转
    if (widget.initialPosition > 0) {
      _player.seekTo(widget.initialPosition);
    }
  }

  // 3. 进度保存逻辑：每隔 5 秒向本地数据库同步一次进度
  void _startProgressSaving() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_player.state == FijkState.started) {
        final int currentPos = _player.value.pos.inMilliseconds;
        final int totalDur = _player.value.duration.inMilliseconds;

        if (currentPos > 0 && totalDur > 0) {
          // 调用全局 HistoryController 存入本地存储 (Hive/SQLite)
          context.read<HistoryController>().saveProgress(
            vodId: widget.vodId,
            vodName: widget.title,
            vodPic: widget.vodPic,
            sourceId: widget.sourceId,
            sourceName: widget.sourceName,
            episodeName: widget.episodeName,
            episodeUrl: widget.url,
            position: currentPos,
            duration: totalDur,
          );
        }
      }
    });
  }

  // 4. 处理集数切换
  @override
  void didUpdateWidget(VideoPlayContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果播放地址变了（切换了集数），则重置播放器状态
    if (oldWidget.url != widget.url) {
      _player.reset().then((_) {
        _playVideo();
      });
    }
  }

  @override
  void dispose() {
    // 销毁时务必保存一次最终进度
    if (_player.value.pos.inMilliseconds > 0) {
      _saveFinalProgress();
    }
    _progressTimer?.cancel();
    _player.release();
    super.dispose();
  }

  void _saveFinalProgress() {
    context.read<HistoryController>().saveProgress(
          vodId: widget.vodId,
          vodName: widget.title,
          vodPic: widget.vodPic,
          sourceId: widget.sourceId,
          sourceName: widget.sourceName,
          episodeName: widget.episodeName,
          episodeUrl: widget.url,
          position: _player.value.pos.inMilliseconds,
          duration: _player.value.duration.inMilliseconds,
        );
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: FijkView(
          player: _player,
          color: Colors.black,
          // 使用自定义面板，展示视频标题
          panelBuilder: (FijkPlayer player, FijkData data, BuildContext context, Size viewSize, Rect textureRect) {
            return fijkPanel2Builder(title: "${widget.title} - ${widget.episodeName}")(
              player, data, context, viewSize, textureRect
            );
          },
        ),
      ),
    );
  }
}