import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../novel_module.dart';

/// 内置书源 JSON 路径（首次启动时自动导入）
const String _bundledSource = 'assets/data/maoyan_book_source.json';

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

      var allSources = BookSourceManager.decodeStoredList(raw)
        ..sort(BookSourceManager.sortComparator);

      // 首次启动：自动导入内置书源
      if (allSources.isEmpty) {
        final imported = await _importBundledSource(prefs);
        if (imported.isNotEmpty) {
          allSources = imported;
        }
      }

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

      // 启动时不走网络检测，仅基于缓存健康状态做初步过滤
      // （用户可在管理页手动触发「全部检测」）
      String configMsg = '已加载书源：${source.bookSourceName}';

      NovelModule.configureRuleSource(bookSourceJson: source.toJson());

      return BookSourceBootstrapResult(
        configured: true,
        message: configMsg,
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

  /// 从内置 asset 导入书源，返回导入后的列表
  static Future<List<BookSourceModel>> _importBundledSource(
    SharedPreferences prefs,
  ) async {
    try {
      final jsonStr = await rootBundle.loadString(_bundledSource);
      final decoded = jsonDecode(jsonStr);

      BookSourceModel source;
      if (decoded is Map<String, dynamic>) {
        source = BookSourceModel.fromJson(decoded);
      } else if (decoded is Map) {
        source = BookSourceModel.fromJson(Map<String, dynamic>.from(decoded));
      } else {
        debugPrint('内置书源 JSON 格式错误');
        return [];
      }

      // 确保启用
      final updated = BookSourceModel(
        rawJson: source.toJson(),
        bookSourceName: source.bookSourceName,
        bookSourceUrl: source.bookSourceUrl,
        bookSourceGroup: source.bookSourceGroup,
        searchUrl: source.searchUrl,
        exploreUrl: source.exploreUrl,
        enabled: true,
        weight: 10,
        customOrder: 0,
      );

      // 保存到 SharedPreferences
      final manager = BookSourceManager(prefs);
      await manager.addOrUpdate(updated);
      await manager.save();

      debugPrint('内置书源已导入: ${updated.bookSourceName}');
      return [updated];
    } catch (e, st) {
      debugPrint('导入内置书源失败: $e');
      debugPrint('$st');
      return [];
    }
  }
}
