import 'package:shared_preferences/shared_preferences.dart';

import '../../account/data/account_store.dart';
import '../../account/domain/account_models.dart';
import '../../policy/plugin_policy.dart';
import '../domain/quiz_bank.dart';
import './quiz_cloud_sync.dart';

/// 客户端「拉取/更新云端题库」协调层。
///
/// 复用账号 serverUrl（默认 background.hpa888.top），
/// 对已订阅分类做增量 sync，并记录上次结果供 UI 展示。
class QuizCloudPullCoordinator {
  QuizCloudPullCoordinator({
    QuizCloudSyncService? syncService,
    BoxAccountStore? accountStore,
  }) : _sync = syncService ?? QuizCloudSyncService(),
       _accountStore = accountStore ?? BoxAccountStore();

  static const _subscribedKey = 'quiz_cloud_subscribed_categories_v1';
  static const _lastAtKey = 'quiz_cloud_last_sync_at_v1';
  static const _lastSummaryKey = 'quiz_cloud_last_sync_summary_v1';

  final QuizCloudSyncService _sync;
  final BoxAccountStore _accountStore;

  Future<String> resolveServerUrl() async {
    final saved = await _accountStore.loadServerUrl();
    return BoxAccountDefaults.normalizeServerUrl(saved);
  }

  Future<List<String>> loadSubscribedCategories() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_subscribedKey) ?? const <String>[];
  }

  Future<void> saveSubscribedCategories(List<String> categories) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = categories
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    await prefs.setStringList(_subscribedKey, normalized);
  }

  Future<QuizCloudPullStatus> loadStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = await resolveServerUrl();
    final subscribed = await loadSubscribedCategories();
    final lastAtRaw = prefs.getString(_lastAtKey);
    final lastSummary = prefs.getString(_lastSummaryKey) ?? '';
    final localCount = await _safeLocalCount();
    return QuizCloudPullStatus(
      serverUrl: serverUrl,
      subscribedCategories: subscribed,
      localCount: localCount,
      lastSyncAt: lastAtRaw == null ? null : DateTime.tryParse(lastAtRaw),
      lastSummary: lastSummary,
    );
  }

  /// 拉取目录；若本地尚无订阅，默认订阅全部 catalog。
  Future<List<QuizCloudCatalog>> fetchCatalogs({String? serverUrl}) async {
    final url = BoxAccountDefaults.normalizeServerUrl(
      serverUrl ?? await resolveServerUrl(),
    );
    final catalogs = await _sync.fetchCatalogs(serverUrl: url);
    final subscribed = await loadSubscribedCategories();
    if (subscribed.isEmpty && catalogs.isNotEmpty) {
      await saveSubscribedCategories(
        catalogs.map((c) => c.id.isNotEmpty ? c.id : c.name).toList(),
      );
    }
    return catalogs;
  }

  /// 同步已订阅分类（为空则先拉目录并默认全订）。
  Future<QuizCloudPullResult> pullAll({
    String? serverUrl,
    List<String>? categories,
    bool resetCursor = false,
    void Function(String message)? onProgress,
  }) async {
    final denial = await PluginGate.denial(
      PluginIds.quizBankView,
      feature: PluginFeature.cloudPull,
    );
    if (denial != null) {
      throw QuizCloudSyncException(denial);
    }
    final url = BoxAccountDefaults.normalizeServerUrl(
      serverUrl ?? await resolveServerUrl(),
    );
    onProgress?.call(resetCursor ? '重置游标并获取目录…' : '获取题库目录…');
    final catalogs = await _sync.fetchCatalogs(serverUrl: url);

    var targets = categories
            ?.map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        await loadSubscribedCategories();

    if (targets.isEmpty) {
      targets = catalogs
          .map((c) => c.id.isNotEmpty ? c.id : c.name)
          .where((e) => e.isNotEmpty)
          .toList();
      if (targets.isNotEmpty) {
        await saveSubscribedCategories(targets);
      }
    }

    // 云端若暂时没有分类目录，仍尝试一次“全库增量”（不带 category）。
    if (targets.isEmpty) {
      onProgress?.call(resetCursor ? '全量重拉全库…' : '同步全库增量…');
      final single = await _sync.sync(
        serverUrl: url,
        resetCursor: resetCursor,
      );
      final localCount = await _reloadAndCount(fallback: single.inserted);
      final result = QuizCloudPullResult(
        serverUrl: url,
        categories: const [''],
        inserted: single.inserted,
        cloudDeletes: single.cloudDeletes,
        imagesCached: single.imagesCached,
        imageFailures: single.imageFailures,
        pages: single.pages,
        catalogCount: catalogs.length,
        localCount: localCount,
        resetCursor: resetCursor,
      );
      await _persistResult(result);
      return result;
    }

    var inserted = 0;
    var cloudDeletes = 0;
    var imagesCached = 0;
    var imageFailures = 0;
    var pages = 0;
    for (var i = 0; i < targets.length; i++) {
      final category = targets[i];
      onProgress?.call(
        resetCursor
            ? '全量重拉 ${i + 1}/${targets.length}：$category'
            : '同步 ${i + 1}/${targets.length}：$category',
      );
      final part = await _sync.sync(
        serverUrl: url,
        category: category,
        resetCursor: resetCursor,
      );
      inserted += part.inserted;
      cloudDeletes += part.cloudDeletes;
      imagesCached += part.imagesCached;
      imageFailures += part.imageFailures;
      pages += part.pages;
    }

    final localCount = await _reloadAndCount(fallback: inserted);
    final result = QuizCloudPullResult(
      serverUrl: url,
      categories: targets,
      inserted: inserted,
      cloudDeletes: cloudDeletes,
      imagesCached: imagesCached,
      imageFailures: imageFailures,
      pages: pages,
      catalogCount: catalogs.length,
      localCount: localCount,
      resetCursor: resetCursor,
    );
    await _persistResult(result);
    return result;
  }

  /// 仅补图：扫描本地远程图/缺失本地文件并下载。
  Future<QuizCloudImageRepairResult> repairImages({
    String? serverUrl,
    void Function(String message)? onProgress,
  }) async {
    final url = BoxAccountDefaults.normalizeServerUrl(
      serverUrl ?? await resolveServerUrl(),
    );
    onProgress?.call('扫描并补全题图…');
    final result = await _sync.repairImages(serverUrl: url);
    onProgress?.call(
      '补图完成：扫描 ${result.scanned} · 成功 ${result.cached} · 失败 ${result.failed}',
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastAtKey, DateTime.now().toIso8601String());
    await prefs.setString(
      _lastSummaryKey,
      '仅补图：扫描 ${result.scanned} · 成功 ${result.cached} · 失败 ${result.failed}',
    );
    return result;
  }

  Future<int> _reloadAndCount({required int fallback}) async {
    try {
      await QuizBankCache.instance.reload();
      return QuizBankCache.instance.items.length;
    } catch (_) {
      return fallback;
    }
  }

  Future<int> _safeLocalCount() async {
    try {
      return (await QuizBankStorage.loadAll()).length;
    } catch (_) {
      try {
        return QuizBankCache.instance.items.length;
      } catch (_) {
        return 0;
      }
    }
  }

  Future<void> _persistResult(QuizCloudPullResult result) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastAtKey, DateTime.now().toIso8601String());
    await prefs.setString(_lastSummaryKey, result.summaryText);
  }

  void dispose() => _sync.dispose();
}

