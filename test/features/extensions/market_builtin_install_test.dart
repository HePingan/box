import 'dart:convert';

import 'package:box/features/extensions/market/data/plugin_market_api.dart';
import 'package:box/features/extensions/market/data/plugin_market_local_sync.dart';
import 'package:box/features/extensions/market/domain/plugin_market_manifest.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 复现用例：点击安装「GitHub 加速下载」提示「插件不可安装（未发布或已下架）」。
///
/// 真实成因（已用 curl 对 background.hpa888.top 核实）：
/// 内置模板（market_* 前缀）从来没有投稿到服务端，服务端
/// `POST /api/plugin-market/<id>/install` 一律回 404 + plugin_not_installable。
/// 而 installFromTemplate 里 `on PluginMarketApiException { rethrow; }`
/// 把这个 404 直接抛给 UI，于是内置插件全都装不上。
///
/// 注意这不是新插件独有的问题 —— market_image_generator、market_quick_note
/// 等既有条目同样 404，属于既存缺陷。
void main() {
  // HomePluginHost.bootstrap 会碰 MethodChannel（答题插件自动搜题），
  // 没有 binding 会断言失败。
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const notInstallable =
      '{"error":{"message":"插件不可安装（未发布或已下架）",'
      '"code":"plugin_not_installable"}}';

  MarketPluginTemplate tpl(String id) => MarketPluginTemplate(
        id: id,
        title: 'GitHub 加速下载',
        subtitle: '链接自动转镜像加速',
        areaCode: 'recommend',
        actionCode: 'openGithubAccel',
        payload: '',
        icon: Icons.rocket_launch_outlined,
        color: const Color(0xFF24292F),
      );

  /// 只回 install 404 的假服务端，模拟真实线上行为。
  PluginMarketApi api404({List<String>? hits}) {
    return PluginMarketApi(
      httpClient: MockClient((req) async {
        hits?.add('${req.method} ${req.url.path}');
        if (req.url.path.contains('/install')) {
          return http.Response(
            notInstallable,
            404,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{}', 200);
      }),
      loadSession: () async => null,
    );
  }

  group('内置模板安装（离线可用）', () {
    test('服务端回 404 plugin_not_installable 时仍安装成功', () async {
      final sync = PluginMarketLocalSync(api: api404());

      // 修复前这里会抛 PluginMarketApiException，UI 显示「插件不可安装」
      final config = await sync.installFromTemplate(tpl('market_github_accel'));

      expect(config.enabled, isTrue);
      expect(
        config.actionCode,
        'openGithubAccel',
        reason: '内置模板不依赖服务端，安装后 action 必须可用',
      );
    });

    test('内置模板不请求服务端 install 接口', () async {
      final hits = <String>[];
      final sync = PluginMarketLocalSync(api: api404(hits: hits));

      await sync.installFromTemplate(tpl('market_github_accel'));

      expect(
        hits.where((h) => h.contains('/install')),
        isEmpty,
        reason: 'market_* 是本地内置模板，服务端没有对应发布记录，不该白跑一次 404',
      );
    });

    test('标记为本地内置来源，而不是伪装成已发布', () async {
      final sync = PluginMarketLocalSync(api: api404());
      final config = await sync.installFromTemplate(tpl('market_github_accel'));

      expect(
        config.marketStatus,
        'builtin',
        reason: '不能标成 published —— 状态同步会拿它去查服务端，查不到又被禁用',
      );
    });

    test('既有内置条目同样能装（回归：这是全体缺陷不是新插件特例）', () async {
      final sync = PluginMarketLocalSync(api: api404());

      for (final id in const [
        'market_image_generator',
        'market_quick_note',
        'market_daily_news',
      ]) {
        final config = await sync.installFromTemplate(tpl(id));
        expect(config.enabled, isTrue, reason: '$id 也该能装上');
      }
    });

    test('builtin_ 前缀同样按内置处理', () async {
      final sync = PluginMarketLocalSync(api: api404());
      final config = await sync.installFromTemplate(tpl('builtin_something'));
      expect(config.enabled, isTrue);
      expect(config.marketStatus, 'builtin');
    });
  });

  group('状态同步不该反手禁用内置插件', () {
    test('装好后跑一次状态同步，内置插件仍然启用', () async {
      // 内置模板的 origin 是 'market'（无 author、无「用户投稿」标签），
      // 会被 syncInstalledStatuses 纳入；服务端查不到就回 unknown，
      // 老逻辑会把它标风险并禁用 —— 等于装上了又被自动关掉。
      final queried = <String>[];
      final api = PluginMarketApi(
        httpClient: MockClient((req) async {
          if (req.url.path.contains('/status')) {
            final ids =
                (jsonDecode(req.body) as Map)['ids'] as List<dynamic>;
            queried.addAll(ids.map((e) => e.toString()));
            return http.Response(
              jsonEncode({
                'items': [
                  for (final id in ids) {'id': id, 'status': 'unknown'},
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response(notInstallable, 404);
        }),
        loadSession: () async => null,
      );

      final sync = PluginMarketLocalSync(api: api);
      final installed =
          await sync.installFromTemplate(tpl('market_github_accel'));
      expect(installed.enabled, isTrue);

      await sync.syncInstalledStatuses(force: true);

      expect(
        queried,
        isNot(contains('market_github_accel')),
        reason: '内置插件不该拿去问服务端 —— 问了必然 unknown，然后被误禁用',
      );
    });
  });

  group('真实投稿插件的行为不受影响', () {
    test('非内置 ID 仍会上报安装并采用服务端返回', () async {
      final hits = <String>[];
      final sync = PluginMarketLocalSync(
        api: PluginMarketApi(
          httpClient: MockClient((req) async {
            hits.add(req.url.path);
            return http.Response(
              jsonEncode({
                'id': 'user_abc',
                'version': 3,
                'packageSha256': '',
                'packageJson': '',
                'packageFormat': 'json',
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
          loadSession: () async => null,
        ),
      );

      final config = await sync.installFromTemplate(tpl('user_abc'));

      expect(hits.any((h) => h.contains('/install')), isTrue);
      expect(config.marketStatus, 'published');
    });

    test('非内置插件真的下架时，错误照旧抛给用户', () async {
      final sync = PluginMarketLocalSync(api: api404());

      await expectLater(
        sync.installFromTemplate(tpl('user_yanked')),
        throwsA(
          isA<PluginMarketApiException>().having(
            (e) => e.friendlyMessage,
            'friendlyMessage',
            contains('未发布或已下架'),
          ),
        ),
      );
    });
  });
}
