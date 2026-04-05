import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/video_source.dart';
import '../controller/video_search_controller.dart';
import 'video_detail_page.dart';

/// 文件功能：搜索页面 UI
/// 实现：输入框交互、搜索结果展示、点击跳转至详情页
class VideoSearchPage extends StatefulWidget {
  final VideoSource currentSource; // 从主页传入当前选中的源

  const VideoSearchPage({super.key, required this.currentSource});

  @override
  State<VideoSearchPage> createState() => _VideoSearchPageState();
}

class _VideoSearchPageState extends State<VideoSearchPage> {
  final TextEditingController _searchEditController = TextEditingController();

  @override
  void dispose() {
    _searchEditController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 建议在外部配置好 Provider，或者在此处局部创建
    return ChangeNotifierProvider(
      create: (_) => VideoSearchController(),
      child: Consumer<VideoSearchController>(
        builder: (context, searchCtrl, child) {
          return Scaffold(
            appBar: AppBar(
              title: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextField(
                  controller: _searchEditController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: "搜索影片、综艺...",
                    prefixIcon: Icon(Icons.search),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  onSubmitted: (value) {
                    searchCtrl.search(widget.currentSource, value);
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => searchCtrl.search(widget.currentSource, _searchEditController.text),
                  child: const Text("确定"),
                )
              ],
            ),
            body: _buildSearchBody(searchCtrl),
          );
        },
      ),
    );
  }

  // 构建搜索主体内容
  Widget _buildSearchBody(VideoSearchController searchCtrl) {
    if (searchCtrl.isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (searchCtrl.searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text("在 [${widget.currentSource.name}] 下未找到资源", 
                 style: const TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: searchCtrl.searchResults.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        final video = searchCtrl.searchResults[index];
        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.network(
              video.vodPic ?? "",
              width: 50,
              height: 70,
              fit: BoxFit.cover,
              errorBuilder: (context, _, __) => Container(width: 50, color: Colors.grey),
            ),
          ),
          title: Text(video.vodName, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text("${video.typeName ?? ''} | ${video.vodRemarks ?? ''}"),
          trailing: const Icon(Icons.arrow_forward_ios, size: 14),
          onTap: () {
            // 点击搜索结果，直接跳转到我们上一节定义的详情页
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => VideoDetailPage(
                  source: widget.currentSource,
                  vodId: video.vodId,
                ),
              ),
            );
          },
        );
      },
    );
  }
}