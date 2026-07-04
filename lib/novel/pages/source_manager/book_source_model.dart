import 'dart:convert';

import '../../core/kuaiyan_novel_source.dart';
import '../../core/maoyan_novel_source.dart';
import '../../core/wtzw_novel_source.dart';

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
  final String _sourceKind;

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
    String? sourceKind,
  })  : _sourceKind = sourceKind ?? _detectKind(rawJson),
        _rawJson = Map<String, dynamic>.from(rawJson);

  static String _detectKind(Map<String, dynamic> json) {
    if (WtzwNovelSource.supportsBookSourceJson(json)) return 'wtzw';
    if (MaoYanNovelSource.supportsBookSourceJson(json)) return 'maoyan';
    if (KuaiYanNovelSource.supportsBookSourceJson(json)) return 'kuaiyan';
    return 'rule';
  }

  String get id => '${_norm(bookSourceUrl)}|${_norm(bookSourceName)}|$_sourceKind';

  static String _norm(String v) => v.trim();

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
    final name = (json['bookSourceName'] ?? '').toString();
    final url = (json['bookSourceUrl'] ?? '').toString();

    return BookSourceModel(
      rawJson: json,
      bookSourceName: name,
      bookSourceUrl: url,
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
