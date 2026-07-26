/// 视频分类模型
class VideoCategory {
  final int typeId;
  final String typeName;

  /// 父分类 ID。0 表示顶级分类(自身即父)。
  ///
  /// 苹果CMS 的 class 列表里，顶级分类(pid=0，如“电影”“电视剧”)通常
  /// 是父容器、本身不挂视频，视频挂在子分类(pid≠0，如“动作片”)上。
  /// 保留 pid 才能识别父子关系，把父类查询展开成子类多选。
  final int pid;

  const VideoCategory({
    required this.typeId,
    required this.typeName,
    this.pid = 0,
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
      pid: parseInt(json['type_pid'] ?? json['typePid'] ?? json['pid']),
    );
  }

  Map<String, dynamic> toJson() => {
    'type_id': typeId,
    'type_name': typeName,
    'type_pid': pid,
  };
}
