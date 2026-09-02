import 'package:flutter/foundation.dart';

import '../../data/account_client.dart';
import '../../data/account_store.dart';
import '../../domain/account_models.dart';
import '../../data/personal_center_client.dart';
import '../../domain/personal_center_models.dart';
import '../../../cloud_sync/data/announcement_service.dart';
import '../../../cloud_sync/data/cloud_sync_client.dart';

/// 个人中心状态控制器。
///
/// 错误分两级：
/// - [fatalError] 只在会话缺失/失效时设置，页面整屏提示并允许重试。
/// - [warnings] 记录单个子模块加载失败，其余已加载数据仍然照常渲染。
class PersonalCenterController extends ChangeNotifier {
  PersonalCenterController({
    PersonalCenterClient? client,
    BoxAccountStore? accountStore,
    BoxAccountClient? accountClient,
    AnnouncementService? announcementService,
  }) : _client = client ?? PersonalCenterClient(),
       _accountStore = accountStore ?? BoxAccountStore(),
       _accountClient = accountClient ?? BoxAccountClient(),
       _announcements = announcementService ?? AnnouncementService();

  final PersonalCenterClient _client;
  final BoxAccountStore _accountStore;
  final BoxAccountClient _accountClient;
  final AnnouncementService _announcements;

  BoxAccountSession? session;
  PersonalOverview? overview;
  PersonalQuotaSummary? quotaSummary;
  PersonalQuizPage? quizPage;
  PersonalPluginPage? pluginPage;
  List<PersonalActivityDay> activity = const [];

  /// 站内公告（公开接口，未登录也能看）。
  AnnouncementState announcements = AnnouncementState.empty;
  bool announcementsLoading = false;
  String? announcementsError;

  bool loading = false;
  bool quotaLoading = false;
  bool pluginsLoading = false;
  bool pluginsLoadingMore = false;
  bool quizLoading = false;
  bool quizLoadingMore = false;

  static const int _pageSize = 20;
  String? pluginStatus;
  String? quizStatus;

  /// 阻断性错误（未登录 / 会话失效）。
  String? fatalError;

  /// 子模块降级提示，键为模块名。
  final Map<String, String> warnings = {};

  bool _announcementsLoaded = false;
  bool _quotaTabLoaded = false;
  bool _pluginsLoaded = false;
  bool _quizLoaded = false;

  /// 兼容旧调用点：仍暴露聚合错误文案。
  String? get error => fatalError ?? (warnings.isEmpty ? null : warningMessage);

  String get warningMessage => '${warnings.keys.join('、')}暂不可用，其余数据已加载。';

  bool get hasWarnings => warnings.isNotEmpty;

  void dismissWarnings() {
    if (warnings.isEmpty) return;
    warnings.clear();
    notifyListeners();
  }

