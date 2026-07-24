import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:box/features/extensions/market/data/plugin_market_api.dart';
import 'package:box/features/extensions/market/domain/plugin_market_manifest.dart';

/// 已装市场插件与云端状态联动（下架禁用 / 安装校验）。
class PluginMarketLocalSync {
  PluginMarketLocalSync({
    PluginMarketApi? api,
    HomePluginHost? host,
  })  : _api = api ?? PluginMarketApi(),
        _host = host ?? HomePluginHost.instance;

  final PluginMarketApi _api;
  final HomePluginHost _host;

  static DateTime? _lastSyncAt;
  static const _minInterval = Duration(seconds: 45);

  /// 回前台/扩展页刷新：下架强制禁用。
  Future<PluginMarketSyncResult> syncInstalledStatuses({
    bool force = false,
  }) async {
    final now = DateTime.now();
    if (!force &&
        _lastSyncAt != null &&
        now.difference(_lastSyncAt!) < _minInterval) {
      return const PluginMarketSyncResult(skipped: true);
    }
    _lastSyncAt = now;

    await _host.bootstrap();
    final marketPlugins = _host.allPlugins.where((p) {
      if (p.builtIn) return false;
      final origin = p.customConfig?.origin ?? '';
      return origin == 'user_market' || origin == 'market';
    }).toList(growable: false);

    if (marketPlugins.isEmpty) {
      return const PluginMarketSyncResult();
    }

    List<Map<String, dynamic>> statuses;
    try {
      statuses = await _api.fetchStatus(
        marketPlugins.map((e) => e.id).toList(growable: false),
      );
    } catch (_) {
      return const PluginMarketSyncResult(failed: true);
    }

    var yanked = 0;
    var riskCleared = 0;
    final risks = <PluginRiskEntry>[];
    for (final item in statuses) {
      final id = item['id']?.toString() ?? '';
      final status = item['status']?.toString() ?? '';
      if (id.isEmpty) continue;
      final plugin = marketPlugins.where((p) => p.id == id).firstOrNull;
      if (plugin == null) continue;
      final cfg = plugin.customConfig;
      if (cfg == null) continue;

      if (status == 'yanked') {
        final note = (item['yankNote']?.toString() ?? '').trim();
        final forceUninstall = item['forceUninstall'] == true;
        if (forceUninstall) {
          await _host.unregister(id);
          yanked++;
          continue;
        }
        final riskNote = note.isEmpty ? '管理员已下架' : note;
        final next = cfg.copyWith(
          marketStatus: 'yanked',
          marketRisk: true,
          marketRiskNote: riskNote,
          enabled: false,
        );
        await _host.addCustomPlugin(next);
        if (plugin.enabled) {
          await _host.toggleEnabled(id, false);
        }
        yanked++;
        risks.add(PluginRiskEntry(
          pluginId: id,
          title: plugin.title,
          kind: PluginRiskKind.yanked,
          note: riskNote,
          localVersion: cfg.marketVersion,
        ));
      } else if (status == 'unknown') {
        // 商店已无此插件（下架并移除记录）
        final next = cfg.copyWith(
          marketRisk: true,
          marketRiskNote: '商店已无此插件，建议卸载',
          enabled: false,
        );
        await _host.addCustomPlugin(next);
        if (plugin.enabled) {
          await _host.toggleEnabled(id, false);
        }
        yanked++;
        risks.add(PluginRiskEntry(
          pluginId: id,
          title: plugin.title,
          kind: PluginRiskKind.yanked,
          note: '商店已无此插件，建议卸载',
          localVersion: cfg.marketVersion,
        ));
      } else if (status == 'published') {
        final sha = item['packageSha256']?.toString() ?? '';
        final remoteVersion = (item['version']?.toString() ?? '').trim();
        final wasRisk = cfg.marketRisk || cfg.marketStatus == 'yanked';
        final next = cfg.copyWith(
          marketStatus: 'published',
          marketRisk: false,
          marketRiskNote: '',
          packageSha256: sha.isNotEmpty ? sha : cfg.packageSha256,
        );
        final changed = wasRisk ||
            cfg.marketStatus != 'published' ||
            (sha.isNotEmpty && sha != cfg.packageSha256);
        if (changed) {
          await _host
              .addCustomPlugin(next.copyWith(enabled: cfg.enabled && !wasRisk));
          riskCleared++;
        }

        // 待更新：远端版本与本地已装版本不同
        final localVersion = cfg.marketVersion.trim();
        if (remoteVersion.isNotEmpty &&
            localVersion.isNotEmpty &&
            remoteVersion != localVersion) {
          risks.add(PluginRiskEntry(
            pluginId: id,
            title: plugin.title,
            kind: PluginRiskKind.outdated,
            note: '有新版本可更新',
            localVersion: localVersion,
            latestVersion: remoteVersion,
          ));
        } else if (sha.isNotEmpty &&
            cfg.packageSha256.isNotEmpty &&
            sha != cfg.packageSha256 &&
            (remoteVersion.isEmpty || remoteVersion == localVersion)) {
          // 校验失败：同版本但包指纹不一致
          risks.add(PluginRiskEntry(
            pluginId: id,
            title: plugin.title,
            kind: PluginRiskKind.checksumMismatch,
            note: '本地包校验与商店不一致，建议重装',
            localVersion: localVersion,
            latestVersion: remoteVersion,
          ));
        }
      }
    }

    return PluginMarketSyncResult(
      checked: marketPlugins.length,
      yankedDisabled: yanked,
      riskCleared: riskCleared,
      risks: risks,
    );
  }

