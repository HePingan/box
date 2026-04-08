// models/video_category.dart

/// 文件功能：定义视频分类模型
/// 对应苹果CMS接口中的 "class" 字段数据
class VideoCategory {
  final int typeId;
  final String typeName;

  VideoCategory({
    required this.typeId,
    required this.typeName,
  });

  factory VideoCategory.fromJson(Map<String, dynamic> json) {
    return VideoCategory(
      // 兼容有些接口传 String 有些传 int 的情况
      typeId: json['type_id'] is int ? json['type_id'] : int.parse(json['type_id'].toString()),
      typeName: json['type_name'] ?? '全部',
    );
  }
}