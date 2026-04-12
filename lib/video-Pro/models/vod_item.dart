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

  // 🏆 优化：添加解析缓存，使得复杂字符串操作一个视频生命周期内最多只执行一次！
  List<PlaySourceGroup>? _cachedPlayUrls;

  VodItem({ // 移除 const
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

  /// 解析播放列表（使用懒加载缓存）
  List<PlaySourceGroup> get parsePlayUrls {
    _cachedPlayUrls ??= VodItemPlayParser.parse(
      vodPlayFrom: vodPlayFrom,
      vodPlayUrl: vodPlayUrl,
    );
    return _cachedPlayUrls!;
  }

  bool get hasPlayUrls => parsePlayUrls.isNotEmpty;

  // ... 下方的 fromJson 和 toJson、_readString 等提取方法保持你原来的代码完全不变即可 ...
  // (为节约字数我不重复贴 fromJson 等固定模板代码，你直接保留原样)

  factory VodItem.fromJson(Map<String, dynamic> json) {
    return VodItem(
      vodId: _readInt(json, const ['vod_id', 'vodId', 'id']),
      typeId: _readInt(json, const ['type_id', 'typeId']),
      vodName: _readString(json, const ['vod_name', 'vodName', 'name']),
      vodPic: _readString(json, const ['vod_pic', 'vodPic', 'pic']),
      vodRemarks: _readString(
        json,
        const ['vod_remarks', 'vodRemarks', 'remarks', 'remark'],
      ),
      vodTime: _readString(json, const ['vod_time', 'vodTime']),
      vodYear: _readString(json, const ['vod_year', 'vodYear']),
      vodArea: _readString(json, const ['vod_area', 'vodArea']),
      vodLang: _readString(json, const ['vod_lang', 'vodLang']),
      vodDirector: _readString(json, const ['vod_director', 'vodDirector']),
      vodActor: _readString(json, const ['vod_actor', 'vodActor']),
      vodContent: _readString(json, const ['vod_content', 'vodContent']),
      typeName: _readString(json, const ['type_name', 'typeName']),
      vodPlayFrom: _readString(
        json,
        const ['vod_play_from', 'vodPlayFrom', 'playFrom'],
      ),
      vodPlayUrl: _readString(
        json,
        const ['vod_play_url', 'vodPlayUrl', 'playUrl'],
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

      final text = value.toString().trim();
      if (text.isEmpty || text.toLowerCase() == 'null') continue;

      final parsed = int.tryParse(text);
      if (parsed != null) return parsed;
    }
    return 0;
  }
}