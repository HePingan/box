// lib/daily_news_url_policy.dart
//
// DailyNewsPage 的内嵌 WebView 地址策略。
//
// 原先这套白名单是 _DailyNewsPageState 的私有静态成员，测不到，
// 结果「AI 热点点开只能看到视界日报门户页」这个 bug 一直没被发现：
// 这页最早只服务「今日热闻」，白名单里只有视界日报和知乎日报；
// 后来 AI 热点复用了同一个页面，permalink 主机不在名单里就被
// 静默 fallback 掉了。抽成纯函数后可测。
library;

/// 内嵌 WebView 允许加载的地址策略。
class DailyNewsUrlPolicy {
  const DailyNewsUrlPolicy._();

  /// 门户页兜底地址：initialUrl 缺失或不被允许时加载这个。
  static final Uri fallbackUri = Uri.parse(
    'https://actcpc.heytapimage.com/oh5/3/1/index.html#/',
  );

  /// 允许在内嵌 WebView 打开的主机。
  ///
  /// 只放各内容源的**站内**域名。AI 热点条目的 `url` 字段常常是
  /// x.com / arxiv 等站外原文，故意不进名单——内嵌 WebView 打不开
  /// 这类页面，放进来只会得到一个白屏。
  static const Set<String> allowedHosts = {
    // 视界日报
    'actcpc.heytapimage.com',
    // 知乎日报
    'daily.zhihu.com',
    'news-at.zhihu.com',
    'news-at-cdn.zhihu.com',
    // AI HOT：站内 permalink（署名要求回链这里）
    'aihot.virxact.com',
  };

  /// 是否允许加载 [uri]。
  static bool isAllowed(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http') return false;

    final host = uri.host.toLowerCase();
    return allowedHosts.any(
      (allowed) => host == allowed || host.endsWith('.$allowed'),
    );
  }

  /// 把 [raw] 解析成实际要加载的地址，不可用时回落到门户页。
  static Uri resolve(String? raw) {
    final trimmed = raw?.trim();
    final uri = trimmed == null || trimmed.isEmpty
        ? null
        : Uri.tryParse(trimmed);
    if (uri == null || !isAllowed(uri)) return fallbackUri;
    return uri;
  }
}
