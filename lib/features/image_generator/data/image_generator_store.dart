import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/image_generator_models.dart';

class ImageGeneratorStore {
  const ImageGeneratorStore();

  static const String _draftKey = 'image_generator.draft.v1';
  static const String _historyKey = 'image_generator.history.v1';
  static const int _historyLimit = 12;

  Future<ImageGeneratorDraft> loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftKey);
    if (raw == null || raw.trim().isEmpty) {
      return ImageGeneratorDraft.defaults();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return ImageGeneratorDraft.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return ImageGeneratorDraft.defaults();
  }

  Future<void> saveDraft(ImageGeneratorDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftKey, jsonEncode(draft.toJson()));
  }

  Future<void> resetDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
  }

  Future<List<ImageGenerationHistoryItem>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_historyKey) ?? const [];
    final result = <ImageGenerationHistoryItem>[];
    for (final raw in rawList) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final item = ImageGenerationHistoryItem.fromJson(
            Map<String, dynamic>.from(decoded),
          );
          if (item.prompt.trim().isNotEmpty || item.hasImages) {
            result.add(item);
          }
        }
      } catch (_) {}
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result.take(_historyLimit).toList();
  }

  Future<List<ImageGenerationHistoryItem>> addHistory(
    ImageGenerationHistoryItem item,
  ) async {
    final current = await loadHistory();
    final next = [item, ...current].take(_historyLimit).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _historyKey,
      next.map((e) => e.toJsonString()).toList(),
    );
    return next;
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }
}
