@Tags(['live'])
library;

import 'dart:io';

import 'package:box/features/account/domain/account_models.dart';
import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:box/features/extensions/market/data/plugin_market_api.dart';
import 'package:box/features/extensions/market/domain/plugin_market_manifest.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真联网端到端：**生产市场**的清单 → 解析 → 下载包 → 哈希校验。
///
/// 为什么要有这条：市场链路的每一段（服务端审核上架 / 清单 JSON 形态 /
/// 客户端解析 / 包下载与 sha256）各自都有单测，但**从来没有一次是拿真服务端
/// 的数据跑真客户端代码**。2026-10-30 首次真上架时，就是靠这条确认
/// 「服务端发出来的字段，App 的解析器确实认得」。
///
/// 默认不随 `flutter test` 跑（带 `live` 标签，CI 用 `--exclude-tags live`）：
///   flutter test --tags live test/plugin_market/plugin_market_live_market_test.dart
///
/// 判定分级（外部故障不该伪装成本仓回归）：
///   - 市场整体不可达（DNS/连接/超时/非 200）→ markTestSkipped 并写明原因；
///   - 可达但清单为空、字段缺失、包哈希对不上 → **失败**，那是真问题。
void main() {
  // PluginMarketApi 的默认实现读 BoxAccountStore（要 binding），起 binding 之后
  // flutter_test 会把 HttpOverrides 换成「一律回 400」的假客户端 —— 真联网测试
  // 必须再把它清掉，否则拿到的是 400 而不是网络错误。
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  const firstPluginId = 'user.u_admin.github-accel';

  // 不读本地会话（flutter_test 里没有 shared_preferences 的平台实现），
  // 直接把服务器地址塞进去：市场清单与包下载都是匿名接口，不需要 token。
  PluginMarketApi api() => PluginMarketApi(
        loadSession: () async => const BoxAccountSession(
          serverUrl: 'https://background.hpa888.top',
          token: '',
          user: BoxAccountUser(
            id: 'test',
            username: 'test',
            role: 'user',
            status: 'normal',
          ),
        ),
      );

  test('生产市场清单可解析，首个插件包下载后 sha256 与清单一致', () async {
    final client = api();

    PluginMarketRemoteManifest remote;
    try {
      remote = await client.fetchMarket();
    } catch (e) {
      markTestSkipped('市场不可达（外部故障，不算本仓回归）：$e');
      return;
    }

    expect(remote.plugins, isNotEmpty, reason: '生产市场应至少有 1 个已上架插件');

    final templates = parseMarketPluginTemplates(remote.plugins);
    expect(templates, isNotEmpty, reason: '服务端清单解析后为空');

    final item = templates.firstWhere(
      (t) => t.id == firstPluginId,
      orElse: () => templates.first,
    );

    // 服务端字段 → 客户端模型的关键映射
    expect(item.id, isNotEmpty);
    expect(item.title, isNotEmpty);
    expect(item.actionCode, isNotEmpty);
    expect(item.packageSha256, isNotEmpty, reason: '清单必须带包哈希，否则安装时无法校验');
    expect(item.packageSize, greaterThan(0));

    // 这个动作必须是 App 真的能执行的那一个（白名单与 enum 对齐的实证）
    expect(
      HomePluginActionType.values.map((a) => a.name),
      contains(item.actionCode),
      reason: '清单里的 actionCode=${item.actionCode} 在 App 端没有对应实现',
    );

    // 真下载 + 真哈希
    final download = await client.downloadPackage(item.id);
    expect(download.bytes, isNotEmpty);
    expect(download.sha256.toLowerCase(), item.packageSha256.toLowerCase(),
        reason: '响应头 x-package-sha256 与清单不一致');
    final digest = sha256.convert(download.bytes).toString();
    expect(digest, item.packageSha256.toLowerCase(),
        reason: '下载字节的 sha256 与清单不一致（包被替换或传输损坏）');
    expect(download.format, 'zip');
  }, timeout: const Timeout(Duration(seconds: 90)));
}
