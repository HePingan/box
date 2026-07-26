import 'dart:convert';

import 'package:box/video/models/douban_ranking_item.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// 豆瓣榜单数据服务。
///
/// 从豆瓣公开 API 拉取实时热门电影/电视剧榜单(真实数据,非编造)。
/// 封面图需要 Referer 防盗链,调用方在展示时注意设置。
///
/// Web 预览模式(kIsWeb)下,浏览器同源策略会拦截跨域请求豆瓣,
/// 故走 nginx 同源代理 /douban-api/(由 nginx 补 Referer 并加 CORS 头)。
/// 该分支仅影响 web 预览,APK 原生请求不受同源策略约束,逻辑不变。
class DoubanRankingService {
  // 老接口 search_subjects 已被豆瓣封禁(稳定返 400),迁到 new_search_subjects。
  // 新接口返回 data 数组,字段更全:directors/casts/rate/star/title/cover/url/id。
  static const _baseUrl = 'https://movie.douban.com/j/new_search_subjects';
  // Web 预览专用同源代理路径(origin-relative,不受 base href 影响)。
  static const _webProxyUrl = '/douban-api/';
  static const _headers = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/122.0.0.0 Mobile Safari/537.36',
  };

  /// 热门电影榜(可选类型标签,如"喜剧"/"爱情")。
  static Future<List<DoubanRankingItem>> hotMovies({
    int pageLimit = 20,
    String? genre,
  }) async {
    return _fetch('movie', 'U', pageLimit, genre);
  }

  /// 热门电视剧榜(可选类型标签)。
  ///
  /// 注:豆瓣 type=tv 单用并不真筛剧集(仍返混合榜),必须叠加 tags=电视剧
  /// 才真出剧集(实测)。类型 chip 与\"电视剧\"用逗号组合,如 tags=电视剧,科幻。
  static Future<List<DoubanRankingItem>> hotTvShows({
    int pageLimit = 20,
    String? genre,
  }) async {
    return _fetch('tv', 'U', pageLimit, genre, baseTag: '电视剧');
  }

  /// 最新电影榜(按时间排序)。
  static Future<List<DoubanRankingItem>> latestMovies({
    int pageLimit = 20,
    String? genre,
  }) async {
    return _fetch('movie', 'R', pageLimit, genre);
  }

  /// 最新电视剧榜(按时间排序)。
  static Future<List<DoubanRankingItem>> latestTvShows({
    int pageLimit = 20,
    String? genre,
  }) async {
    return _fetch('tv', 'R', pageLimit, genre, baseTag: '电视剧');
  }

  /// [type] movie|tv;[sort] U热度/T评分/R时间;[genre] 类型标签(可空);
  /// [baseTag] 固定基础标签(如剧集榜的\"电视剧\"),与 genre 逗号组合。
  static Future<List<DoubanRankingItem>> _fetch(
    String type,
    String sort,
    int pageLimit,
    String? genre, {
    String? baseTag,
  }) async {
    // Web 预览走同源代理绕 CORS;APK 直连豆瓣。
    // 新接口用 sort/tags/start 参数;count 实测被忽略(恒返 ~20 条),
    // 故不传 count,改在客户端截取前 pageLimit 条。
    final params = <String, String>{
      'type': type,
      'sort': sort,
      'range': '0,10', // 评分区间 0-10(全部)
      'start': '0',
    };
    // 类型标签:豆瓣新接口用 tags 参数筛选整个榜单(如 tags=喜剧),实测生效。
    // baseTag(剧集榜固定\"电视剧\")与 genre(类型 chip)用逗号组合,
    // 如 tags=电视剧,科幻 → 真出科幻剧集(实测)。
    final tags = <String>[
      if (baseTag != null && baseTag.isNotEmpty) baseTag,
      if (genre != null && genre.isNotEmpty) genre,
    ];
    if (tags.isNotEmpty) {
      params['tags'] = tags.join(',');
    }
    final uri = Uri.parse(kIsWeb ? _webProxyUrl : _baseUrl).replace(
      queryParameters: params,
    );
    // 豆瓣按 IP 限流:并发/高频请求会返回 200 + 空 data,约 15s 恢复。
    // 故对"返 200 但空 data"做退避重试(最多 3 次),避免榜单偶发空白。
    // 网络错误/非 200 也重试;彻底失败才抛异常(调用方显示"暂不可用",绝不造假)。
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        // 退避:1s、2s,给豆瓣 IP 限流窗口恢复时间。
        await Future.delayed(Duration(seconds: attempt));
      }
      try {
        final response = await http
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) {
          throw Exception('豆瓣返回 ${response.statusCode}');
        }
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        // 新接口返回字段为 data(老接口是 subjects)。
        final data = json['data'] as List<dynamic>? ?? [];
        if (data.isEmpty) {
          // 空 data 多半是限流,退避后重试;最后一轮仍空则返回空列表。
          lastError = Exception('豆瓣返回空数据(疑似限流)');
          continue;
        }
        final items =
            data.map((e) => DoubanRankingItem.fromJson(e)).toList();
        // count 参数无效,客户端截取前 pageLimit 条。
        return items.length > pageLimit ? items.sublist(0, pageLimit) : items;
      } catch (e) {
        lastError = e;
        // 继续重试;循环结束仍失败才抛。
      }
    }
    // 3 次都失败 → 抛异常,调用方显示"暂不可用",绝不返回假数据。
    throw lastError ?? Exception('豆瓣榜单请求失败');
  }
}
