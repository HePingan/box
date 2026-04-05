/// 文件功能：定义资源站配置模型
/// 对应地址：https://raw.githubusercontent.com/.../full-noadult.json
class VideoSource {
  final String id;
  final String name;
  final String url; // 列表接口地址
  final String detailUrl; // 详情接口地址
  final bool isEnabled;

  VideoSource({
    required this.id,
    required this.name,
    required this.url,
    required this.detailUrl,
    this.isEnabled = true,
  });

  // 从 JSON 转换
  factory VideoSource.fromJson(Map<String, dynamic> json) {
    return VideoSource(
      id: json['id'] ?? '',
      name: json['name'] ?? '未知源',
      url: json['url'] ?? '',
      detailUrl: json['detailUrl'] ?? '',
      isEnabled: json['isEnabled'] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'detailUrl': detailUrl,
    'isEnabled': isEnabled,
  };
}