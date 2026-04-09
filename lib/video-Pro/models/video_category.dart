/// 视频分类模型
class VideoCategory {
  final int typeId;
  final String typeName;

  const VideoCategory({
    required this.typeId,
    required this.typeName,
  });

  factory VideoCategory.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString().trim()) ?? 0;
    }

    String parseString(dynamic value, [String fallback = '全部']) {
      final text = value?.toString().trim();
      if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
        return fallback;
      }
      return text;
    }

    return VideoCategory(
      typeId: parseInt(
        json['type_id'] ??
            json['typeId'] ??
            json['id'] ??
            json['tid'] ??
            json['type'],
      ),
      typeName: parseString(
        json['type_name'] ?? json['typeName'] ?? json['name'] ?? json['title'],
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'type_id': typeId,
        'type_name': typeName,
      };
}