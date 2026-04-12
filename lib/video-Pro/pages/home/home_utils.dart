import 'package:flutter/foundation.dart';

import '../../models/video_source.dart';
import '../../models/vod_item.dart';
// 💥 注意：我已经移除了 video_api_service.dart 的引入，彻底切断在 UI 渲染层发起 API 请求的可能！

const String kFallbackCatalogUrl =
    'https://raw.githubusercontent.com/ZhuBaiwan-oOZZXX/OuonnkiTV-Source/main/tv_source/OuonnkiTV/full-noadult.json';

const List<String> kHomeNsfwKeywords = [
  '伦理', '三级', '写真', '热舞', '福利', '激情', '成人',
  '两性', '情色', '午夜', '限制级', '禁片', 'VIP', '擦边',
];

// ✅ 优化点 1：预编译正则表达式
// 利用底层 C++ 正则引擎，将原本 O(N) 的 List 连环 contains 遍历，转化为极速的正则匹配
final RegExp _nsfwRegex = RegExp(
  kHomeNsfwKeywords.join('|'), 
  caseSensitive: false,
);

bool isSafeContent(String? text) {
  if (text == null || text.trim().isEmpty) return true;
  
  // 极速匹配：只要命中任何一个敏感词集，立刻返回 false
  return !_nsfwRegex.hasMatch(text);
}

String? resolveImageUrl(String? rawUrl, VideoSource source) {
  if (rawUrl == null) return null;

  var url = rawUrl.trim().replaceAll('\\', '');
  if (url.isEmpty) return null;

  if (url.startsWith('//')) {
    return 'https:$url';
  }

  final parsed = Uri.tryParse(url);
  if (parsed != null && parsed.hasScheme) {
    return url;
  }

  final baseUrls = <String>[
    source.detailUrl.trim(),
    source.url.trim(),
  ];

  for (final base in baseUrls) {
    if (base.isEmpty) continue;

    final baseUri = Uri.tryParse(base);
    if (baseUri == null || !baseUri.hasScheme) continue;

    try {
      return baseUri.resolve(url).toString();
    } catch (_) {
      // 继续尝试下一个 base
    }
  }

return url;
}

// 💥 彻底干掉 Future，直接变成极速的同步字符串解析方法：
String? resolveVideoCoverSync(VodItem video, VideoSource source) {
  final direct = resolveImageUrl(video.vodPic, source);
  if (direct != null && direct.isNotEmpty) {
    return direct;
  }
  return null;
}