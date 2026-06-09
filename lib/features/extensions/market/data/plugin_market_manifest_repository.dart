import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../../../novel/core/cache_store.dart';
import '../../../../../plugin_market/models/plugin_market_security.dart';
import '../../../../../plugin_market/models/plugin_market_signature_verifier.dart';
import '../domain/plugin_market_manifest.dart';

class PluginMarketManifestRepository {
  PluginMarketManifestRepository({CacheStore? cache})
    : _cache = cache ?? CacheStore(namespace: 'plugin_market');

  static final PluginMarketManifestRepository instance =
      PluginMarketManifestRepository();

  final CacheStore _cache;

  String _cacheManifestKey(PluginMarketChannel channel) {
    return 'remote_manifest_v3_${channel.name}';
  }

  Future<PluginMarketManifest> loadManifest({
    required List<MarketPluginTemplate> fallbackTemplates,
    required PluginMarketChannel channel,
    required PluginMarketSecurityConfig security,
    String? remoteConfigUrl,
    bool forceRefresh = false,
  }) async {
    final builtin = PluginMarketManifest(
      version: 1,
      templates: dedupMarketPluginTemplates(fallbackTemplates),
      source: 'builtin',
      fetchedAt: DateTime.now(),
      channel: channel,
      signatureVerified: security.mode == PluginMarketSignMode.none,
      signatureMode: security.mode,
      signatureMessage: security.mode == PluginMarketSignMode.none
          ? '验签关闭'
          : '内置清单',
      signatureValue: '',
    );

    final cached = await _readCache(channel);
    final url = safeMarketString(remoteConfigUrl);

    // 未配置远程：缓存优先
    if (url.isEmpty) {
      return cached ?? builtin;
    }

    // 配置远程：尝试远程
    final remote = await _fetchRemote(
      url,
      requestedChannel: channel,
      security: security,
    );

    if (remote != null) {
      if (!forceRefresh && cached != null && cached.version > remote.version) {
        return cached.copyWith(source: 'cache');
      }

      await _writeCache(channel, remote);
      return remote;
    }

    // 远程失败，回退
    return cached ?? builtin;
  }

  Future<PluginMarketManifest?> _fetchRemote(
    String url, {
    required PluginMarketChannel requestedChannel,
    required PluginMarketSecurityConfig security,
  }) async {
    try {
      final uri = Uri.parse(url);
      final text = await NetworkAssetBundle(
        uri,
      ).loadString(url).timeout(const Duration(seconds: 10));

      final decoded = jsonDecode(text);

      // 兼容老格式：直接数组
      if (decoded is List) {
        final plugins = decoded;
        final verify = verifyPluginMarketSignatureForPayload(
          security: security,
          channel: requestedChannel,
          version: 1,
          plugins: plugins,
          signature: '',
        );

        if (!verify.passed && !security.allowUnsigned) {
          return null;
        }

        final templates = parseMarketPluginTemplates(plugins);
        return PluginMarketManifest(
          version: 1,
          templates: templates,
          source: 'remote',
          fetchedAt: DateTime.now(),
          channel: requestedChannel,
          signatureVerified: verify.passed,
          signatureMode: security.mode,
          signatureMessage: verify.passed
              ? verify.message
              : '${verify.message}${security.allowUnsigned ? '（已放行）' : ''}',
          signatureValue: '',
        );
      }

      if (decoded is! Map) {
        return null;
      }

      final root = Map<String, dynamic>.from(decoded);
      final resolved = _resolveChannelPayload(
        root,
        requestedChannel: requestedChannel,
      );
      if (resolved == null) return null;

      final actualChannel = resolved.channel;
      final node = resolved.node;

      final version = safeMarketInt(
        node['version'],
        safeMarketInt(root['version'], 1),
      );

      final rawPluginsValue =
          node['plugins'] ??
          node['data'] ??
          node['list'] ??
          root['plugins'] ??
          root['data'] ??
          root['list'] ??
          const [];

      final rawPlugins = rawPluginsValue is List ? rawPluginsValue : const [];

      String signature = safeMarketString(
        node['signature'],
        safeMarketString(node['sign']),
      );

      if (signature.isEmpty) {
        final signs = root['signatures'];
        if (signs is Map) {
          signature = safeMarketString(signs[actualChannel.name]);
        }
      }

      final verify = verifyPluginMarketSignatureForPayload(
        security: security,
        channel: actualChannel,
        version: version,
        plugins: rawPlugins,
        signature: signature,
      );

      if (!verify.passed && !security.allowUnsigned) {
        return null;
      }

      final templates = parseMarketPluginTemplates(rawPlugins);
      final fetchedAt =
          tryParseMarketDate(node['fetchedAt']) ??
          tryParseMarketDate(node['updatedAt']) ??
          tryParseMarketDate(root['fetchedAt']) ??
          tryParseMarketDate(root['updatedAt']) ??
          DateTime.now();

      return PluginMarketManifest(
        version: version <= 0 ? 1 : version,
        templates: templates,
        source: 'remote',
        fetchedAt: fetchedAt,
        channel: actualChannel,
        signatureVerified: verify.passed,
        signatureMode: security.mode,
        signatureMessage: verify.passed
            ? verify.message
            : '${verify.message}${security.allowUnsigned ? '（已放行）' : ''}',
        signatureValue: signature,
      );
    } catch (_) {
      return null;
    }
  }

  _ResolvedRemotePayload? _resolveChannelPayload(
    Map<String, dynamic> root, {
    required PluginMarketChannel requestedChannel,
  }) {
    final channelsRaw = root['channels'];

    // 新格式：{ channels: { stable: {...}, beta: {...} } }
    if (channelsRaw is Map) {
      final channels = Map<String, dynamic>.from(channelsRaw);

      dynamic node = channels[requestedChannel.name];
      PluginMarketChannel actual = requestedChannel;

      if (node is! Map && requestedChannel == PluginMarketChannel.beta) {
        final stable = channels['stable'];
        if (stable is Map) {
          node = stable;
          actual = PluginMarketChannel.stable;
        }
      }

      if (node is! Map) {
        for (final entry in channels.entries) {
          if (entry.value is Map) {
            node = entry.value;
            actual = pluginMarketChannelFromName(entry.key);
            break;
          }
        }
      }

      if (node is Map) {
        return _ResolvedRemotePayload(
          channel: actual,
          node: Map<String, dynamic>.from(node),
        );
      }

      return null;
    }

    // 旧格式：根节点即清单
    return _ResolvedRemotePayload(channel: requestedChannel, node: root);
  }

  Future<PluginMarketManifest?> _readCache(PluginMarketChannel channel) async {
    try {
      final raw = await _cache.read(_cacheManifestKey(channel));

      if (raw is String) {
        if (raw.trim().isEmpty) return null;
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return PluginMarketManifest.fromCacheJson(
            Map<String, dynamic>.from(decoded),
            defaultChannel: channel,
          );
        }
      }

      if (raw is Map) {
        return PluginMarketManifest.fromCacheJson(
          Map<String, dynamic>.from(raw),
          defaultChannel: channel,
        );
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(
    PluginMarketChannel channel,
    PluginMarketManifest manifest,
  ) async {
    final text = jsonEncode(manifest.toJson());
    await _cache.write(_cacheManifestKey(channel), text);
  }
}

class _ResolvedRemotePayload {
  const _ResolvedRemotePayload({required this.channel, required this.node});

  final PluginMarketChannel channel;
  final Map<String, dynamic> node;
}
