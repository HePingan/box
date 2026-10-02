// lib/daily_news_url_policy.dart
//
// DailyNewsPage 的内嵌 WebView 地址策略。
//
// 这套白名单从 `_DailyNewsPageState` 的私有静态成员里抽出来是为了能测
// （原来测不到，于是「AI 热点点开只看到视界日报门户页」这种 bug 只能靠用户报）。
//
// 抽出来之后仍然漏了一次，原因值得留下：
//   **测的是我们以为的主机，不是上游真实给的主机。**
//   上游返回的每条热点 permalink 主机是 `aihot.news`，而白名单里加的是**接口**
//   主机 `aihot.virxact.com`（2026-10-02 实测两者不是一回事：接口在 virxact，
//   条目页在 aihot.news）。用例照着白名单自己写主机字符串，
//   于是「白名单里有这一条」永远通过、「点开能看到那条热点」从来没有被验证。
//   现在的判据：用例从**真实响应快照**里取 permalink，断言它必须原样通过
//   （见 test/daily_news_page_host_allowlist_test.dart）。
//
// 第二条教训：**打不开不许静默换成别的站点**。原实现对被拒的地址一律回落
// 到「视界日报」门户页，用户点一条 AI 热点却看到另一个完全无关的资讯站，
// 既没有提示也无法自己判断 —— [DailyNewsTarget.blockedUrl] 就是为这条存在的。
library;

/// 一次打开的目标：实际要加载的地址，以及「原地址为什么没被直接采用」。
class DailyNewsTarget {
  const DailyNewsTarget({required this.uri, this.blockedUrl});

  /// 实际交给内嵌 WebView 的地址（[blockedUrl] 非空时这只是兜底值，不加载）。
  final Uri uri;

  /// 非空 = 用户点的那条链接是**站外**地址（AI 热点的原文常在 X / arXiv），
  /// 内嵌 WebView 打不开。页面必须如实说明并把原地址交给用户复制，
  /// 不许静默换成门户页 —— 那会让「点进去内容不对」变成查不出来的现象。
  final String? blockedUrl;

  bool get isBlocked => blockedUrl != null;
}

/// 内嵌 WebView 允许加载的地址策略。
class DailyNewsUrlPolicy {
  const DailyNewsUrlPolicy._();

  /// 门户页兜底地址：**只在调用方没给地址时**用（插件目录里那条「视界日报」）。
  static final Uri fallbackUri = Uri.parse(
    'https://actcpc.heytapimage.com/oh5/3/1/index.html#/',
  );

  /// 允许在内嵌 WebView 打开的主机。
  ///
  /// 只放各内容源的**站内**域名。AI 热点条目的原文链接常常是
  /// x.com / arxiv 等站外地址，故意不进名单 —— 内嵌 WebView 打不开
  /// 这类页面，放进来只会得到一个白屏；这类地址走
  /// [DailyNewsTarget.blockedUrl] 如实告知。
  static const Set<String> allowedHosts = {
    // 视界日报（历史门户入口）
    'actcpc.heytapimage.com',
    // 知乎日报：今日热闻的数据源（news-at.zhihu.com）与站点首页（daily.zhihu.com）
    'daily.zhihu.com',
    'news-at.zhihu.com',
    'news-at-cdn.zhihu.com',
    // AI HOT 条目页：署名要求回链这里。
    // 主机是 aihot.news，不是接口主机 aihot.virxact.com（2026-10-02 实测）。
    'aihot.news',
    // 旧域名：2026-10-31 前只做跳转，留着让用户手上的旧链接还能开。
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

  /// 决定这次到底加载什么、以及要不要如实告知「打不开」。
  ///
  /// - 没给地址 / 给的不是网址 → 门户页（历史行为，插件入口在用）；
  /// - 白名单内 → 原样加载；
  /// - http(s) 但站外 → [DailyNewsTarget.isBlocked]，页面展示原地址 + 复制，
  ///   不再悄悄换成门户页；
  /// - 其它 scheme（`intent://`、`javascript:`）→ 当作没有地址。
  static DailyNewsTarget decide(String? raw) {
    final trimmed = raw?.trim();
    final uri = (trimmed == null || trimmed.isEmpty)
        ? null
        : Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return DailyNewsTarget(uri: fallbackUri);
    }
    if (isAllowed(uri)) return DailyNewsTarget(uri: uri);
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'https' || scheme == 'http') {
      return DailyNewsTarget(uri: fallbackUri, blockedUrl: trimmed);
    }
    return DailyNewsTarget(uri: fallbackUri);
  }

  /// 只想要一个地址时的简写（插件入口、旧调用点用）。
  ///
  /// 注意：这条路径**看不到** isBlocked，新代码请用 [decide]，
  /// 否则又会写出「静默换成门户页」那种查不出来的行为。
  static Uri resolve(String? raw) => decide(raw).uri;
}
