import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controller/video_controller.dart';
import '../controller/aggregate_search_controller.dart';
import 'video_detail_page.dart';

/// 文件功能：聚合搜索页面 UI
/// 实现：全屏聚合检索、展示来源标签(Tag)、点击精准跳转
class AggregateSearchPage extends StatefulWidget {
  const AggregateSearchPage({super.key});

  @override
  State<AggregateSearchPage> createState() => _AggregateSearchPageState();
}

class _AggregateSearchPageState extends State<AggregateSearchPage> {
  final TextEditingController _searchEditController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    // 获取由 VideoController 加载好的源列表
    final allSources = context.read<VideoController>().sources;

    return ChangeNotifierProvider(
      create: (_) => AggregateSearchController(),
      child: Consumer<AggregateSearchController>(
        builder: (context, aggCtrl, child) {
          return Scaffold(
            appBar: AppBar(
              title: TextField(
                controller: _searchEditController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: "全网资源并发搜...",
                  border: InputBorder.none,
                ),
                onSubmitted: (val) => aggCtrl.searchAllSources(allSources, val),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => aggCtrl.searchAllSources(allSources, _searchEditController.text),
                )
              ],
            ),
            body: _buildList(aggCtrl),
          );
        },
      ),
    );
  }

  Widget _buildList(AggregateSearchController aggCtrl) {
    if (aggCtrl.isSearching) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text("正在飞速检索几十个资源站，请稍后..."),
          ],
        ),
      );
    }

    if (aggCtrl.allResults.isEmpty) {
      return const Center(child: Text("搜一下，万千资源即刻呈现"));
    }

    return ListView.builder(
      itemCount: aggCtrl.allResults.length,
      itemBuilder: (context, index) {
        final item = aggCtrl.allResults[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: ListTile(
            leading: _buildPoster(item.video.vodPic),
            title: Text(item.video.vodName, style: const TextStyle(fontWeight: FontWeight.bold)),
            // 关键：在这里展示来源标签，让用户知道这个结果是从哪个站搜出来的
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("${item.video.typeName} · ${item.video.vodRemarks}"),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    "源自: ${item.source.name}",
                    style: const TextStyle(fontSize: 10, color: Colors.blue),
                  ),
                ),
              ],
            ),
            isThreeLine: true,
            onTap: () {
              // 跳转：这里必须传 item.source 而不是全局 source
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => VideoDetailPage(
                    source: item.source,
                    vodId: item.video.id, // 这里通常是 int，按 model 适配
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // 海报组件
  Widget _buildPoster(String? url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: (url != null && url.isNotEmpty)
          ? Image.network(url, width: 50, height: 75, fit: BoxFit.cover, 
              errorBuilder: (_,__,___) => Container(width: 50, color: Colors.grey))
          : Container(width: 50, color: Colors.grey),
    );
  }
}