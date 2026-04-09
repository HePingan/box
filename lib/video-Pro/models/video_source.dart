class VideoSource {
  final String id;
  final String name;
  final String url;
  final String detailUrl;
  final bool isEnabled;

  const VideoSource({
    required this.id,
    required this.name,
    required this.url,
    required this.detailUrl,
    this.isEnabled = true,
  });

  factory VideoSource.fromJson(Map<String, dynamic> json) {
    String asString(dynamic value, [String fallback = '']) {
      if (value == null) return fallback;
      final text = value.toString().trim();
      if (text.isEmpty || text.toLowerCase() == 'null') return fallback;
      return text;
    }

    bool asBool(dynamic value, [bool fallback = true]) {
      if (value is bool) return value;
      final text = value?.toString().trim().toLowerCase();
      if (text == null || text.isEmpty) return fallback;
      if (['1', 'true', 'yes', 'y', 'on'].contains(text)) return true;
      if (['0', 'false', 'no', 'n', 'off'].contains(text)) return false;
      return fallback;
    }

    final url = asString(
      json['url'] ??
          json['listUrl'] ??
          json['list_url'] ??
          json['apiUrl'] ??
          json['api_url'],
    );

    final detailUrl = asString(
      json['detailUrl'] ??
          json['detail_url'] ??
          json['detail'] ??
          json['apiDetail'] ??
          json['api_detail'] ??
          url,
      url,
    );

    return VideoSource(
      id: asString(json['id'] ?? json['sourceId'] ?? json['sid'] ?? url),
      name: asString(
        json['name'] ?? json['sourceName'] ?? json['title'],
        '未知源',
      ),
      url: url,
      detailUrl: detailUrl,
      isEnabled: asBool(
        json['isEnabled'] ?? json['enabled'] ?? json['status'] ?? true,
      ),
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