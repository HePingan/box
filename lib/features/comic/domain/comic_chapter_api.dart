// 「图不在 HTML 里」那类书源的取图接口：章节页自报 aid/cid/picCount，再按 offset
// 分批 POST 取图（野蛮漫画就是这个形态，实测单话 209 张、一批 5 张）。
//
// 为什么抽成单独一份：**两个地方要跑同一套** —— 阅读时的 `ComicOnlineService` 和
// 「漫画源自检」页的「章节取图」这一步。以前只有前者有，自检页对这类源只能报
// 「content 规则里找不到图片选择器」，明明源是好的、看着却像坏了（2026-09-29
// 用户报「自检里没有野蛮漫画」时顺出来的：加进去才发现第三步会误报）。
library;

import 'dart:convert';

import 'comic_fetcher.dart';
import 'comic_source.dart';
import 'comic_source_engine.dart';

/// 章节页 `let read={…}` 里取图需要的参数（aid/cid + 站点自报的张数）。
class ComicChapterReadParams {
  const ComicChapterReadParams({
    required this.aid,
    required this.cid,
    this.picCount,
  });

  final String aid;
  final String cid;

  /// 站点自报的总张数（`picCount`）；拿不到就是 null。
  final int? picCount;
}

/// 从章节页 HTML 里取 `let read={aid:'…',cid:'…',picCount:N,…}`。
///
/// 取不到返回 null（由调用方如实报「站点可能改版」，不要编一个默认值）。
ComicChapterReadParams? readComicChapterParams(String html) {
  final m = RegExp(r'let\s+read\s*=\s*\{([\s\S]*?)\}').firstMatch(html);
  if (m == null) return null;
  final block = m.group(1)!;
  final aid = _quotedFieldOf(block, 'aid');
  final cid = _quotedFieldOf(block, 'cid');
  if (aid == null || cid == null) return null;
  final pc = RegExp(r'picCount\s*:\s*(\d+)').firstMatch(block);
  return ComicChapterReadParams(
    aid: aid,
    cid: cid,
    picCount: pc == null ? null : int.tryParse(pc.group(1)!),
  );
}

/// 取图接口一批的结果。
class ComicChapterPicsBatch {
  const ComicChapterPicsBatch({required this.urls, this.total, this.limit});

  final List<String> urls;

  /// 站点自报的总张数（接口的 `total` 比章节页的 picCount 更权威）。
  final int? total;

  /// 站点**这一批实际给几张**（接口的 `limit`；站点自己封顶 10）。
  /// 拿它判断"这批没满 = 已是最后一批"，比用我们请求的张数可靠。
  final int? limit;
}

/// 解析取图接口的一批响应；结构对不上返回 null（由调用方如实报）。
ComicChapterPicsBatch? parseComicChapterPicsBatch(String body) {
  final Object? raw;
  try {
    raw = jsonDecode(body);
  } catch (_) {
    return null;
  }
  if (raw is! Map) return null;
  final data = raw['data'];
  if (data is! Map) return null;
  final list = data['pic'];
  if (list is! List) return null;
  final urls = <String>[];
  for (final e in list) {
    if (e is! Map) continue;
    final p = (e['pic'] ?? '').toString().trim();
    if (p.isNotEmpty) urls.add(p);
  }
  final t = data['total'];
  final l = data['limit'];
  return ComicChapterPicsBatch(
    urls: urls,
    total: t is num ? t.toInt() : int.tryParse('${t ?? ''}'),
    limit: l is num ? l.toInt() : int.tryParse('${l ?? ''}'),
  );
}

/// 每一批要几张。
///
/// 站点自己封顶 **10**（实测 `limit=20/50/100` 都只回 10 张，响应里也写着 `limit: 10`），
/// 所以按 10 要：一整话 209 张从 42 次往返降到 21 次 —— 少等一半时间。
const int kComicPicBatchSize = 10;

/// 一话最多取多少张（防接口异常时死循环；真源单话实测 209 张，500 够用）。
const int kComicMaxPics = 500;

