import 'vod_item_play_parser.dart';

class VodItem {
  final int vodId;
  final int typeId;

  final String vodName;
  final String? vodPic;
  final String? vodRemarks;
  final String? vodTime;
  final String? vodYear;
  final String? vodArea;
  final String? vodLang;
  final String? vodDirector;
  final String? vodActor;
  final String? vodContent;
  final String? typeName;

  final String? vodPlayFrom;
  final String? vodPlayUrl;

  // 播放解析缓存
  List<PlaySourceGroup>? _cachedPlayUrls;

  VodItem({
    required this.vodId,
    this.typeId = 0,
    required this.vodName,
    this.vodPic,
    this.vodRemarks,
    this.vodTime,
    this.vodYear,
    this.vodArea,
    this.vodLang,
    this.vodDirector,
    this.vodActor,
    this.vodContent,
    this.typeName,
    this.vodPlayFrom,
    this.vodPlayUrl,
  });

  /// 兼容旧代码：封面别名
  String? get coverUrl => vodPic;

  /// 兼容旧代码：海报别名
  String? get posterUrl => vodPic;

  /// 解析播放列表（懒加载缓存）
  List<PlaySourceGroup> get parsePlayUrls {
    _cachedPlayUrls ??= VodItemPlayParser.parse(
      vodPlayFrom: vodPlayFrom,
      vodPlayUrl: vodPlayUrl,
    );
    return _cachedPlayUrls!;
  }

  bool get hasPlayUrls => parsePlayUrls.isNotEmpty;

  factory VodItem.fromJson(
    Map<String, dynamic> json, {
    String? baseUrl,
  }) {
    return VodItem(
      vodId: _readInt(json, const ['vod_id', 'vodId', 'id']),
      typeId: _readInt(json, const ['type_id', 'typeId']),
      vodName: _readString(
        json,
        const ['vod_name', 'vodName', 'name', 'title', 'vodTitle'],
      ),
      vodPic: _resolveMediaUrl(
        _readString(
          json,
          const [
            'vod_pic',
            'vodPic',
            'pic',
            'poster',
            'cover',
            'image',
            'img',
            'thumb',
            'posterUrl',
            'coverUrl',
            'imageUrl',
          ],
        ),
        baseUrl,
      ),
      vodRemarks: _readString(
        json,
        const ['vod_remarks', 'vodRemarks', 'remarks', 'remark'],
      ),
      vodTime: _readString(json, const ['vod_time', 'vodTime', 'time']),
      vodYear: _readString(json, const ['vod_year', 'vodYear', 'year']),
      vodArea: _readString(json, const ['vod_area', 'vodArea', 'area']),
      vodLang: _readString(json, const ['vod_lang', 'vodLang', 'lang']),
      vodDirector: _readString(
        json,
        const ['vod_director', 'vodDirector', 'director'],
      ),
      vodActor: _readString(json, const ['vod_actor', 'vodActor', 'actor']),
      vodContent: _readString(
        json,
        const ['vod_content', 'vodContent', 'content'],
      ),
      typeName: _readString(json, const ['type_name', 'typeName']),
      vodPlayFrom: _readString(
        json,
        const ['vod_play_from', 'vodPlayFrom', 'playFrom', 'play_from'],
      ),
      vodPlayUrl: _readString(
        json,
        const ['vod_play_url', 'vodPlayUrl', 'playUrl', 'play_url'],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'vod_id': vodId,
      'type_id': typeId,
      'vod_name': vodName,
      'vod_pic': vodPic,
      'vod_remarks': vodRemarks,
      'vod_time': vodTime,
      'vod_year': vodYear,
      'vod_area': vodArea,
      'vod_lang': vodLang,
      'vod_director': vodDirector,
      'vod_actor': vodActor,
      'vod_content': vodContent,
      'type_name': typeName,
      'vod_play_from': vodPlayFrom,
      'vod_play_url': vodPlayUrl,
    };
  }

  VodItem copyWith({
    int? vodId,
    int? typeId,
    String? vodName,
    String? vodPic,
    String? vodRemarks,
    String? vodTime,
    String? vodYear,
    String? vodArea,
    String? vodLang,
    String? vodDirector,
    String? vodActor,
    String? vodContent,
    String? typeName,
    String? vodPlayFrom,
    String? vodPlayUrl,
  }) {
    return VodItem(
      vodId: vodId ?? this.vodId,
      typeId: typeId ?? this.typeId,
      vodName: vodName ?? this.vodName,
      vodPic: vodPic ?? this.vodPic,
      vodRemarks: vodRemarks ?? this.vodRemarks,
      vodTime: vodTime ?? this.vodTime,
      vodYear: vodYear ?? this.vodYear,
      vodArea: vodArea ?? this.vodArea,
      vodLang: vodLang ?? this.vodLang,
      vodDirector: vodDirector ?? this.vodDirector,
      vodActor: vodActor ?? this.vodActor,
      vodContent: vodContent ?? this.vodContent,
      typeName: typeName ?? this.typeName,
      vodPlayFrom: vodPlayFrom ?? this.vodPlayFrom,
      vodPlayUrl: vodPlayUrl ?? this.vodPlayUrl,
    );
  }

  @override
  String toString() {
    return 'VodItem(vodId: $vodId, typeId: $typeId, vodName: $vodName)';
  }

  static String _readString(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = json[key];
      if (value == null) continue;

      final text = value.toString().trim();
      if (text.isEmpty || text.toLowerCase() == 'null') continue;

      return text;
    }
    return '';
  }

  static int _readInt(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = json[key];
      if (value == null) continue;

      if (value is int) return value;
      if (value is double) return value.toInt();

      final text = value.toString().trim();
      if (text.isEmpty || text.toLowerCase() == 'null') continue;

      final parsed = int.tryParse(text);
      if (parsed != null) return parsed;
    }
    return 0;
  }

  static String? _resolveMediaUrl(String? rawUrl, String? baseUrl) {
    final value = rawUrl?.trim() ?? '';
    if (value.isEmpty || value.toLowerCase() == 'null') return null;

    // 已经是绝对地址
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }

    // 协议相对地址
    if (value.startsWith('//')) {
      return 'https:$value';
    }

    // 没有 baseUrl 就原样返回
    final normalizedBase = _originBase(baseUrl);
    if (normalizedBase == null) return value;

    final path = value.startsWith('/') ? value.substring(1) : value;
    return normalizedBase.resolve(path).toString();
  }

  static Uri? _originBase(String? baseUrl) {
    final text = baseUrl?.trim() ?? '';
    if (text.isEmpty) return null;

    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;

    final origin = uri.hasPort
        ? '${uri.scheme}://${uri.host}:${uri.port}/'
        : '${uri.scheme}://${uri.host}/';

    return Uri.tryParse(origin);
  }
}