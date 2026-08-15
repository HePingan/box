import 'package:flutter/foundation.dart';

import '../../data/account_client.dart';
import '../../data/account_store.dart';
import '../../domain/account_models.dart';
import '../../data/personal_center_client.dart';
import '../../domain/personal_center_models.dart';

class PersonalCenterController extends ChangeNotifier {
  PersonalCenterController({
    PersonalCenterClient? client,
    BoxAccountStore? accountStore,
  }) : _client = client ?? PersonalCenterClient(),
       _accountStore = accountStore ?? BoxAccountStore();

  final PersonalCenterClient _client;
  final BoxAccountStore _accountStore;

  BoxAccountSession? session;
  PersonalOverview? overview;
  PersonalQuotaSummary? quotaSummary;
  PersonalQuizPage? quizPage;
  List<PersonalActivityDay> activity = const [];
  List<Map<String, dynamic>> plugins = const [];
  bool loading = false;
  String? error;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      session = await _accountStore.loadSession();
      final current = session;
      if (current == null || current.token.trim().isEmpty) {
        throw const PersonalCenterException('请先登录账号');
      }

      final failures = <String>[];
      try {
        overview = await _client.fetchOverview(
          serverUrl: current.serverUrl,
          token: current.token,
        );
      } catch (_) {
        failures.add('额度总览');
      }
      try {
        quotaSummary = await _client.fetchQuotaSummary(
          serverUrl: current.serverUrl,
          token: current.token,
        );
      } catch (_) {
        failures.add('额度流水');
      }
      try {
        quizPage = await _client.fetchMyQuizzes(
          serverUrl: current.serverUrl,
          token: current.token,
        );
      } catch (_) {
        failures.add('我的题库');
      }
      try {
        activity = await _client.fetchActivity(
          serverUrl: current.serverUrl,
          token: current.token,
        );
      } catch (_) {
        failures.add('活动记录');
      }
      try {
        plugins = await _client.fetchMyPlugins(
          serverUrl: current.serverUrl,
          token: current.token,
        );
      } catch (_) {
        failures.add('我的插件');
      }
      if (failures.isNotEmpty && failures.length >= 3) {
        error = '个人中心数据暂不可用，请稍后重试。';
      } else if (failures.isNotEmpty) {
        error = '${failures.join('、')}暂不可用，其余数据已加载。';
      }
    } catch (e) {
      error = e is PersonalCenterException ? e.message : '加载个人中心失败：$e';
    } finally {
      loading = false;
      notifyListeners();
    }
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
    final user = await BoxAccountClient().updateMyProfile(
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
    if (overview != null) {
      overview = PersonalOverview(
        user: PersonalUser.fromJson(user.toJson()),
        quota: overview!.quota,
        stats: overview!.stats,
      );
    }
    notifyListeners();
  }

  Future<void> loadQuizzes({String? status}) async {
    final current = session;
    if (current == null) return;
    try {
      quizPage = await _client.fetchMyQuizzes(
        serverUrl: current.serverUrl,
        token: current.token,
        status: status,
      );
      notifyListeners();
    } catch (e) {
      error = e is PersonalCenterException ? e.message : e.toString();
      notifyListeners();
    }
  }
}
