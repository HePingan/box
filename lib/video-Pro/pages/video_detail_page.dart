import 'package:flutter/material.dart';
import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../services/video_api_service.dart';
import '../widgets/video_play_container.dart';

/// 文件功能：视频详情与选集页面
/// 实现：异步加载播放地址、解析线路、展示剧集按钮
class VideoDetailPage extends StatefulWidget {
  final VideoSource source; // 资源站信息
  final int vodId;         // 视频ID

  const VideoDetailPage({super.key, required this.source, required this.vodId});

  @override
  State<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends State<VideoDetailPage> {
  VodItem? _fullDetail;
  bool _isLoading = true;
  Map<String, String>? _currentEpisode; // 当前播放的剧集 {name, url}

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  // 获取包含播放链接的完整详情 (ac=detail)
  Future<void> _loadDetail() async {
    final detail = await VideoApiService.fetchDetail(widget.source.detailUrl, widget.vodId);
    if (mounted) {
      setState(() {
        _fullDetail = detail;
        _isLoading = false;
        // 默认播放第一集
        if (_fullDetail != null && _fullDetail!.parsePlayUrls.isNotEmpty) {
          _currentEpisode = _fullDetail!.parsePlayUrls[0];
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_fullDetail?.vodName ?? "详情")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 1. 播放器区域 (文件 7 实现)
                if (_currentEpisode != null)
                  VideoPlayContainer(
                    url: _currentEpisode!['url']!,
                    title: _fullDetail!.vodName,
                  )
                else
                  const AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Center(child: Text("无可播放资源")),
                  ),

                // 2. 视频信息介绍
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _buildVideoInfo(),
                      const Divider(),
                      const Text("直播/选集", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      // 3. 剧集列表渲染 (解析截图3中的结果)
                      _buildEpisodeList(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // 构建视频基本信息
  Widget _buildVideoInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_fullDetail?.vodName ?? "", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text("更新：${_fullDetail?.vodRemarks ?? '未知'}"),
        Text("分类：${_fullDetail?.typeName ?? '通用'}"),
        const SizedBox(height: 8),
        Text("更新时间：${_fullDetail?.vodTime ?? '-'}"),
      ],
    );
  }

  // 构建选集或线路列表
  Widget _buildEpisodeList() {
    final episodes = _fullDetail?.parsePlayUrls ?? [];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: episodes.map((ep) {
        bool isSelected = _currentEpisode == ep;
        return ActionChip(
          label: Text(ep['name']!),
          backgroundColor: isSelected ? Colors.blue : null,
          labelStyle: TextStyle(color: isSelected ? Colors.white : null),
          onPressed: () {
            setState(() {
              _currentEpisode = ep;
            });
          },
        );
      }).toList(),
    );
  }
}