  /// 安装/更新：优先下载 zip 校验 sha，再写本地配置。
  /// 支持进度回调与失败重试。
  Future<HomeCustomPluginConfig> installFromTemplate(
    MarketPluginTemplate template, {
    void Function(int receivedBytes, int totalBytes)? onProgress,
    int retries = 1,
  }) async {
    var config = HomeCustomPluginConfig.fromMarketTemplate(template);

    // 1) 若清单声明了 packageUrl/zip，下载并校验
    final hasZipHint = template.packageFormat == 'zip' ||
        template.packageUrl.contains('/package') ||
        template.packageSha256.isNotEmpty;
    if (hasZipHint) {
      try {
        final pkg = await _api.downloadPackage(
          template.id,
          onProgress: onProgress,
          retries: retries,
        );
        final actual = sha256.convert(pkg.bytes).toString();
        final expected = pkg.sha256.isNotEmpty
            ? pkg.sha256
            : template.packageSha256;
        if (expected.isNotEmpty && actual != expected) {
          throw const PluginMarketApiException('插件包校验失败（sha256 不匹配）');
        }
        // 安装上报
        try {
          await _api.reportInstall(template.id);
        } catch (_) {}
        config = config.copyWith(
          packageSha256: actual,
          marketStatus: 'published',
          marketRisk: false,
          marketRiskNote: '',
          enabled: true,
        );
        await _host.addCustomPlugin(config);
        return config;
      } on PluginMarketApiException {
        rethrow;
      } catch (_) {
        // 下载失败则走 JSON 快照路径
      }
    }

    // 2) JSON 快照 / 无包：reportInstall
    try {
      final report = await _api.reportInstall(template.id);
      final packageJson = report['packageJson']?.toString() ?? '';
      final sha = report['packageSha256']?.toString() ?? '';
      if (sha.isNotEmpty && packageJson.isNotEmpty) {
        final actual = sha256.convert(utf8.encode(packageJson)).toString();
        // zip 发布时 packageSha256 是 zip 的 hash，与 packageJson 不同；仅当 format 非 zip 时比对 json
        final format = report['packageFormat']?.toString() ??
            template.packageFormat;
        if (format != 'zip' && actual != sha) {
          throw const PluginMarketApiException('插件包校验失败（sha256 不匹配）');
        }
        config = config.copyWith(
          packageSha256: sha,
          marketStatus: 'published',
          marketRisk: false,
          marketRiskNote: '',
          enabled: true,
        );
      } else if (sha.isNotEmpty) {
        config = config.copyWith(
          packageSha256: sha,
          marketStatus: 'published',
          marketRisk: false,
          enabled: true,
        );
      } else {
        config = config.copyWith(
          marketStatus: 'published',
          marketRisk: false,
          enabled: true,
        );
      }
    } on PluginMarketApiException {
      rethrow;
    } catch (_) {
      config = config.copyWith(marketStatus: 'local_cache');
    }
    await _host.addCustomPlugin(config);
    return config;
  }
}

class PluginMarketSyncResult {
  const PluginMarketSyncResult({
    this.skipped = false,
    this.failed = false,
    this.checked = 0,
    this.yankedDisabled = 0,
    this.riskCleared = 0,
    this.risks = const [],
  });

  final bool skipped;
  final bool failed;
  final int checked;
  final int yankedDisabled;
  final int riskCleared;

  /// 本次同步检测到的风险条目（已下架 / 待更新 / 校验失败）。
  final List<PluginRiskEntry> risks;
}

/// 已装插件风险类型。
enum PluginRiskKind {
  /// 已被管理员下架 / 商店已无
  yanked,

  /// 有新版本可更新
  outdated,

  /// 本地包校验与商店不一致
  checksumMismatch,
}

/// 已装插件风险条目。
class PluginRiskEntry {
  const PluginRiskEntry({
    required this.pluginId,
    required this.title,
    required this.kind,
    required this.note,
    this.localVersion = '',
    this.latestVersion = '',
  });

  final String pluginId;
  final String title;
  final PluginRiskKind kind;
  final String note;
  final String localVersion;
  final String latestVersion;
}
