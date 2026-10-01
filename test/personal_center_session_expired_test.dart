// 会话失效要说「登录已失效」而不是「数据暂不可用」（2026-10-01 真机事故回归）。
//
// 事故：服务端会话 30 天 TTL 到期 → 个人中心四个子模块（额度总览/额度流水/
// 活跃趋势/我的插件）同时 401，界面只说「额度历史、额度概览、活跃趋势、插件
// 暂不可用，其余数据已加载」+「额度数据暂不可用，下拉可重试」—— 用户完全不知道
// 该去重新登录，只能猜。
//
// 修法（三层）：
//   1) 账号层任何 401 → 全局 `globalSessionInvalidNotifier` 记一笔；
//   2) 个人中心把 401 单独归类为 [sessionExpired]，不再摊成逐模块 warning；
//   3) 页面据此显示「登录已失效，请重新登录」+ 一键重新登录（页面渲染见
//      personal_center_page.dart；本文件覆盖前两层的数据契约）。
import 'package:box/features/account/data/account_store.dart';
import 'package:box/features/account/data/personal_center_client.dart';
import 'package:box/features/account/domain/account_models.dart';
import 'package:box/features/account/domain/personal_center_models.dart';
import 'package:box/features/account/presentation/controllers/personal_center_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _server = 'https://background.hpa888.top';

BoxAccountSession _session() => const BoxAccountSession(
  serverUrl: _server,
  token: 'sess-token-expired',
  user: BoxAccountUser(
    id: 'u1',
    username: 'tester',
    role: 'user',
    status: 'active',
  ),
);

class _FakeAccountStore extends BoxAccountStore {
  _FakeAccountStore(this.session);

  final BoxAccountSession? session;

  @override
  Future<BoxAccountSession?> loadSession() async => session;

  @override
  Future<String> loadServerUrl() async => _server;
}

/// 四个子模块全 401（真实 client 的 401 分支另有专门用例）。
class _UnauthorizedClient extends PersonalCenterClient {
  @override
  Future<PersonalOverview> fetchOverview({
    required String serverUrl,
    required String token,
  }) async => throw const PersonalCenterException('请求失败 HTTP 401', statusCode: 401);

  @override
  Future<PersonalQuotaSummary> fetchQuotaSummary({
    required String serverUrl,
    required String token,
    bool? success,
    int limit = 50,
  }) async => throw const PersonalCenterException('请求失败 HTTP 401', statusCode: 401);

  @override
  Future<List<PersonalActivityDay>> fetchActivity({
    required String serverUrl,
    required String token,
  }) async => throw const PersonalCenterException('请求失败 HTTP 401', statusCode: 401);
}

/// 四个子模块全成功（用于验证"会话恢复后提示会消失"）。
class _OkClient extends PersonalCenterClient {
  @override
  Future<PersonalOverview> fetchOverview({
    required String serverUrl,
    required String token,
  }) async => PersonalOverview.fromJson(<String, dynamic>{
    'user': <String, dynamic>{'nickname': 'tester'},
    'quota': <String, dynamic>{
      'remaining': 10,
      'dailyLimit': 20,
      'usedToday': 5,
    },
    'stats': <String, dynamic>{},
  });

  @override
  Future<PersonalQuotaSummary> fetchQuotaSummary({
    required String serverUrl,
    required String token,
    bool? success,
    int limit = 50,
  }) async => PersonalQuotaSummary.fromJson(<String, dynamic>{'items': []});

  @override
  Future<List<PersonalActivityDay>> fetchActivity({
    required String serverUrl,
    required String token,
  }) async => const [];
}

PersonalCenterController _controller(PersonalCenterClient client) =>
    PersonalCenterController(
      client: client,
      accountStore: _FakeAccountStore(_session()),
    );

void main() {
  setUp(() => clearGlobalSessionInvalid());
  tearDown(() => clearGlobalSessionInvalid());

  group('账号层的 401 → 全局标记', () {
    test('真实 PersonalCenterClient 收到 401：抛异常 + 置全局「登录已失效」', () async {
      final client = PersonalCenterClient(
        httpClient: MockClient((_) async => http.Response('', 401)),
      );

      await expectLater(
        client.fetchOverview(serverUrl: _server, token: 'dead-token'),
        throwsA(
          isA<PersonalCenterException>().having(
            (e) => e.statusCode,
            'statusCode',
            401,
          ),
        ),
      );
      expect(
        globalSessionInvalidNotifier.value,
        isTrue,
        reason: '401 必须被账号层识别为「登录已失效」，供界面提示重登',
      );
    });

    test('重新登录成功（saveSession）→ 标记清掉', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      markGlobalSessionInvalid();
      expect(globalSessionInvalidNotifier.value, isTrue);

      await BoxAccountStore().saveSession(_session());
      expect(
        globalSessionInvalidNotifier.value,
        isFalse,
        reason: '登录成功 = 会话恢复，重登提示必须消失',
      );
    });

    test('主动退出（clearSession）→ 标记清掉（退出不等于失效）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      markGlobalSessionInvalid();

      await BoxAccountStore().clearSession();
      expect(globalSessionInvalidNotifier.value, isFalse);
    });
  });

  group('个人中心：401 归类为「会话失效」', () {
    test('四个子模块全 401 → sessionExpired=true 且不产生逐模块 warning', () async {
      final controller = _controller(_UnauthorizedClient());

      await controller.load();

      expect(controller.sessionExpired, isTrue);
      expect(
        controller.warnings,
        isEmpty,
        reason: '会话失效不该说成「某几个模块暂不可用，其余数据已加载」',
      );
      expect(controller.fatalError, isNull, reason: '有会话（只是失效），不是未登录');
      expect(controller.hasWarnings, isFalse);
    });

    test('会话恢复（全部 200）→ sessionExpired 自动回落 false', () async {
      final controller = _controller(_OkClient());

      await controller.load();

      expect(controller.sessionExpired, isFalse);
      expect(controller.warnings, isEmpty);
      expect(controller.overview, isNotNull);
    });
  });
}