class QuizCloudPullStatus {
  const QuizCloudPullStatus({
    required this.serverUrl,
    required this.subscribedCategories,
    required this.localCount,
    required this.lastSummary,
    this.lastSyncAt,
  });

  final String serverUrl;
  final List<String> subscribedCategories;
  final int localCount;
  final DateTime? lastSyncAt;
  final String lastSummary;

  String get lastSyncLabel {
    final at = lastSyncAt;
    if (at == null) return '尚未同步';
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class QuizCloudPullResult {
  const QuizCloudPullResult({
    required this.serverUrl,
    required this.categories,
    required this.inserted,
    required this.cloudDeletes,
    required this.catalogCount,
    required this.localCount,
    this.imagesCached = 0,
    this.imageFailures = 0,
    this.pages = 0,
    this.resetCursor = false,
  });

  final String serverUrl;
  final List<String> categories;
  final int inserted;
  final int cloudDeletes;
  final int imagesCached;
  final int imageFailures;
  final int pages;
  final int catalogCount;
  final int localCount;
  final bool resetCursor;

  String get summaryText {
    final cat = categories.where((e) => e.isNotEmpty).join('、');
    final scope = cat.isEmpty ? '全库' : cat;
    final mode = resetCursor ? '全量' : '增量';
    return '$mode · 新增 $inserted · 补图 $imagesCached'
        '${imageFailures > 0 ? " · 图失败 $imageFailures" : ""}'
        ' · 本地 $localCount · $scope';
  }
}
