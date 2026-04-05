import 'package:flutter/material.dart';

import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../services/video_api_service.dart';
import '../widgets/video_play_container.dart';

class VideoDetailPage extends StatefulWidget {
  final VideoSource source;
  final int vodId;

  const VideoDetailPage({
    super.key,
    required this.source,
    required this.vodId,
  });

  @override
  State<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends State<VideoDetailPage> {
  VodItem? _fullDetail;
  bool _isLoading = true;
  String? _currentEpisodeUrl;
  String? _currentEpisodeName;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _isLoading = true;
    });

    final detail = await VideoApiService.fetchDetail(
      widget.source.detailUrl,
      widget.vodId,
    );

    if (!mounted) return;

    setState(() {
      _fullDetail = detail;
      _isLoading = false;

      if (_fullDetail != null && _fullDetail!.parsePlayUrls.isNotEmpty) {
        _currentEpisodeUrl = _fullDetail!.parsePlayUrls.first['url'];
        _currentEpisodeName = _fullDetail!.parsePlayUrls.first['name'];
      } else {
        _currentEpisodeUrl = null;
        _currentEpisodeName = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = _fullDetail?.vodName ?? widget.source.name;
    // 获取屏幕高度，用来限制播放器最大高度，防止网页端/平板横屏时溢出
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontSize: 16)),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _fullDetail == null
              ? const Center(child: Text('视频详情加载失败'))
              : Column(
                  children: [
                    // --- 播放器区域：加入了限高和黑底，完美适配任意屏幕 ---
                    Container(
                      width: double.infinity,
                      color: Colors.black,
                      // 限定最大高度为屏幕高度的 45%，彻底杜绝底部集数被挤爆
                      constraints: BoxConstraints(
                        maxHeight: screenHeight * 0.45,
                      ),
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: _currentEpisodeUrl != null
                              ? VideoPlayContainer(
                                  url: _currentEpisodeUrl!,
                                  title: _fullDetail!.vodName,
                                  vodId: widget.vodId.toString(),
                                  vodPic: _fullDetail?.vodPic ?? '',
                                  sourceId: widget.source.id,
                                  sourceName: widget.source.name,
                                  episodeName: _currentEpisodeName ?? '正片',
                                )
                              : const Center(
                                  child: Text('无可播放资源', style: TextStyle(color: Colors.white)),
                                ),
                        ),
                      ),
                    ),
                    // ---------------------------------------------------
                    
                    // --- 详情与选集区域 ---
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          _buildVideoInfo(),
                          const SizedBox(height: 16),
                          const Text(
                            '选集 / 线路',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _buildEpisodeList(),
                          // 底部留一点空白，滑动更舒服
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildVideoInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _fullDetail?.vodName ?? '',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text('更新：${_fullDetail?.vodRemarks ?? '未知'}'),
        Text('分类：${_fullDetail?.typeName ?? '通用'}'),
        Text('更新时间：${_fullDetail?.vodTime ?? '-'}'),
        Text('来源：${widget.source.name}'),
      ],
    );
  }

  Widget _buildEpisodeList() {
    final episodes = _fullDetail?.parsePlayUrls ?? [];
    if (episodes.isEmpty) {
      return const Text('暂无选集数据');
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: episodes.map((ep) {
        final isSelected = ep['url'] == _currentEpisodeUrl;
        return ChoiceChip(
          label: Text(ep['name'] ?? '正片'),
          selected: isSelected,
          onSelected: (_) {
            if (isSelected) return; // 已经是当前集就不刷新了
            
            // 切换集数
            setState(() {
              _currentEpisodeUrl = ep['url'];
              _currentEpisodeName = ep['name'];
            });
          },
        );
      }).toList(),
    );
  }
}