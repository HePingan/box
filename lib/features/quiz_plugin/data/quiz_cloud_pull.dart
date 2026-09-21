import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/app_logger.dart';
import '../../../utils/log_channels.dart';

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

  /// 只读拉一次云端目录（供覆盖率自检）。失败时抛出，由调用方静默处理。
  Future<List<QuizCloudCatalog>> fetchCatalogSnapshot() async {
    final url = await resolveServerUrl();
    return _sync.fetchCatalogs(serverUrl: url);
  }

  /// 是否存在被中断、尚未补齐的同步轨（需绕过节流立即续拉）。
  Future<bool> hasIncompleteSync() async {
    try {
      final url = await resolveServerUrl();
      if (await _sync.hasIncompleteSync(serverUrl: url)) return true;
      for (final c in await loadSubscribedCategories()) {
        if (await _sync.hasIncompleteSync(serverUrl: url, category: c)) {
          return true;
        }
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  Future<void> saveSubscribedCategories(List<String> categories) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized =
        categories
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
    void Function(QuizCloudSyncProgress progress)? onPageProgress,
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
    AppLogger.instance.logTo(
      LogChannel.quiz,
      'pull 开始 reset=$resetCursor server=$url',
    );
    final catalogs = await _sync.fetchCatalogs(serverUrl: url);

    var targets =
        categories?.map((e) => e.trim()).where((e) => e.isNotEmpty).toList() ??
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
        expectedTotal: catalogs.fold<int>(0, (a, c) => a + c.count),
        onProgress: onProgress,
        onPageProgress: onPageProgress,
      );
      final localCount = await _reloadAndCount(fallback: single.inserted);
      final coverage = QuizBankCoverage.evaluate(
        localCount: localCount,
        catalogs: catalogs,
      );
      _logCoverage(coverage);
      final result = QuizCloudPullResult(
        serverUrl: url,
        categories: const [''],
        inserted: single.inserted,
        cloudDeletes: single.cloudDeletes,
        imagesCached: single.imagesCached,
        imageFailures: single.imageFailures,
        pages: single.pages,
        reachedPageLimit: single.reachedPageLimit,
        catalogCount: catalogs.length,
        localCount: localCount,
        resetCursor: resetCursor,
        coverage: coverage,
      );
      await _persistResult(result);
      return result;
    }

    var inserted = 0;
    var cloudDeletes = 0;
    var imagesCached = 0;
    var imageFailures = 0;
    var pages = 0;
    var reachedPageLimit = false;
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
        expectedTotal: _catalogCount(catalogs, category),
        onProgress: (msg) => onProgress?.call(
          '${i + 1}/${targets.length}：$msg',
        ),
        onPageProgress: onPageProgress,
      );
      inserted += part.inserted;
      cloudDeletes += part.cloudDeletes;
      imagesCached += part.imagesCached;
      imageFailures += part.imageFailures;
      pages += part.pages;
      reachedPageLimit = reachedPageLimit || part.reachedPageLimit;
      AppLogger.instance.logTo(
        LogChannel.quiz,
        'pull 分类完成 ${i + 1}/${targets.length} category=$category'
        ' 入库=${part.inserted} 页=${part.pages}'
        ' 达上限=${part.reachedPageLimit}',
      );
    }

    final localCount = await _reloadAndCount(fallback: inserted);
    // 同步中断（切后台/杀进程/断网）会让游标部分推进却只落一部分数据，
    // 用户侧表现为「同步过却搜不到题」。这里对账本地与云端目录，缺口显式上报。
    final coverage = QuizBankCoverage.evaluate(
      localCount: localCount,
      catalogs: catalogs,
    );
    _logCoverage(coverage);
    AppLogger.instance.logTo(
      LogChannel.quiz,
      'pull 完成 本地=$localCount 目录声称=${coverage.expectedCount}'
      ' 入库=$inserted 页=$pages 分类=${targets.length}'
      ' 缺口=${coverage.missingCount} 达上限=$reachedPageLimit',
    );
    final result = QuizCloudPullResult(
      serverUrl: url,
      categories: targets,
      inserted: inserted,
      cloudDeletes: cloudDeletes,
      imagesCached: imagesCached,
      imageFailures: imageFailures,
      pages: pages,
      reachedPageLimit: reachedPageLimit,
      catalogCount: catalogs.length,
      localCount: localCount,
      resetCursor: resetCursor,
      coverage: coverage,
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

  /// 覆盖率诊断：同步中断导致的「部分落库」在真机上只能靠日志分辨，
  /// 否则引擎侧统一报「本地题库未找到」，无法区分库缺 vs 召回空。
  ///
  /// 双写：这条是排查「同步过却搜不到题」的第一证据，必须能被用户在
  /// App 内调试日志页搜到（搜 `coverage` 或 `missing`）。
  static void _logCoverage(QuizBankCoverage coverage) {
    final line = 'coverage: ${coverage.summaryText}'
        ' (local=${coverage.localCount}'
        ' expected=${coverage.expectedCount}'
        ' missing=${coverage.missingCount}'
        ' complete=${coverage.isComplete})';
    AppLogger.instance.logTo(LogChannel.quiz, line);
    debugPrint('[QuizCloudPull] $line');
  }

  /// 取某个分类的云端声明题数；分类用 id 或 name 匹配（见 pullAll 的 targets
  /// 构造），匹配不到返回 0（进度条退化为不确定型，不影响同步本身）。
  static int _catalogCount(List<QuizCloudCatalog> catalogs, String category) {
    final key = category.trim();
    if (key.isEmpty) return 0;
    for (final c in catalogs) {
      if (c.id == key || c.name == key) return c.count;
    }
    return 0;
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

/// 本地题库 vs 云端目录的覆盖率判定。
///
/// 背景：增量同步若中途被中断（切后台/杀进程/断网），游标会部分推进，
/// 导致「看起来同步过了、实际只落了一部分」——用户表现为「明明同步过，
/// 却一道题都搜不到」，而引擎侧只报「本地题库未找到」，无法区分
/// 「库不完整」与「召回为空」。
///
/// 该纯函数只做数字比对，不触网、不碰存储，便于单测覆盖。
class QuizBankCoverage {
  const QuizBankCoverage._({
    required this.localCount,
    required this.expectedCount,
    required this.missingCount,
    required this.isComplete,
  });

  /// 云端目录声明的总题数（多目录求和）；目录为空时视为 0。
  final int expectedCount;

  /// 本地已有题数。
  final int localCount;

  /// 缺口题数（本地多于云端时为 0，因为本地可能含自建题）。
  final int missingCount;

  /// 是否已达覆盖。目录为空（未登录/离线）时不判缺失，避免误报。
  final bool isComplete;

  static QuizBankCoverage evaluate({
    required int localCount,
    required List<QuizCloudCatalog> catalogs,
  }) {
    final expected = catalogs.fold<int>(0, (sum, c) => sum + c.count);
    if (expected <= 0) {
      return QuizBankCoverage._(
        localCount: localCount,
        expectedCount: 0,
        missingCount: 0,
        isComplete: true,
      );
    }
    final missing = expected > localCount ? expected - localCount : 0;
    return QuizBankCoverage._(
      localCount: localCount,
      expectedCount: expected,
      missingCount: missing,
      isComplete: missing == 0,
    );
  }

  String get summaryText {
    if (expectedCount <= 0) return '本地 $localCount 题';
    if (isComplete) return '本地 $localCount 题 · 已齐全（云端 $expectedCount）';
    return '本地 $localCount / 云端 $expectedCount 题 · 缺 $missingCount 题，'
        '请点「更新」补齐';
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
    this.reachedPageLimit = false,
    this.coverage,
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
  final bool reachedPageLimit;

  /// 同步后本地 vs 云端目录的覆盖率；目录不可得时为 null。
  final QuizBankCoverage? coverage;

  /// 本次同步是否「没拉完」——达页数安全上限，或覆盖率对账后仍有缺口。
  /// UI 据此在题库页常驻提示「题库不完整」，而不是只弹一次 SnackBar。
  bool get isPartial =>
      reachedPageLimit || (coverage != null && !coverage!.isComplete);

  String get summaryText {
    final cat = categories.where((e) => e.isNotEmpty).join('、');
    final scope = cat.isEmpty ? '全库' : cat;
    final mode = resetCursor ? '全量' : '增量';
    final gap = (coverage != null && !coverage!.isComplete)
        ? ' · 缺 ${coverage!.missingCount} 题'
        : '';
    // 达上限时说明「本次没拉完、还需再拉」，不能写得像同步成功。
    final limit = reachedPageLimit
        ? ' · 本次未拉完（已达 $_pagesLimitLabel 页上限），请再点一次「更新」'
        : '';
    return '$mode · 新增 $inserted · 补图 $imagesCached'
        '${imageFailures > 0 ? " · 图失败 $imageFailures" : ""}'
        '$limit'
        '$gap'
        ' · 本地 $localCount · $scope';
  }

  /// 页数上限的用户可读描述（与 QuizCloudSyncService._maxSyncPages 对齐）。
  static String get _pagesLimitLabel => '10,000 条';
}
