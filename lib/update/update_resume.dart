// 更新包下载的**续传判定**（纯逻辑，可单测）。
//
// 为什么需要它：27MB 的包在手机上断一次（切后台、切网络、地铁进隧道）就得从 0 再来。
// 用户 2026-09-29 报的就是这个 ——「只能重新再次下载更新」。更新站的包支持 Range
// （实测响应头 `accept-ranges: bytes`），所以能接着下。

import 'dart:convert';

/// 上一次下到一半时留下的记录（存在 `<包路径>.part.meta`）。
class UpdateResumeState {
  const UpdateResumeState({this.etag, this.lastModified, this.totalBytes});

  /// 服务端给的包标识（换了包就会变）。
  final String? etag;
  final String? lastModified;

  /// 整包多大（上次响应里知道的）。
  final int? totalBytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'etag': etag,
    'lastModified': lastModified,
    'totalBytes': totalBytes,
  };

  /// 解析（坏数据返回 null：续传是省流量，不是正确性的前提）。
  static UpdateResumeState? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final total = raw['totalBytes'];
    return UpdateResumeState(
      etag: raw['etag'] is String ? raw['etag'] as String : null,
      lastModified: raw['lastModified'] is String
          ? raw['lastModified'] as String
          : null,
      totalBytes: total is int && total > 0 ? total : null,
    );
  }

  /// 从磁盘上的文本解析。
  static UpdateResumeState? decode(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    try {
      return fromJson(jsonDecode(text));
    } on FormatException {
      return null;
    }
  }

  String encode() => jsonEncode(toJson());
}

/// 续传要带的请求头（没有可续的就 null = 从头下）。
///
/// `If-Range` 必须带：不带的话服务端可能按旧偏移给**新包**的数据，
/// 拼出来的 APK 哈希对不上，用户每次重试都以"下载失败"收场。
/// 带上它，包变了服务端就会整包重发（200），我们就从头写。
Map<String, String>? resumeHeaders({
  required int partBytes,
  required UpdateResumeState? state,
}) {
  if (!canResume(partBytes: partBytes, state: state)) return null;
  final headers = <String, String>{'Range': 'bytes=$partBytes-'};
  final validator = ifRangeValue(state);
  if (validator != null) headers['If-Range'] = validator;
  return headers;
}

/// 这次的半成品能不能接着下。
bool canResume({required int partBytes, required UpdateResumeState? state}) {
  if (partBytes <= 0) return false;
  final total = state?.totalBytes;
  // 已经和整包一样大：上次其实下完了、只是没走到改名那一步 —— 直接整包重写更省事。
  if (total != null && partBytes >= total) return false;
  return true;
}

/// `If-Range` 的取值：优先 ETag，退而求其次 Last-Modified；都没有就不带。
String? ifRangeValue(UpdateResumeState? state) {
  final etag = state?.etag?.trim();
  if (etag != null && etag.isNotEmpty) return etag;
  final lastModified = state?.lastModified?.trim();
  return (lastModified != null && lastModified.isNotEmpty) ? lastModified : null;
}

/// `Content-Range: bytes 100-999/1000` → 起点 100。
int? startFromContentRange(String? value) => _contentRange(value)?.$1;

/// `Content-Range: bytes 100-999/1000` → 整包长度 1000。
int? totalFromContentRange(String? value) => _contentRange(value)?.$2;

/// 206 才叫"接上了"（200 = 服务端整包重发）。
bool isPartialContent(int? statusCode) => statusCode == 206;

/// 解析 `bytes <start>-<end>/<total>`；`*` 或写错就返回 null。
(int, int?)? _contentRange(String? value) {
  final text = value?.trim();
  if (text == null || !text.startsWith('bytes ')) return null;
  final body = text.substring('bytes '.length);
  final slash = body.indexOf('/');
  if (slash < 0) return null;
  final range = body.substring(0, slash);
  final dash = range.indexOf('-');
  if (dash < 0) return null;
  final start = int.tryParse(range.substring(0, dash).trim());
  if (start == null || start < 0) return null;
  final totalText = body.substring(slash + 1).trim();
  if (totalText == '*') return (start, null);
  final total = int.tryParse(totalText);
  return (start, (total != null && total > 0) ? total : null);
}