/// 取一话的图（接口型源）：章节页拿 `aid/cid` → 取图接口按 offset 分批 → 地址交给取数器
/// （中转会包成中转地址；直连原样返回，图片由图片缓存带着手机 UA 去取）。
///
/// [onBatch] 每批成功后回调一次（批号从 1 开始），给自检页做进度提示用。
/// [onImages] 每批成功后回调**当前全部地址**（含 `wrap`）—— 阅读页靠它先显示前几张，
/// 不必等整话 209 张都取完（那要几十次往返，用户看到的就是"一直转圈"）。
Future<List<String>> fetchComicChapterPicsViaApi({
  required ComicFetcher fetcher,
  required ComicSource source,
  required String chapterUrl,
  required String picsPath,
  int batchSize = kComicPicBatchSize,
  int maxPics = kComicMaxPics,
  void Function(int batchNo, int got)? onBatch,
  void Function(List<String> urls)? onImages,
}) async {
  final html = await fetcher.getText(chapterUrl);
  final params = readComicChapterParams(html);
  if (params == null) {
    throw ComicProbeException(
      '章节页里找不到取图参数（`let read={aid,cid,…}`）—— 站点可能改版',
    );
  }
  final picsUrl = source.absolute(picsPath);
  final out = <String>[];
  var offset = 0;
  var batchNo = 0;
  // total：站点说多少张。章节页的 picCount 先当已知数，接口的 `total` 更权威。
  var total = params.picCount ?? 0;
  while (true) {
    if (out.length >= maxPics) {
      throw ComicProbeException(
        '这一话取到 $maxPics 张还没取完（站点说共 $total 张），停下防死循环',
      );
    }
    if (total > 0 && out.length >= total) break; // 取满了
    batchNo++;
    final String body;
    try {
      body = await fetcher.postForm(picsUrl, {
        'id': params.cid,
        'aid': params.aid,
        'offset': '$offset',
        'limit': '$batchSize',
      });
    } on ComicProbeException catch (e) {
      // 报清**第几批 / 从哪一张开始**：只说"取图失败"用户没法判断是偶发还是接口变了。
      throw ComicProbeException('第 $batchNo 批取图失败（offset=$offset）：$e');
    }
    final batch = parseComicChapterPicsBatch(body);
    if (batch == null) {
      throw ComicProbeException(
        '第 $batchNo 批返回的不是取图 JSON（开头：${_head(body)}）',
      );
    }
    if (batch.total != null && batch.total! > 0) total = batch.total!;
    if (batch.urls.isEmpty) {
      if (total > 0 && out.length < total) {
        throw ComicProbeException(
          '第 $batchNo 批（offset=$offset）一张都没返回，但站点说共 $total 张 —— 取不齐',
        );
      }
      break; // 没有更多了
    }
    out.addAll(batch.urls);
    // 按**实际返回张数**推进 offset（末批不足时不会跳过中间的页）。
    offset += batch.urls.length;
    onBatch?.call(batchNo, out.length);
    // 地址交给取数器：中转包成中转地址；直连原样返回（图片缓存自己带手机 UA）。
    onImages?.call(out.map(fetcher.wrap).toList());
    // total 未知时：这批没满（按**站点自报的**批大小判）就是最后一批。
    final effLimit = batch.limit ?? batchSize;
    if (total <= 0 && batch.urls.length < effLimit) break;
  }
  if (out.isEmpty) {
    throw ComicProbeException('这一话一张图都没取到（取图接口返回空）');
  }
  // 图在 `tuer.justpic01pt.com:666`，实测**直连可取**（200 / 48 KB / image/jpeg），
  // 图片缓存会带上手机 UA。
  return out.map(fetcher.wrap).toList();
}

/// 取 `key:'值'` 里的值；`key` 前面要一个**非标识符字符**（或字段开头）——
/// 否则 `cid` 会命中 `apiCid` 里那一截。
String? _quotedFieldOf(String block, String key) {
  final m = RegExp(
    '(?:^|[^A-Za-z0-9_])${RegExp.escape(key)}\\s*:\\s*\'([^\']*)\'',
  ).firstMatch(block);
  final v = m?.group(1)?.trim() ?? '';
  return v.isEmpty ? null : v;
}

String _head(String s) {
  final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  return t.length <= 120 ? t : '${t.substring(0, 120)}…';
}
