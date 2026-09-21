/// 用户自己添加的网站收藏。
///
/// 工具页大部分条目本质上就是「打开某个网站」，所以让用户自己攒一份
/// 收藏是这个页面最自然的扩展。这份数据算用户资产，必须能导出、能分享。
class CustomSite {
  const CustomSite({
    required this.id,
    required this.title,
    required this.url,
    required this.createdAt,
  });

  final String id;
  final String title;

  /// 已规范化的地址：一定带 scheme，一定是 http/https。
  final String url;
  final int createdAt;

  /// 允许的 scheme 白名单。
  ///
  /// 这个 url 会被直接交给 WebView 加载，`javascript:` / `data:` /
  /// `file:` 分别对应「执行任意脚本」「渲染任意内嵌页面」「读本地文件」，
  /// 必须在入口就拦住 —— 等进了 WebView 再拦就晚了。
  static const _allowedSchemes = {'http', 'https'};

  /// 从用户输入构造。非法输入返回 null，由调用方给提示。
  ///
  /// 用户通常只会输 `example.com`，所以缺 scheme 时补 https 而不是判为
  /// 无效；但**不能**对 `javascript:alert(1)` 这种已经带了 scheme 的
  /// 输入补 https，否则会把危险 scheme 洗成合法地址。
  static CustomSite? tryCreate({
    required String title,
    required String url,
    int? createdAt,
    String? id,
  }) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+\-.]*:').hasMatch(trimmed);
    final candidate = hasScheme ? trimmed : 'https://$trimmed';

    final uri = Uri.tryParse(candidate);
    if (uri == null) return null;
    if (!_allowedSchemes.contains(uri.scheme.toLowerCase())) return null;
    if (uri.host.trim().isEmpty) return null;

    // scheme 与 host 统一小写（域名大小写不敏感），path/query 保持原样：
    // 很多站点的路径参数是大小写敏感的，一并小写会打开错误页面。
    final normalized = uri.replace(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host.toLowerCase(),
    );
    var cleaned = normalized.toString();
    // Uri 会把 `http://example.com` 补成带尾斜杠的形式，去掉更贴近用户输入。
    if (cleaned.endsWith('/') && normalized.path == '/' &&
        !normalized.hasQuery && !normalized.hasFragment) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }

    final finalTitle = title.trim().isEmpty ? normalized.host : title.trim();
    final stamp = createdAt ?? DateTime.now().millisecondsSinceEpoch;
    return CustomSite(
      // 用 url 当 id：同一个网址不该出现两条收藏，这样天然去重。
      id: id ?? cleaned,
      title: finalTitle,
      url: cleaned,
      createdAt: stamp,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'url': url,
    'createdAt': createdAt,
  };

  /// 宽容解析：朋友分享过来的内容可能缺字段或被手改坏，
  /// 单条坏数据不该让整次导入失败，返回 null 由调用方跳过。
  static CustomSite? fromJson(Object? json) {
    if (json is! Map) return null;
    final url = json['url'];
    if (url is! String) return null;
    final rawCreated = json['createdAt'];
    return CustomSite.tryCreate(
      title: json['title']?.toString() ?? '',
      url: url,
      createdAt: rawCreated is int
          ? rawCreated
          : int.tryParse(rawCreated?.toString() ?? ''),
      id: json['id']?.toString(),
    );
  }

  CustomSite copyWith({String? title}) => CustomSite(
    id: id,
    title: title ?? this.title,
    url: url,
    createdAt: createdAt,
  );
}
