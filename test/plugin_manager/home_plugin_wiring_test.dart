import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 接线回归：三个扩展点（事件总线 / 生命周期 / 动作注册表公开 register()）
/// 此前在 `lib/` 里**零生产调用** —— 代码与单测都在，App 从未用过，
/// 而文档把「可扩展 Action 系统」「生命周期 + 事件总线」列为已完成收益。
///
/// 本组用例锁死"接线后真的有人在用"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  HomePluginHost host() => HomePluginHost(
        persistence: HomePluginPersistence(
          cache: CacheStore.inMemory('plugin_wiring'),
        ),
      );

  HomeCustomPluginConfig config(String id, {bool enabled = true}) =>
      HomeCustomPluginConfig.fromJson(<String, dynamic>{
        'id': id,
        'title': '接线用例插件',
        'area': HomePluginArea.center.name,
        'action': HomePluginActionType.toast.name,
        'enabled': enabled,
      });

  test('装/卸/停都会 emit 事件，且落到生命周期轨迹里', () async {
    final h = host();
    final seen = <String>[];
    void onInstalled(dynamic d) => seen.add('installed:${d ?? ''}');
    void onDisabled(dynamic d) => seen.add('disabled:${d ?? ''}');
    PluginEventBus.instance.subscribe(PluginEvents.installed, onInstalled);
    PluginEventBus.instance.subscribe(PluginEvents.disabled, onDisabled);
    addTearDown(() {
      PluginEventBus.instance.unsubscribe(PluginEvents.installed, onInstalled);
      PluginEventBus.instance.unsubscribe(PluginEvents.disabled, onDisabled);
    });

    await h.addCustomPlugin(config('wiring_plugin_a'));
    expect(seen, contains('installed:wiring_plugin_a'));

    await h.toggleEnabled('wiring_plugin_a', false);
    expect(seen, contains('disabled:wiring_plugin_a'));

    await h.unregister('wiring_plugin_a');
    expect(seen.where((e) => e.contains('wiring_plugin_a')).length, 2);

    // 生产默认生命周期（HomePluginLifecycleObserver）也在记轨迹。
    expect(
      HomePluginLifecycleObserver.instance.trail
          .any((e) => e.contains('wiring_plugin_a')),
      isTrue,
      reason: '单例默认生命周期必须是真实实现，不能再是 Noop',
    );
  });

  test('公开的 register() 真的被用上：内置动作由 registerDefaults 注册', () {
    // 此前 _handlers 是静态字面量、公开 register() 零调用。
    expect(
      HomePluginActionRegistry.contains(HomePluginActionType.toast.name),
      isTrue,
    );
    expect(
      HomePluginActionRegistry.contains(HomePluginActionType.openVideoList.name),
      isTrue,
    );

    // 外部仍可注册自己的动作（扩展点可用，不是摆设）。
    var ran = false;
    HomePluginActionRegistry.register('wiring.custom.action', (ctx, actx) async {
      ran = true;
    });
    expect(HomePluginActionRegistry.contains('wiring.custom.action'), isTrue);
    expect(ran, isFalse, reason: '注册本身不应执行');
  });

  test('默认生命周期会拒绝 id/标题为空的插件（真实校验，不是摆设）', () async {
    final h = host();
    await h.register(
      HomePlugin(
        id: '   ',
        title: '标题有',
        subtitle: '',
        icon: Icons.extension_outlined,
        color: const Color(0xFF334155),
        area: HomePluginArea.center,
        onTap: (_) async {},
      ),
    );

    expect(
      h.pluginsOf(HomePluginArea.center, onlyEnabled: false)
          .where((p) => p.id.trim().isEmpty),
      isEmpty,
      reason: '空 id 的行在 UI 上是空白条目，必须在入口被拒',
    );
  });

  test('事件名有单一事实源，且能一次订阅全部', () {
    expect(PluginEvents.all, hasLength(5));
    expect(PluginEvents.all, contains(PluginEvents.riskFlagged));
    expect(PluginEvents.riskFlagged, 'plugin.risk');
  });
}
