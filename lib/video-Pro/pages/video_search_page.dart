import 'package:flutter/material.dart';

import '../models/video_source.dart';
import '../models/vod_item.dart';
import '../services/video_api_service.dart';
import 'video_detail_page.dart';

class VideoSearchPage extends StatefulWidget {
  final VideoSource currentSource;

  const VideoSearchPage({super.key, required this.currentSource});

  @override
  State<VideoSearchPage> createState() => _VideoSearchPageState();
}

class _VideoSearchPageState extends State<VideoSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  List<VodItem> _results = [];
  bool _isLoading = false;
  bool _hasSearched = false;

  Future<void> _performSearch() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;

    FocusScope.of(context).unfocus(); // 收起键盘
    setState(() {
      _isLoading = true;
      _hasSearched = true;
    });

    final res = await VideoApiService.searchVideo(widget.currentSource.url, keyword);

    if (mounted) {
      setState(() {
        _results = res;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '在 ${widget.currentSource.name} 中搜索...',
            border: InputBorder.none,
            hintStyle: const TextStyle(fontSize: 15),
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _performSearch(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _performSearch,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (!_hasSearched)
              ? Center(child: Text('输入关键字开始搜索', style: TextStyle(color: Colors.grey.shade500)))
              : _results.isEmpty
                  ? Center(child: Text('未找到相关视频', style: TextStyle(color: Colors.grey.shade500)))
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: screenWidth > 600 ? 6 : 3, // 宽屏适配
                        childAspectRatio: 0.55,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final video = _results[index];
                        return _buildResultCard(video);
                      },
                    ),
    );
  }

  Widget _buildResultCard(VodItem video) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VideoDetailPage(source: widget.currentSource, vodId: video.vodId),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  color: Colors.grey.shade200,
                  alignment: Alignment.center,
                  child: const Icon(Icons.movie_outlined, size: 30, color: Colors.grey),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(video.vodName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 2),
          Text(video.typeName ?? '未知', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}