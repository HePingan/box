import 'package:flutter/foundation.dart';

import '../../data/account_client.dart';
import '../../data/account_store.dart';
import '../../domain/account_models.dart';
import '../../data/personal_center_client.dart';
import '../../domain/personal_center_models.dart';

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
  }) : _client = client ?? PersonalCenterClient(),
       _accountStore = accountStore ?? BoxAccountStore(),
       _accountClient = accountClient ?? BoxAccountClient();

  final PersonalCenterClient _client;
  final BoxAccountStore _accountStore;
  final BoxAccountClient _accountClient;

  BoxAccountSession? session;
  PersonalOverview? overview;
  PersonalQuotaSummary? quotaSummary;
  PersonalQuizPage? quizPage;
  List<PersonalActivityDay> activity = const [];
  List<Map<String, dynamic>> plugins = const [];

  bool loading = false;
  bool quotaLoading = false;
  bool pluginsLoading = false;
  bool quizLoading = false;

  /// 阻断性错误（未登录 / 会话失效）。
  String? fatalError;

  /// 子模块降级提示，键为模块名。
  final Map<String, String> warnings = {};

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

  Future<void> loadPlugins({bool force = false}) async {
    final current = session;
    if (current == null) return;
    if (_pluginsLoaded && !force) return;
    pluginsLoading = true;
    notifyListeners();
    await _guard('我的插件', () async {
      plugins = await _client.fetchMyPlugins(
        serverUrl: current.serverUrl,
        token: current.token,
      );
    });
    _pluginsLoaded = true;
    pluginsLoading = false;
    notifyListeners();
  }

  Future<void> loadQuizzes({String? status, bool force = false}) async {
    final current = session;
    if (current == null) return;
    if (_quizLoaded && !force && status == null) return;
    quizLoading = true;
    notifyListeners();
    await _guard('我的题库', () async {
      quizPage = await _client.fetchMyQuizzes(
        serverUrl: current.serverUrl,
        token: current.token,
        status: status,
      );
    });
    _quizLoaded = true;
    quizLoading = false;
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
