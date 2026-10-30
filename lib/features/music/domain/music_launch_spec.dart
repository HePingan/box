import 'dart:convert';

/// 音乐入口的启动参数（插件 payload → 页面）。
///
/// 为什么需要它：`openMusic` 原先只打开音乐页，payload 被**完全丢弃** ——
/// 于是市场里「专注白噪音 / 睡眠电台」这种插件只能写 `toast` 当占位。
/// 现在插件可以把「播哪一条」写进 payload，点一下就直接播。
///
/// 支持的写法（都容错，解析失败不抛异常，页面按"没给参数"处理）：
///
/// ```text
/// https://example.com/a.mp3                      // 纯字符串 = URL
/// {"url":"https://...","title":"专注白噪音","autoplay":true,"loop":true}
/// {"link":"https://...","name":"睡眠电台"}        // url/link/href + title/name 都认
/// ```
///
/// 只接受 http(s)：`file://`、`javascript:`、`content:` 一律判为无效 ——
/// 市场条目是外部投稿，不能成为任意本地读取或脚本执行的入口。
class MusicLaunchSpec {
  const MusicLaunchSpec({
    this.url = '',
    this.title = '',
    this.autoPlay = false,
    this.loop = false,
  });

  final String url;
  final String title;
  final bool autoPlay;
  final bool loop;

  bool get isEmpty => url.isEmpty;

  /// 解析失败的原始内容（非空表示"用户给了东西但不可用"，页面可提示）。
  static const MusicLaunchSpec empty = MusicLaunchSpec();

  static MusicLaunchSpec parse(String? payload) {
    final text = (payload ?? '').trim();
    if (text.isEmpty) return empty;

    if (text.startsWith('{')) {
      Object? decoded;
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        return empty;
      }
      if (decoded is! Map) return empty;

      final rawUrl = _firstNonEmpty([
        decoded['url'],
        decoded['link'],
        decoded['href'],
        decoded['src'],
      ]);
      final title = _firstNonEmpty([
        decoded['title'],
        decoded['name'],
        decoded['label'],
      ]);
      return MusicLaunchSpec(
        url: _normalizeUrl(rawUrl),
        title: title,
        autoPlay: _asBool(decoded['autoplay'] ?? decoded['autoPlay']),
        loop: _asBool(decoded['loop']),
      );
    }

    // 非 JSON：整串当 URL（作者最省事的写法）
    return MusicLaunchSpec(url: _normalizeUrl(text), autoPlay: true);
  }

  /// 只放行 http/https，并去掉首尾空白。
  static String _normalizeUrl(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return '';
    final lower = url.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return '';
    }
    // 至少要有个主机名，避免 "https://" 这种半截串被当成有效地址
    if (url.length <= (lower.startsWith('https://') ? 8 : 7)) return '';
    return url;
  }

  static String _firstNonEmpty(List<Object?> values) {
    for (final v in values) {
      final text = v?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static bool _asBool(Object? value) {
    if (value is bool) return value;
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == 'true' || text == '1' || text == 'yes';
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        if (title.isNotEmpty) 'title': title,
        'autoplay': autoPlay,
        'loop': loop,
      };

  @override
  String toString() =>
      'MusicLaunchSpec(url=$url, title=$title, autoPlay=$autoPlay, loop=$loop)';
}
