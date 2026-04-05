import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // 假设你使用 Provider 管理状态
import '../controller/video_controller.dart';
import '../models/video_source.dart';

/// 文件功能：视频模块主入口
/// 实现：源站切换、视频列表展示、点击进入详情
class VideoHomePage extends StatefulWidget {
  const VideoHomePage({super.key});

  @override
  State<VideoHomePage> createState() => _VideoHomePageState();
}

class _VideoHomePageState extends State<VideoHomePage> {
  @override
  void initState() {
    super.initState();
    // 页面初始化时，加载 GitHub 的配置链接
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VideoController>().initSources(
          "https://raw.githubusercontent.com/ZhuBaiwan-oOZZXX/OuonnkiTV-Source/main/tv_source/OuonnkiTV/full-noadult.json");
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VideoController>();

    return Scaffold(
      appBar: AppBar(
        title: Text(controller.currentSource?.name ?? "视频聚合"),
        actions: [
          // 切换源站的按钮
          IconButton(
            icon: const Icon(Icons.source),
            onPressed: () => _showSourcePicker(context, controller),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: 跳转搜索页
            },
          ),
        ],
      ),
      body: controller.isLoading && controller.videoList.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => controller.fetchVideoList(isRefresh: true),
              child: GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, // 每行3个，适合手机端布局
                  childAspectRatio: 0.7,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: controller.videoList.length,
                itemBuilder: (context, index) {
                  final video = controller.videoList[index];
                  return _buildVideoCard(video);
                },
              ),
            ),
    );
  }

  // 构建视频卡片
  Widget _buildVideoCard(video) {
    return GestureDetector(
      onTap: () {
        // TODO: 跳转视频详情页 (下一节实现)
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                video.vodPic ?? "",
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    Container(color: Colors.grey, child: const Icon(Icons.movie)),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            video.vodName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            video.vodRemarks ?? "",
            maxLines: 1,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // 弹出源选择器 (底部弹窗)
  void _showSourcePicker(BuildContext context, VideoController controller) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return ListView.builder(
          itemCount: controller.sources.length,
          itemBuilder: (context, index) {
            final s = controller.sources[index];
            return ListTile(
              title: Text(s.name),
              selected: s.id == controller.currentSource?.id,
              onTap: () {
                controller.setCurrentSource(s);
                Navigator.pop(context);
              },
            );
          },
        );
      },
    );
  }
}