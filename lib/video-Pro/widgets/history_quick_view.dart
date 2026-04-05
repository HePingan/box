import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controller/history_controller.dart';

/// 文件功能：主页“最近观看”快捷组件
class HistoryQuickView extends StatelessWidget {
  const HistoryQuickView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<HistoryController>(
      builder: (context, historyCtrl, child) {
        if (historyCtrl.historyList.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text("继续观看", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: historyCtrl.historyList.length,
                itemBuilder: (context, index) {
                  final item = historyCtrl.historyList[index];
                  return _buildHistoryCard(context, item);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHistoryCard(BuildContext context, item) {
    // 计算进度条： $ \text{width} = \text{cardWidth} \times \frac{\text{position}}{\text{duration}} $
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: () {
          // TODO: 直接跳转详情页并定位到上次播放的剧集和毫秒
        },
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.vodName, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text("看到：${item.episodeName}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  Text("来源：${item.sourceName}", style: const TextStyle(fontSize: 10, color: Colors.blue)),
                ],
              ),
            ),
            // 底部进度条
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 3,
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: item.progressPercentage,
                  child: Container(color: Colors.orange),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}