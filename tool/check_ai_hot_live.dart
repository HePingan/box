// 发版前的活体检查：拿**客户端自己的模型和白名单**去对上游今天给的真实数据。
//
// 为什么需要它：353 那个「点开任何热点都是视界日报门户页」的 bug，
// 坏就坏在白名单写的是**接口主机**、而上游条目页在另一个域名上 ——
// 这种「我们的假设」和「上游的事实」漂开，本地用例永远绿（夹具是人手写的），
// 只有真机点开才知道。这个脚本把两边的对照做成一条命令，接进构建脚本。
//
// 查三件事：
//   1) 接口还返回条目，且客户端解析出来的条数 == 原始 JSON 里的条数
//      （字段改名会让条目**静默消失**，条数对不上就是信号）
//   2) 每条条目页地址都在 daily_news_url_policy 的白名单里（站外会被判成打不开）
//   3) 每个分类都有中文标签（否则首页 AI 行的标签位直接显示英文 slug）
//
// 退出码：
//   0 = 通过，或**上游不可达**（离线/限流不该阻断发版，会醒目地打印「跳过」）
//   1 = 上游可达但客户端假设已经漂了 —— 构建脚本据此阻断
//
// 用法：dart run tool/check_ai_hot_live.dart
import 'dart:convert';
import 'dart:io';

import 'package:box/daily_news_url_policy.dart';
import 'package:box/features/home/data/ai_hot_models.dart';

const String _endpoint =
    'https://aihot.news/api/v1/items?mode=selected&window=7d&limit=50';

Future<void> main() async {
  final client = HttpClient();
  String body;
  try {
    final req = await client.getUrl(Uri.parse(_endpoint));
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final resp = await req.close().timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) {
      stdout.writeln('[跳过] 上游返回 ${resp.statusCode}（限流/维护都不阻断发版）');
      client.close();
      exit(0);
    }
    body = await resp.transform(utf8.decoder).join();
  } catch (e) {
    stdout.writeln('[跳过] 上游不可达（$e）—— 离线不该阻断发版');
    client.close();
    exit(0);
  }
  client.close();

  final raw = jsonDecode(body) as Map<String, dynamic>;
  final rawItems = <Map<String, dynamic>>[
    for (final it in (raw['items'] as List? ?? const []))
      if (it is Map) it.cast<String, dynamic>(),
  ];
  final feed = AiHotFeed.fromJson(raw);

  final problems = <String>[];

  // 1) 解析条数（静默丢条目）
  if (feed.items.length != rawItems.length) {
    problems.add(
      '解析出 ${feed.items.length} 条，上游给了 ${rawItems.length} 条'
      '（字段改名/类型变化会让条目静默消失）',
    );
  }

  // 2) 条目页主机必须在白名单里
  final hosts = <String>{};
  for (final item in feed.items) {
    final open = item.openUrl;
    if (open == null) {
      problems.add('条目 ${item.id} 没有可打开的地址');
      continue;
    }
    final target = DailyNewsUrlPolicy.decide(open);
    hosts.add(target.uri.host);
    if (target.isBlocked) {
      problems.add('条目 ${item.id} 的地址被判成站外：$open');
    }
  }

  // 3) 分类必须有中文标签
  final labels = <String, String>{};
  for (final item in feed.items) {
    final cat = item.category;
    if (cat == null || cat.isEmpty) continue;
    labels[cat] = item.categoryLabel;
    if (item.categoryLabel == cat) {
      problems.add('分类 $cat 没有中文标签（界面上会直接显示英文 slug）');
    }
  }

  stdout.writeln(
    '上游 ${feed.items.length} 条 · 条目页主机 ${hosts.join(', ')} · '
    '分类 ${labels.entries.map((e) => '${e.key}→${e.value}').join(', ')}',
  );

  if (problems.isEmpty) {
    stdout.writeln('[通过] 主机白名单与分类标签都跟得上上游');
    exit(0);
  }
  stderr.writeln('[失败] 上游与客户端假设已经漂了，先修再发：');
  for (final p in problems.toSet()) {
    stderr.writeln('  ✗ $p');
  }
  exit(1);
}
