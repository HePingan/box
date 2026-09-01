// AI HOT 真实网络连通性 + 解析契约（e2e）。
//
// 打真实服务端，验证「我们的模型能吃下上游今天真实返回的数据」。
// 上游改字段/挂掉时这里会红，属于预期信号——不是本地代码坏了。
//
// 标了 tags: ['live'] ，离线跑全量时可以用 --exclude-tags live 跳过。
import 'package:box/features/home/data/ai_hot_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'AI HOT 精选接口真实可用且能解析出条目',
    () async {
      final service = AiHotService();
      final feed = await service.fetchSelected(take: 4, forceRefresh: true);

      expect(
        feed.items,
        isNotEmpty,
        reason: '真实上游应返回精选条目；为空说明接口变了或网络不可达',
      );

      final first = feed.items.first;
      expect(first.id, isNotEmpty);
      expect(first.title, isNotEmpty);
      expect(
        first.openUrl,
        isNotNull,
        reason: '每条至少要有可打开的链接（permalink 或原文）',
      );
      expect(
        feed.attributionLabel,
        isNotEmpty,
        reason: '署名必须存在',
      );

      // 中文标题不该出现 latin1 误解码的乱码特征。
      expect(
        first.title.contains('â') || first.title.contains('ç'),
        isFalse,
        reason: '标题出现 latin1 乱码特征，说明解码链路有问题',
      );
    },
    tags: <String>['live'],
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
