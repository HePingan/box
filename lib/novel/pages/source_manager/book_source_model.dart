import 'dart:convert';

class BookSourceModel {
  final Map<String, dynamic> _rawJson;

  final String bookSourceName;
  final String bookSourceUrl;
  final String bookSourceGroup;
  final String searchUrl;
  final String exploreUrl;
  final bool enabled;
  final int weight;
  final int customOrder;

  BookSourceModel({
    required Map<String, dynamic> rawJson,
    required this.bookSourceName,
    required this.bookSourceUrl,
    required this.bookSourceGroup,
    required this.searchUrl,
    required this.exploreUrl,
    required this.enabled,
    required this.weight,
    required this.customOrder,
  }) : _rawJson = Map<String, dynamic>.from(rawJson);

  String get id => '${bookSourceUrl.trim()}|${bookSourceName.trim()}';

  Map<String, dynamic> toJson() {
    final json = Map<String, dynamic>.from(_rawJson);

    json['bookSourceName'] = bookSourceName;
    json['bookSourceUrl'] = bookSourceUrl;
    json['bookSourceGroup'] = bookSourceGroup;
    json['searchUrl'] = searchUrl;
    json['exploreUrl'] = exploreUrl;
    json['enabled'] = enabled;
    json['weight'] = weight;
    json['customOrder'] = customOrder;

    return json;
  }

  String toRawJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory BookSourceModel.fromJson(Map<String, dynamic> json) {
    return BookSourceModel(
      rawJson: json,
      bookSourceName: (json['bookSourceName'] ?? '').toString(),
      bookSourceUrl: (json['bookSourceUrl'] ?? '').toString(),
      bookSourceGroup: (json['bookSourceGroup'] ?? '').toString(),
      searchUrl: (json['searchUrl'] ?? '').toString(),
      exploreUrl: (json['exploreUrl'] ?? '').toString(),
      enabled: _toBool(json['enabled'], defaultValue: true),
      weight: _toInt(json['weight']),
      customOrder: _toInt(json['customOrder']),
    );
  }

  BookSourceModel copyWith({
    Map<String, dynamic>? rawJson,
    String? bookSourceName,
    String? bookSourceUrl,
    String? bookSourceGroup,
    String? searchUrl,
    String? exploreUrl,
    bool? enabled,
    int? weight,
    int? customOrder,
  }) {
    return BookSourceModel(
      rawJson: rawJson ?? toJson(),
      bookSourceName: bookSourceName ?? this.bookSourceName,
      bookSourceUrl: bookSourceUrl ?? this.bookSourceUrl,
      bookSourceGroup: bookSourceGroup ?? this.bookSourceGroup,
      searchUrl: searchUrl ?? this.searchUrl,
      exploreUrl: exploreUrl ?? this.exploreUrl,
      enabled: enabled ?? this.enabled,
      weight: weight ?? this.weight,
      customOrder: customOrder ?? this.customOrder,
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  static bool _toBool(dynamic value, {bool defaultValue = false}) {
    if (value is bool) return value;
    final text = '${value ?? ''}'.trim().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
    return defaultValue;
  }
}