  /// 首屏加载：只解析会话 + 拉取额度 Tab 所需数据，其它 Tab 按需加载。
  Future<void> load({bool force = false}) async {
    loading = true;
    fatalError = null;
    notifyListeners();
    try {
      session = await _accountStore.loadSession();
      final current = session;
      if (current == null || current.token.trim().isEmpty) {
        throw const PersonalCenterException('请先登录账号');
      }
      await _loadQuotaTab(current, force: force);
    } catch (e) {
      fatalError = e is PersonalCenterException ? e.message : '加载个人中心失败：$e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// 额度 Tab：总览 + 流水 + 30 天活跃趋势。
  Future<void> loadQuotaTab({bool force = false}) async {
    final current = session;
    if (current == null) return;
    quotaLoading = true;
    notifyListeners();
    try {
      await _loadQuotaTab(current, force: force);
    } finally {
      quotaLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadQuotaTab(
    BoxAccountSession current, {
    bool force = false,
  }) async {
    if (_quotaTabLoaded && !force) return;
    await Future.wait([
      _guard('额度总览', () async {
        overview = await _client.fetchOverview(
          serverUrl: current.serverUrl,
          token: current.token,
        );
      }),
      _guard('额度流水', () async {
        quotaSummary = await _client.fetchQuotaSummary(
          serverUrl: current.serverUrl,
          token: current.token,
        );
      }),
      _guard('活跃趋势', () async {
        activity = await _client.fetchActivity(
          serverUrl: current.serverUrl,
          token: current.token,
        );
      }),
    ]);
    _quotaTabLoaded = true;
  }

  /// 我的插件首页数据。[status] 变化时强制重新拉取第一页。
  Future<void> loadPlugins({String? status, bool force = false}) async {
    final current = session;
    if (current == null) return;
    final statusChanged = status != pluginStatus;
    if (_pluginsLoaded && !force && !statusChanged) return;
    pluginStatus = status;
    pluginsLoading = true;
    notifyListeners();
    await _guard('我的插件', () async {
      pluginPage = await _client.fetchMyPlugins(
        serverUrl: current.serverUrl,
        token: current.token,
        status: status,
        limit: _pageSize,
      );
    });
    _pluginsLoaded = true;
    pluginsLoading = false;
    notifyListeners();
  }

  /// 加载下一页插件，追加到当前列表。
  Future<void> loadMorePlugins() async {
    final current = session;
    final loaded = pluginPage;
    if (current == null || loaded == null) return;
    if (pluginsLoadingMore || !loaded.hasMore) return;
    pluginsLoadingMore = true;
    notifyListeners();
    await _guard('我的插件', () async {
      final next = await _client.fetchMyPlugins(
        serverUrl: current.serverUrl,
        token: current.token,
        status: pluginStatus,
        offset: loaded.items.length,
        limit: _pageSize,
      );
      pluginPage = PersonalPluginPage(
        items: [...loaded.items, ...next.items],
        total: next.total,
        offset: next.offset,
        limit: next.limit,
        hasMore: next.hasMore,
      );
    });
    pluginsLoadingMore = false;
    notifyListeners();
  }

  Future<void> loadQuizzes({String? status, bool force = false}) async {
    final current = session;
    if (current == null) return;
    final statusChanged = status != quizStatus;
    if (_quizLoaded && !force && !statusChanged) return;
    quizStatus = status;
    quizLoading = true;
    notifyListeners();
    await _guard('我的题库', () async {
      quizPage = await _client.fetchMyQuizzes(
        serverUrl: current.serverUrl,
        token: current.token,
        status: status,
        limit: _pageSize,
      );
    });
    _quizLoaded = true;
    quizLoading = false;
    notifyListeners();
  }

  /// 加载下一页题目，追加到当前列表。
  Future<void> loadMoreQuizzes() async {
    final current = session;
    final loaded = quizPage;
    if (current == null || loaded == null) return;
    if (quizLoadingMore || !loaded.hasMore) return;
    quizLoadingMore = true;
    notifyListeners();
    await _guard('我的题库', () async {
      final next = await _client.fetchMyQuizzes(
        serverUrl: current.serverUrl,
        token: current.token,
        status: quizStatus,
        offset: loaded.questions.length,
        limit: _pageSize,
      );
      quizPage = PersonalQuizPage(
        questions: [...loaded.questions, ...next.questions],
        total: next.total,
        offset: next.offset,
        limit: next.limit,
        hasMore: next.hasMore,
      );
    });
    quizLoadingMore = false;
    notifyListeners();
  }

  /// 按成功/失败筛选重新拉取流水，供流水详情页使用。
  Future<PersonalQuotaSummary> fetchTransactions({
    bool? success,
    int limit = 100,
  }) async {
    final current = session;
    if (current == null) {
      throw const PersonalCenterException('请先登录账号');
    }
    return _client.fetchQuotaSummary(
      serverUrl: current.serverUrl,
      token: current.token,
      success: success,
      limit: limit,
    );
  }

  Future<void> updateNickname(String nickname) async {
    final current = session;
    if (current == null) {
      throw const PersonalCenterException('请先登录账号');
    }
    final value = nickname.trim();
    if (value.isEmpty || value.length > 32) {
      throw const PersonalCenterException('昵称不能为空且长度不能超过 32 个字符');
    }
    final user = await _accountClient.updateMyProfile(
      serverUrl: current.serverUrl,
      token: current.token,
      nickname: value,
    );
    final updated = BoxAccountSession(
      serverUrl: current.serverUrl,
      token: current.token,
      user: user,
    );
    await _accountStore.saveSession(updated);
    session = updated;
    final loaded = overview;
    if (loaded != null) {
      // copyWith 保留 createdAt / lastLoginAt，避免 JSON 往返丢字段。
      overview = PersonalOverview(
        user: loaded.user.copyWith(nickname: user.nickname),
        quota: loaded.quota,
        stats: loaded.stats,
      );
    }
    notifyListeners();
  }

  // ── 公告 ──

  /// 加载公告。公告是公开接口，不依赖登录态，因此即使 [session] 为空也能拉。
  Future<void> loadAnnouncements({bool force = false}) async {
    if (_announcementsLoaded && !force) return;
    announcementsLoading = true;
    announcementsError = null;
    notifyListeners();
    try {
      announcements = await _announcements.load(force: force);
      _announcementsLoaded = true;
    } catch (e) {
      announcementsError = e is CloudSyncException ? e.message : '公告加载失败：$e';
    } finally {
      announcementsLoading = false;
      notifyListeners();
    }
  }

  // 原先这里有个 refreshAnnouncementBadge()：只读缓存点亮红点，但从未被任何
  // 地方调用 —— 公告因此既不会在启动时拉，红点也永远不亮。职责已由 app 作用域
  // 的 AnnouncementCenter.bootstrap() 接管，这里不再保留死代码。

  Future<void> markAnnouncementRead(String id) async {
    if (announcements.isRead(id)) return;
    final ids = await _announcements.markRead(id);
    announcements = AnnouncementState(
      items: announcements.items,
      readIds: ids,
      fetchedAt: announcements.fetchedAt,
      fromCache: announcements.fromCache,
    );
    notifyListeners();
  }

  Future<void> markAllAnnouncementsRead() async {
    if (!announcements.hasUnread) return;
    final ids = await _announcements.markAllRead(
      announcements.items.map((e) => e.id),
    );
    announcements = AnnouncementState(
      items: announcements.items,
      readIds: ids,
      fetchedAt: announcements.fetchedAt,
      fromCache: announcements.fromCache,
    );
    notifyListeners();
  }

  /// 执行一个子模块加载，失败只登记降级提示，不抛出。
  Future<void> _guard(String label, Future<void> Function() task) async {
    try {
      await task();
      warnings.remove(label);
    } catch (_) {
      warnings[label] = label;
    }
  }
}
