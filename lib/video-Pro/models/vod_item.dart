/// 文件功能：定义视频/节目条目模型
/// 对应苹果CMS标准字段：vod_id, vod_name, vod_play_url 等
class VodItem {
  final int vodId;
  final String vodName;
  final String? typeName;      // 分类（如：大陆综艺）
  final String? vodPic;       // 海报图片
  final String? vodRemarks;   // 更新状态（如：更新至第8期）
  final String? vodTime;      // 更新时间
  final String? vodPlayFrom;  // 播放来源标识（如：wjm3u8）
  final String? vodPlayUrl;   // 原始播放链接字符串

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

  // 解析列表数据 (截图 3 结构)
  factory VodItem.fromJson(Map<String, dynamic> json) {
    return VodItem(
      vodId: json['vod_id'] is int ? json['vod_id'] : int.parse(json['vod_id'].toString()),
      vodName: json['vod_name'] ?? '未知标题',
      typeName: json['type_name'],
      vodPic: json['vod_pic'],
      vodRemarks: json['vod_remarks'],
      vodTime: json['vod_time'],
      vodPlayFrom: json['vod_play_from'],
      vodPlayUrl: json['vod_play_url'],
    );
  }

  // 特殊方法：解析播放列表
  // 苹果CMS 格式通常为: 线路1$url1#线路2$url2
  List<Map<String, String>> get parsePlayUrls {
    if (vodPlayUrl == null || vodPlayUrl!.isEmpty) return [];
    List<Map<String, String>> result = [];
    
    // 先按 # 分割集数/线路
    List<String> episodes = vodPlayUrl!.split('#');
    for (var episode in episodes) {
      // 再按 $ 分割名称和链接
      List<String> parts = episode.split('\$');
      if (parts.length >= 2) {
        result.add({
          "name": parts[0],
          "url": parts[1]
        });
      } else {
        result.add({
          "name": "正片",
          "url": parts[0]
        });
      }
    }
    return result;
  }
}