/// 「这集看过没有」的判定。
///
/// ## 为什么单独抽成纯函数
///
/// 详情页要按播放历史给剧集格子打标记，而历史数据是**脏的**：
/// 记录来自不同版本、不同源，同一个地址可能带/不带查询串，`vodId` 可能
/// 存成字符串 `"123"` 也可能 `"123 "`；还可能是很久以前留下的一条。
///
/// 判错的代价是**误导**：用户看到"看过"的标记却点了没看过的一集，
/// 比不标更糟。所以判定逻辑抽出来单独测，界面上只消费结果。
///
/// ## 判据（三条，全部满足才算看过）
///
/// 1. **同一部片**：`vodId` 相同（按 trim 后比较；片子换了源但 id 相同算同一部）。
/// 2. **同一集**：`episodeUrl` 归一化后相同（去掉 query/fragment 与首尾空白）。
///    不能只比集名 —— 集名来自片源、可能重复；地址才是这一集的唯一标识。
/// 3. **真看过**：进度 ≥ [watchedThreshold]。只点进去看一眼（2 秒）不算，
///    否则整页会全是"看过"的标记，那个标记就没有信息量了。
library;

import '../../models/history_item.dart';

/// 判定「看过」的最小进度：1 分钟。
///
/// 为什么不是 0：播放器一初始化就会落一条 `position>0` 的记录，
/// 把这种也算上等于"点过即看过"。
/// 为什么不是 10 分钟：短剧单集可能只有几分钟，门槛太高会永远标不上。
const int watchedThreshold = 60 * 1000;

/// 归一化一集的可播放地址，用作"同一集"的比较键。
///
/// 去掉 query 与 fragment：采集站常给同一集挂不同的 `?from=x`，但那是同一集。
/// 不解析成 Uri 对象 —— 脏数据里 `Uri.parse` 会抛，而这里只需要字符串比较。
String episodeKeyOf(String url) {
  var text = url.trim();
  if (text.isEmpty) return '';
  // 先砍 fragment，再砍 query。
  final hash = text.indexOf('#');
  if (hash >= 0) text = text.substring(0, hash);
  final question = text.indexOf('?');
  if (question >= 0) text = text.substring(0, question);
  return text.trim();
}

/// 从历史记录里挑出「属于这部片、并且真的看过」的剧集地址集合。
///
/// 返回值是 [episodeKeyOf] 归一化后的地址集合，供详情页的剧集格子做 O(1) 命中。
///
/// [vodId] 传当前页面的影片 id（字符串或数字都转成字符串由调用方负责）。
///
/// 刻意**不**按 `sourceId` 过滤：换源续播是这一版的既有能力（见
/// `cross_source_*` 用例），用户在 A 源看的第 10 集，换到 B 源同一部片
/// 也该显示"看过"。而"同一集"由地址判定，不会把 B 源的另一集标错。
Set<String> watchedEpisodeKeys(
  Iterable<HistoryItem> history, {
  required String vodId,
  int threshold = watchedThreshold,
}) {
  final wantedId = vodId.trim();
  if (wantedId.isEmpty) return const <String>{};

  final keys = <String>{};
  for (final item in history) {
    if (item.vodId.trim() != wantedId) continue;
    // 进度门槛：只记录"真的看过一会儿"的。
    if (item.position < threshold) continue;
    final key = episodeKeyOf(item.episodeUrl);
    if (key.isEmpty) continue;
    keys.add(key);
  }
  return keys;
}

/// 某一集是否看过。`episodeUrl` 传剧集原始的播放地址。
bool isEpisodeWatched(
  Set<String> watchedKeys,
  String episodeUrl,
) {
  if (watchedKeys.isEmpty) return false;
  final key = episodeKeyOf(episodeUrl);
  if (key.isEmpty) return false;
  return watchedKeys.contains(key);
}
