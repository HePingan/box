class VodItem {
  final int vodId;
  final String vodName;
  final String? typeName;
  final String? vodPic;
  final String? vodRemarks;
  final String? vodTime;
  final String? vodPlayFrom;
  final String? vodPlayUrl;

  VodItem({
    required this.vodId,
    required this.vodName,
    this.typeName,
    this.vodPic,
    this.vodRemarks,
    this.vodTime,
    this.vodPlayFrom,
    this.vodPlayUrl,
  });

  factory VodItem.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic value) {
      if (value is int) return value;
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    String? asNullableString(dynamic value) {
      if (value == null) return null;
      final text = value.toString().trim();
      return text.isEmpty ? null : text;
    }

    return VodItem(
      vodId: asInt(json['vod_id'] ?? json['id'] ?? json['vodId']),
      vodName: (json['vod_name'] ?? json['name'] ?? json['vodName'] ?? '未知标题')
          .toString(),
      typeName: asNullableString(json['type_name'] ?? json['typeName']),
      vodPic: asNullableString(json['vod_pic'] ?? json['pic'] ?? json['vodPic']),
      vodRemarks: asNullableString(json['vod_remarks'] ?? json['remarks'] ?? json['vodRemarks']),
      vodTime: asNullableString(json['vod_time'] ?? json['time'] ?? json['vodTime']),
      vodPlayFrom:
          asNullableString(json['vod_play_from'] ?? json['playFrom'] ?? json['vodPlayFrom']),
      vodPlayUrl:
          asNullableString(json['vod_play_url'] ?? json['playUrl'] ?? json['vodPlayUrl']),
    );
  }

  /// 完美兼容各种奇葩格式数据源的集数解析器
  List<Map<String, String>> get parsePlayUrls {
    if (vodPlayUrl == null || vodPlayUrl!.trim().isEmpty) return [];

    // 1. 如果源里包含 $$$ (表示有多条播放线路，比如 极速线$$$备用线)，我们先取第一条可用线路的数据
    String targetUrls = vodPlayUrl!;
    if (targetUrls.contains('\$\$\$')) {
      targetUrls = targetUrls.split('\$\$\$').first;
    }

    final result = <Map<String, String>>[];
    // 2. 不同的集数之间是用 # 隔开的
    final episodes = targetUrls.split('#');

    for (final episode in episodes) {
      final item = episode.trim();
      if (item.isEmpty) continue;

      // 3. 集数和视频真实URL之间，是用 $ 隔开的 (例如： 第1集$http://xxxx)
      final splitParts = item.split('\$');
      if (splitParts.length >= 2) {
        final name = splitParts[0].trim().isEmpty ? '正片' : splitParts[0].trim();
        final url = splitParts[1].trim();
        if (url.isNotEmpty) {
          result.add({'name': name, 'url': url});
        }
      } else {
        result.add({'name': '正片', 'url': item});
      }
    }

    return result;
  }
}