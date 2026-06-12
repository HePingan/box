import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../domain/public_api_models.dart';

class PublicApiIndexLoader {
  const PublicApiIndexLoader._();

  static const String _fullAssetPath = 'assets/data/public_apis_index.json';
  static const String _domesticAssetPath =
      'assets/data/public_apis_domestic_available.json';

  static List<PublicApiDirectoryEntry>? _fullCache;
  static List<PublicApiDirectoryEntry>? _domesticCache;

  static Future<List<PublicApiDirectoryEntry>> loadAll() async {
    if (_fullCache != null) return _fullCache!;
    _fullCache = await _load(_fullAssetPath);
    return _fullCache!;
  }

  static Future<List<PublicApiDirectoryEntry>> loadDomesticAvailable() async {
    if (_domesticCache != null) return _domesticCache!;
    _domesticCache = await _load(_domesticAssetPath);
    return _domesticCache!;
  }

  static Future<List<PublicApiDirectoryEntry>> search({
    required String query,
    String? category,
    bool noAuthOnly = true,
    bool httpsOnly = true,
    int limit = 40,
    bool domesticOnly = true,
  }) async {
    final entries = domesticOnly
        ? await loadDomesticAvailable()
        : await loadAll();
    final normalizedCategory = category?.trim().toLowerCase();
    return entries
        .where((entry) {
          if (noAuthOnly && !entry.noAuth) return false;
          if (httpsOnly && !entry.https) return false;
          if (normalizedCategory != null &&
              normalizedCategory.isNotEmpty &&
              entry.category.toLowerCase() != normalizedCategory) {
            return false;
          }
          return entry.matches(query);
        })
        .take(limit)
        .toList();
  }

  static Future<List<PublicApiDirectoryEntry>> _load(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map(
          (item) =>
              PublicApiDirectoryEntry.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }
}
