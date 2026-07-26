import 'package:flutter/foundation.dart' show kIsWeb;

/// 豆瓣榜单条目(从豆瓣 API 拉到的原始数据)。
class DoubanRankingItem {
  final String title;
  final String coverUrl;
  final double? rate;
  final String? url; // 豆瓣页面链接
  final String? episodesInfo;
  final List<String> directors; // 导演(新接口 new_search_subjects 提供)
  final List<String> casts; // 主演(新接口 new_search_subjects 提供)

  const DoubanRankingItem({
    required this.title,
    required this.coverUrl,
    this.rate,
    this.url,
    this.episodesInfo,
    this.directors = const [],
    this.casts = const [],
  });

  /// 副标题:导演 · 主演(真实数据,拿不到则为空)。
  /// 例:"文牧野 · 徐峥/王传君/周一围"
  String get subtitle {
    final dir = directors.where((s) => s.isNotEmpty).join('/');
    final cast = casts.where((s) => s.isNotEmpty).take(3).join('/');
    if (dir.isEmpty && cast.isEmpty) return '';
    if (dir.isEmpty) return cast;
    if (cast.isEmpty) return dir;
    return '$dir · $cast';
  }

  /// 展示用封面 URL。
  ///
  /// Web 预览(kIsWeb)下浏览器同源策略+防盗链会拦截 imgN.doubanio.com,
  /// 故把主机名改写到 nginx 同源代理 /douban-img/(补 Referer 并加 CORS 头)。
  /// APK 原生请求不受同源策略约束,直接用原始 URL + Referer 头,逻辑不变。
  String get displayCoverUrl {
    if (!kIsWeb || coverUrl.isEmpty) return coverUrl;
    final uri = Uri.tryParse(coverUrl);
    if (uri == null) return coverUrl;
    // /view/photo/... 路径拼到同源代理下(任意 imgN 分片路径一致,可跨分片取图)。
    return '/douban-img${uri.path}';
  }

  /// 从豆瓣 JSON 字段构造单个条目。
  /// 兼容 new_search_subjects(data 数组,rate 为字符串,含 directors/casts)
  /// 与老接口 search_subjects(subjects 数组,含 episodes_info)。
  factory DoubanRankingItem.fromJson(Map<String, dynamic> json) {
    final cover = json['cover'] as String? ?? '';
    final rateRaw = json['rate'];
    // rate 可能是字符串"9.0"(新接口)或数字(老接口),空评分为"0"跳过。
    final rate = (rateRaw != null && rateRaw.toString().isNotEmpty)
        ? double.tryParse(rateRaw.toString())
        : null;
    return DoubanRankingItem(
      title: (json['title'] as String?) ?? '未知',
      coverUrl: cover,
      rate: (rate != null && rate > 0) ? rate : null,
      url: json['url'] as String?,
      episodesInfo: json['episodes_info'] as String?,
      directors: _stringList(json['directors']),
      casts: _stringList(json['casts']),
    );
  }

  /// 把 JSON 里的 `List<dynamic>` 安全转成 `List<String>`。
  static List<String> _stringList(dynamic v) {
    if (v is List) {
      return v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    return const [];
  }
}

/// 将豆瓣榜单条目映射为 VodItem,用于走源搜索链路。
DoubanRankingItem doubanJsonToItem(Map<String, dynamic> json) =>
    DoubanRankingItem.fromJson(json);
