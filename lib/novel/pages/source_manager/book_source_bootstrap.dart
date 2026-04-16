import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../novel_module.dart';
import 'book_source_manager.dart';
import 'book_source_model.dart';

class BookSourceBootstrapResult {
  final bool configured;
  final String message;
  final BookSourceModel? source;

  const BookSourceBootstrapResult({
    required this.configured,
    this.message = '',
    this.source,
  });
}

class BookSourceBootstrap {
  const BookSourceBootstrap._();

  static Future<BookSourceBootstrapResult> loadAndConfigure(
    SharedPreferences prefs,
  ) async {
    try {
      final raw = prefs.getString(BookSourceManager.storageKey);
      final currentId = prefs.getString(BookSourceManager.currentSourceKey);

      final allSources = BookSourceManager.decodeStoredList(raw)
        ..sort(BookSourceManager.sortComparator);

      if (allSources.isEmpty) {
        return const BookSourceBootstrapResult(
          configured: false,
          message: '还没有导入任何书源，请先导入规则书源 JSON。',
        );
      }

      final enabledSources = allSources.where((e) => e.enabled).toList();
      if (enabledSources.isEmpty) {
        return const BookSourceBootstrapResult(
          configured: false,
          message: '已导入书源，但没有启用项，请先启用一个书源。',
        );
      }

      BookSourceModel? source;

      if (currentId != null && currentId.trim().isNotEmpty) {
        for (final item in enabledSources) {
          if (item.id == currentId) {
            source = item;
            break;
          }
        }
      }

      source ??= enabledSources.first;

      NovelModule.configureRuleSource(
        bookSourceJson: source.toJson(),
      );

      return BookSourceBootstrapResult(
        configured: true,
        message: '已加载书源：${source.bookSourceName}',
        source: source,
      );
    } catch (e, st) {
      debugPrint('书源启动配置失败: $e');
      debugPrint('$st');

      return BookSourceBootstrapResult(
        configured: false,
        message: '启动时加载书源失败：$e',
      );
    }
  }
}