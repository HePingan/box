import 'dart:convert';
import 'dart:typed_data';

/// 缩略图该怎么加载。
enum QuizThumbKind {
  /// 内嵌 data URL，已解出字节，直接 Image.memory。
  bytes,

  /// 远端地址，走 Image.network。
  network,

  /// 空值或脏数据，画占位图，不发请求也不解码。
  placeholder,
}

/// 题库列表缩略图取源判定。
///
/// 服务端 `image` 字段来源混杂：CDN 地址、内嵌 data URL、以及被截断或
/// 缺 base64 段的脏数据。解码放在 widget build 里做的话，一条脏数据就会
/// 抛异常糊掉整个列表项，所以这里收成纯函数：能解就解，解不了统一降级占位。
class QuizThumbImageSource {
  const QuizThumbImageSource._(this.kind, {this.bytes, this.url});

  final QuizThumbKind kind;

  /// kind == bytes 时有值。
  final Uint8List? bytes;

  /// kind == network 时有值。
  final String? url;

  static const _placeholder = QuizThumbImageSource._(
    QuizThumbKind.placeholder,
  );

  /// 解析缩略图取源。
  ///
  /// [raw] 是服务端返回的 image 字段原始值，[base] 是服务器地址（不带 path）。
  /// 支持三种格式：
  ///   1. data URL → Image.memory（内嵌）
  ///   2. 完整 http/https URL → Image.network（远端）
  ///   3. 相对路径（如 /uploads/xxx.jpg）→ 用 [base] 解析成完整 URL
  ///   4. 空值或脏数据 → 占位图
  static QuizThumbImageSource parse(String raw, {String base = ''}) {
    final image = raw.trim();
    if (image.isEmpty) return _placeholder;

    final lower = image.toLowerCase();
    if (lower.startsWith('data:')) {
      final comma = image.indexOf(',');
      // 没有逗号说明 data URL 被截断，后半段的 base64 根本不存在。
      if (comma < 0 || comma == image.length - 1) return _placeholder;
      final payload = image.substring(comma + 1).trim();
      if (payload.isEmpty) return _placeholder;
      try {
        final decoded = base64Decode(payload);
        if (decoded.isEmpty) return _placeholder;
        return QuizThumbImageSource._(QuizThumbKind.bytes, bytes: decoded);
      } on FormatException {
        // 截断或夹了非法字符的 base64：降级，不让异常冒到 build。
        return _placeholder;
      }
    }

    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return QuizThumbImageSource._(QuizThumbKind.network, url: image);
    }

    // 相对路径：用服务器地址解析成完整 URL。
    // base 应该是不带 path 的服务器地址，比如 "https://background.hpa888.top"。
    // 如果 base 为空或格式不对，直接降级占位。
    if (base.isNotEmpty) {
      try {
        final resolved = Uri.parse(base).resolve(image);
        if (resolved.scheme == 'http' || resolved.scheme == 'https') {
          return QuizThumbImageSource._(QuizThumbKind.network, url: resolved.toString());
        }
      } catch (_) {
        // 解析失败，降级占位。
      }
    }

    // 其他裸字符串（相对路径但没给 base、非法格式等）：占位。
    return _placeholder;
  }
}
