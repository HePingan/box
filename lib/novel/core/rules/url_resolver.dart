// URL 归一化、相对/绝对转换
import 'package:box/novel/core/novel_exceptions.dart';

class UrlResolver {
  const UrlResolver();

  String normalizeBaseUrlInput(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    if (raw.startsWith('//')) return 'https:$raw';
    return 'https://$raw';
  }

  bool isAbsoluteUrl(String value) {
    final raw = value.trim();
    return raw.startsWith('http://') || raw.startsWith('https://');
  }

  /// 是否为 data: URI（书源搜索用，base64 编码的内联数据）
  bool isDataUri(String value) {
    return value.trim().toLowerCase().startsWith('data:');
  }

  String toAbsoluteUrl(
    String input, {
    String? base,
    required String defaultBaseUrl,
  }) {
    final raw = input.trim();
    if (raw.isEmpty) return raw;
    if (isAbsoluteUrl(raw)) return raw;

    final anchor =
        (base != null && base.trim().isNotEmpty) ? base.trim() : defaultBaseUrl;

    if (anchor.isEmpty) {
      throw NovelSourceException('bookSourceUrl 为空，无法解析相对地址');
    }

    String absoluteBase;
    if (isAbsoluteUrl(anchor)) {
      absoluteBase = anchor;
    } else if (anchor.startsWith('//')) {
      final scheme = defaultBaseUrl.startsWith('https://') ? 'https' : 'http';
      absoluteBase = '$scheme:$anchor';
    } else {
      final root = normalizeBaseUrlInput(defaultBaseUrl);
      if (root.isEmpty) {
        throw NovelSourceException('bookSourceUrl 为空，无法解析相对地址');
      }
      absoluteBase = Uri.parse(root).resolve(anchor).toString();
    }

    final baseUri = Uri.parse(absoluteBase);
    if (raw.startsWith('//')) return '${baseUri.scheme}:$raw';
    return baseUri.resolve(raw).toString();
  }

  Uri resolveUri(
    String path, {
    String? base,
    required String defaultBaseUrl,
  }) {
    final raw = path.trim();
    if (raw.isEmpty) {
      final fallback = (base != null && base.trim().isNotEmpty)
          ? toAbsoluteUrl(base, defaultBaseUrl: defaultBaseUrl)
          : defaultBaseUrl;
      return Uri.parse(fallback);
    }
    return Uri.parse(toAbsoluteUrl(raw, base: base, defaultBaseUrl: defaultBaseUrl));
  }

  String absUrl(
    String path, {
    String? base,
    required String defaultBaseUrl,
  }) {
    final raw = path.trim();
    if (raw.isEmpty) return '';
    try {
      return toAbsoluteUrl(raw, base: base, defaultBaseUrl: defaultBaseUrl);
    } catch (_) {
      return raw;
    }
  }

  bool looksLikeRuleExpr(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;
    return t.startsWith(r'$') ||
        t.startsWith('@') ||
        t.startsWith('.') ||
        t.contains(r'$.') ||
        t.contains(r'$..');
  }
}
