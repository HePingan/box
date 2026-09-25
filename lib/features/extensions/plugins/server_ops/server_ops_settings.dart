// 服务器运维插件：运维通道（WebDAV + 终端）的连接参数（B1 多服务器模型）。
//
// 设计口径：
//   * **一台机器一条连接**：地址 / 用户名 / 终端地址 / 快照 id 都在 [ServerOpsServer] 里，
//     文件页 / 终端页 / 诊断都按**当前选中的那台**工作；
//   * **口令不进模型**：既不在 [ServerOpsServer] 里、也不写进 SharedPreferences。
//     它按服务器分键存本机加密存储（`serverOps.dav.password.<id>`，见 OpsSecretStore），
//     只有当前会话内的一份内存缓存 [passwords] 供界面同步显示"这台配了口令没有"；
//   * 构建注入只是**默认值**，用户在设置里填过就以用户的为准（两台机器各有各的默认值）；
//   * 这些参数全部可以经构造参数注入，单测不碰真网络、也不依赖构建参数。
//
// 键一律带 `serverOps.dav.` 前缀：与「远端存储」插件的账户键分开，
// 免得两个插件的地址/口令互相覆盖。

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:box/features/extensions/plugins/server_ops/server_ops_secret_store.dart';

/// 一台运维目标机（不可变）。**口令不在模型里** —— 它只存本机加密存储。
class ServerOpsServer {
  const ServerOpsServer({
    required this.id,
    required this.label,
    this.baseUrl = '',
    this.user = '',
    this.terminalUrl = '',
    this.apiUrl = '',
    this.snapshotId = '',
  });

  /// 稳定标识（也是口令键的后缀：`serverOps.dav.password.<id>`）。
  final String id;

  /// 界面上显示的名字（如「阿里云 · 主服务端」）。
  final String label;

  /// 这台机器的 WebDAV 根地址；空 = 用构建注入的默认值。
  final String baseUrl;

  /// 这台机器的用户名；空 = 用构建注入的默认值。
  final String user;

  /// 这台机器的终端（ttyd）地址；空 = 用构建注入的默认值。
  final String terminalUrl;

  /// 这台机器的**只读运维 API** 地址（C2）；空 = 按 id 取内置默认，用户自己加的机器没有默认。
  final String apiUrl;

  /// 对应服务器页快照 hosts.json 里那台机器的 id（用来标「当前」）；空 = 就用 [id]。
  final String snapshotId;

  /// 与快照对齐用的机器 id。
  String get effectiveSnapshotId => _nonEmpty(snapshotId) ?? id;

  String get effectiveBaseUrl =>
      _nonEmpty(baseUrl) ?? ServerOpsSettings.defaultBaseUrl;

  String get effectiveUser => _nonEmpty(user) ?? ServerOpsSettings.defaultUser;

  String get effectiveTerminalUrl =>
      _nonEmpty(terminalUrl) ?? ServerOpsSettings.defaultTerminalUrl;

  /// 生效的只读 API 地址；用户自己加的机器没填就是空串（界面据此提示"这台的系统页还没接"）。
  String get effectiveApiUrl =>
      _nonEmpty(apiUrl) ?? ServerOpsSettings.defaultApiUrlFor(id);

  /// 地址或用户名还是构建默认值（没被用户覆盖过）。
  bool get usedBuildDefaults =>
      _nonEmpty(baseUrl) == null || _nonEmpty(user) == null;

  ServerOpsServer copyWith({
    String? id,
    String? label,
    String? baseUrl,
    String? user,
    String? terminalUrl,
    String? apiUrl,
    String? snapshotId,
  }) =>
      ServerOpsServer(
        id: id ?? this.id,
        label: label ?? this.label,
        baseUrl: baseUrl ?? this.baseUrl,
        user: user ?? this.user,
        terminalUrl: terminalUrl ?? this.terminalUrl,
        apiUrl: apiUrl ?? this.apiUrl,
        snapshotId: snapshotId ?? this.snapshotId,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
        'baseUrl': baseUrl,
        'user': user,
        'terminalUrl': terminalUrl,
        'apiUrl': apiUrl,
        'snapshotId': snapshotId,
      };

  /// 解析一条持久化记录；没有可用 id 的条目返回 null（宁可丢一条也不要错 id）。
  static ServerOpsServer? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _nonEmpty(raw['id'] as String?);
    if (id == null) return null;
    return ServerOpsServer(
      id: id,
      label: _nonEmpty(raw['label'] as String?) ?? id,
      baseUrl: _nonEmpty(raw['baseUrl'] as String?) ?? '',
      user: _nonEmpty(raw['user'] as String?) ?? '',
      terminalUrl: _nonEmpty(raw['terminalUrl'] as String?) ?? '',
      apiUrl: _nonEmpty(raw['apiUrl'] as String?) ?? '',
      snapshotId: _nonEmpty(raw['snapshotId'] as String?) ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ServerOpsServer &&
      other.id == id &&
      other.label == label &&
      other.baseUrl == baseUrl &&
      other.user == user &&
      other.terminalUrl == terminalUrl &&
      other.apiUrl == apiUrl &&
      other.snapshotId == snapshotId;

  @override
  int get hashCode =>
      Object.hash(id, label, baseUrl, user, terminalUrl, apiUrl, snapshotId);

  @override
  String toString() =>
      'ServerOpsServer($id, $label, $baseUrl, $user, $terminalUrl, $apiUrl, $snapshotId)';
}

/// 整套运维通道配置：服务器列表 + 当前选中的那台（口令按服务器分键存）。
class ServerOpsSettings {
  const ServerOpsSettings({
    this.servers = const <ServerOpsServer>[],
    this.selectedServerId,
    this.passwords = const <String, String>{},
    this.apiTokens = const <String, String>{},
  });

  /// 用户保存过的服务器列表；空 = 用户从没保存过 → 用 [builtInServers]（开箱即用两台）。
  final List<ServerOpsServer> servers;

  /// 当前选中的服务器 id；null / 空 / 找不到 = 列表第一台。
  final String? selectedServerId;

  /// 本次会话内从加密存储读出的口令，键是服务器 id。
  ///
  /// **绝不落盘、绝不进 JSON**：落盘一律走 [OpsSecretStore] 的分服务器键。
  /// 留这一份只是为了界面能同步回答"这台配了口令没有"（每块 UI 都异步读一次
  /// 加密存储既慢又难测）。
  final Map<String, String> passwords;

  /// 本次会话内从加密存储读出的**只读 API 设备令牌**，键是服务器 id。
  /// 与 [passwords] 同样的规矩：绝不落盘、绝不进 JSON、绝不进日志（面板会被截屏）。
  final Map<String, String> apiTokens;

  /// 内置两台的只读 API 地址。地址不是秘密，随包内置；**令牌**要用户填一次。
  static const String defaultApiUrl = 'https://box.hpa888.top/opsapi';
  static const String defaultApiUrl175 = 'https://box.hpa888.top/opsapi175';

  /// 按机器 id 给只读 API 的默认地址；用户自己加的机器没有默认（返回空串）。
  static String defaultApiUrlFor(String id) {
    if (id == builtInHpa888Id) return defaultApiUrl;
    if (id == builtInTencent175Id) return defaultApiUrl175;
    return '';
  }

  // ── 构建注入的默认值（两台机器各一套；名字与
  //    tool/build_release_with_update_sign.sh 里注入的 --dart-define 对得上） ──

  static const String defaultBaseUrl = String.fromEnvironment(
    'OPS_DAV_BASE',
    defaultValue: 'https://box.hpa888.top/dav',
  );

  static const String defaultUser = String.fromEnvironment(
    'OPS_DAV_USER',
    defaultValue: 'boxops',
  );

  static const String defaultTerminalUrl = String.fromEnvironment(
    'OPS_TERM_URL',
    defaultValue: 'https://box.hpa888.top/term/',
  );

  static const String defaultBaseUrl175 = String.fromEnvironment(
    'OPS_DAV175_BASE',
    defaultValue: 'https://box.hpa888.top/dav175',
  );

  static const String defaultUser175 = String.fromEnvironment(
    'OPS_DAV175_USER',
    defaultValue: 'boxops',
  );

  static const String defaultTerminalUrl175 = String.fromEnvironment(
    'OPS_TERM175_URL',
    defaultValue: 'https://box.hpa888.top/term175/',
  );

  // ── 开箱即用的两台（都不是秘密：地址与用户名本来就在包里） ─────────

  /// 主服务端（阿里云）。
  static const String builtInHpa888Id = 'hpa888';

  /// 构建 / 监控机（腾讯云 175，经 hpa888 的 nginx location 暴露）。
  static const String builtInTencent175Id = 'tencent175';

  /// 内置的主服务端。
  static const ServerOpsServer builtInHpa888 = ServerOpsServer(
    id: builtInHpa888Id,
    label: '阿里云 · 主服务端',
    baseUrl: defaultBaseUrl,
    user: defaultUser,
    terminalUrl: defaultTerminalUrl,
    apiUrl: defaultApiUrl,
    snapshotId: builtInHpa888Id,
  );

  /// 内置的构建 / 监控机。
  static const ServerOpsServer builtInTencent175 = ServerOpsServer(
    id: builtInTencent175Id,
    label: '腾讯云 · 构建/监控机',
    baseUrl: defaultBaseUrl175,
    user: defaultUser175,
    terminalUrl: defaultTerminalUrl175,
    apiUrl: defaultApiUrl175,
    snapshotId: builtInTencent175Id,
  );

  static const List<ServerOpsServer> builtInServers = <ServerOpsServer>[
    builtInHpa888,
    builtInTencent175,
  ];

  // ── SharedPreferences 键（前缀 serverOps.dav.） ──────────────────

  /// 服务器列表（JSON 数组）——290 起的新键。
  static const String serversKey = 'serverOps.dav.servers';

  /// 当前选中的服务器 id。
  static const String selectedKey = 'serverOps.dav.selected';

  // 下面四个是**老键**（289/290 的单服务器时代）：只在迁移时读，迁完删掉。
  static const String baseUrlKey = 'serverOps.dav.baseUrl';
  static const String userKey = 'serverOps.dav.user';
  static const String terminalUrlKey = 'serverOps.dav.terminalUrl';

  /// 老键里那份**明文**口令（289 及以前）；290 起已改成加密存储，这个键只出现在
  /// 迁移路径里。
  static const String passwordKey = KeystoreOpsSecretStore.legacyKey;

  // ── 生效值（一律按当前选中的服务器算） ───────────────────────────

  /// 实际生效的服务器列表（没保存过就是开箱即用的两台）。
  List<ServerOpsServer> get effectiveServers =>
      servers.isEmpty ? builtInServers : servers;

  /// 当前选中的服务器（选中的 id 找不到时退回第一台 —— 总得有一台能用）。
  ServerOpsServer get currentServer {
    final id = _nonEmpty(selectedServerId);
    final list = effectiveServers;
    if (id != null) {
      for (final server in list) {
        if (server.id == id) return server;
      }
    }
    return list.first;
  }

  /// 生效的选中 id（把"没选 / 选了个不存在的"归一成实际那台）。
  String get effectiveSelectedServerId => currentServer.id;

  /// 某台服务器保存的口令（原样返回，不 trim：尾随空格可能是口令的一部分）。
  String passwordFor(String serverId) => passwords[serverId] ?? '';

  /// 某台服务器配过口令没有。
  bool hasPasswordFor(String serverId) => _nonEmpty(passwordFor(serverId)) != null;

  String get effectiveBaseUrl => currentServer.effectiveBaseUrl;

  String get effectiveUser => currentServer.effectiveUser;

  /// 生效口令。没有就是空串（文件页/终端页据此给"先去设置里填"的引导）。
  String get effectivePassword => _nonEmpty(passwordFor(currentServer.id)) ?? '';

  /// 生效终端地址。
  String get effectiveTerminalUrl => currentServer.effectiveTerminalUrl;

  /// 生效的只读 API 地址（空 = 这台没接系统页）。
  String get effectiveApiUrl => currentServer.effectiveApiUrl;

  String apiTokenFor(String serverId) => apiTokens[serverId] ?? '';

  bool hasApiTokenFor(String serverId) => _nonEmpty(apiTokenFor(serverId)) != null;

  /// 生效的设备令牌；空 = 没配（系统页要给"先去设置里填"的引导）。
  String get effectiveApiToken => _nonEmpty(apiTokenFor(currentServer.id)) ?? '';

  bool get hasApiToken => effectiveApiToken.isNotEmpty;

  /// 有没有可用口令；没有时文件页/终端页要给"先去设置里填"的引导。
  bool get hasPassword => effectivePassword.isNotEmpty;

  bool get usedBuildDefaults => currentServer.usedBuildDefaults;

  /// 新增服务器时用的 id（`srv1` / `srv2` …）：确定性、不撞已有 id、能单测。
  ///
  /// 机器 id 要与 hosts.json 对齐是**内置两台**的事；用户自己加的服务器没有快照行，
  /// 生成一个不会撞的 id 就够（它的 snapshotId 默认等于自己，不会误标「当前」）。
  static String nextServerId(Iterable<String> existing) {
    final taken = existing.toSet();
    for (var i = 1;; i++) {
      final candidate = 'srv$i';
      if (!taken.contains(candidate)) return candidate;
    }
  }

  // ── 读写本地 ────────────────────────────────────────────────────

  /// 从本地读。三种情况按顺序：
  ///   1. 有新键（保存过的列表）→ 直接用；
  ///   2. 有老键（单服务器时代的 baseUrl/user/terminalUrl/口令）→ 一次性迁移；
  ///   3. 都没有 → 开箱即用的两台（口令缓存按两台各读一次）。
  ///
  /// 读不出来一律给"什么都没配"（地址/用户名的构建默认值照旧生效）。
  static Future<ServerOpsSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final persisted = _decodeServers(prefs.getString(serversKey));
      if (persisted != null && persisted.isNotEmpty) {
        return ServerOpsSettings(
          servers: persisted,
          selectedServerId: _nonEmpty(prefs.getString(selectedKey)),
          passwords: await _readPasswords(persisted.map((s) => s.id)),
          apiTokens: await _readApiTokens(persisted.map((s) => s.id)),
        );
      }
      final migrated = await _migrateLegacy(prefs);
      if (migrated != null) return migrated;
      return ServerOpsSettings(
        passwords: await _readPasswords(builtInServers.map((s) => s.id)),
        apiTokens: await _readApiTokens(builtInServers.map((s) => s.id)),
      );
    } catch (_) {
      return const ServerOpsSettings();
    }
  }

  /// 老数据迁移（必须有，否则老用户升级后要重新输一遍口令）。
  ///
  /// 老状态是**一套连接**：`serverOps.dav.baseUrl/user/terminalUrl`（SharedPreferences）
  /// 加上一个口令键（290 它在加密存储里、289 及以前是 SharedPreferences 里的明文
  /// `serverOps.dav.password`）。这里把它折成一台 id = hpa888 的服务器：
  ///   * 口令**先搬**到分服务器键 `serverOps.dav.password.hpa888`，再删老键；
  ///   * 四个老键（含明文口令键）全部清掉；
  ///   * 顺手把新键写进去 —— 迁移只做一次，下次 load() 走第 1 条路。
  ///
  /// 没有任何老数据时返回 null（交给"开箱即用的两台"那条路）。
  static Future<ServerOpsSettings?> _migrateLegacy(
    SharedPreferences prefs,
  ) async {
    final baseUrl = _nonEmpty(prefs.getString(baseUrlKey));
    final user = _nonEmpty(prefs.getString(userKey));
    final terminalUrl = _nonEmpty(prefs.getString(terminalUrlKey));
    final plain = prefs.getString(passwordKey);
    final legacySecret = await serverOpsSecretStore.readLegacyPassword();
    final hasAnyLegacy = baseUrl != null ||
        user != null ||
        terminalUrl != null ||
        plain != null ||
        _nonEmpty(legacySecret) != null;
    if (!hasAnyLegacy) return null;

    // 老代码的口径是"加密存储优先，其次 SharedPreferences 里的明文"。
    final password = _nonEmpty(legacySecret) ?? plain;
    const id = builtInHpa888Id;
    final server = ServerOpsServer(
      id: id,
      label: '阿里云 · 主服务端',
      baseUrl: baseUrl ?? '',
      user: user ?? '',
      terminalUrl: terminalUrl ?? '',
      snapshotId: id,
    );

    final passwords = <String, String>{};
    if (password != null && password.isNotEmpty) {
      await serverOpsSecretStore.writePassword(id, password);
      passwords[id] = password;
    }
    // 老键一律清掉：留着任一一个都等于"改了但没改干净"。
    await serverOpsSecretStore.clearLegacyPassword();
    await prefs.remove(passwordKey);
    await prefs.remove(baseUrlKey);
    await prefs.remove(userKey);
    await prefs.remove(terminalUrlKey);
    await prefs.setString(serversKey, jsonEncode([server.toJson()]));
    await prefs.setString(selectedKey, id);

    return ServerOpsSettings(
      servers: [server],
      selectedServerId: id,
      passwords: passwords,
    );
  }

  /// 读某几台服务器的口令（读不出来/没存过就跳过）。
  static Future<Map<String, String>> _readPasswords(
    Iterable<String> ids,
  ) async {
    final out = <String, String>{};
    for (final id in ids) {
      final value = await serverOpsSecretStore.readPassword(id);
      if (_nonEmpty(value) != null) out[id] = value!;
    }
    return out;
  }

  /// 读某几台服务器的设备令牌（读不出来/没存过就跳过）。
  static Future<Map<String, String>> _readApiTokens(Iterable<String> ids) async {
    final out = <String, String>{};
    for (final id in ids) {
      final value = await serverOpsSecretStore.readApiToken(id);
      if (_nonEmpty(value) != null) out[id] = value!;
    }
    return out;
  }

  static List<ServerOpsServer>? _decodeServers(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! List) return null;
    final out = <ServerOpsServer>[];
    for (final item in decoded) {
      final server = ServerOpsServer.fromJson(item);
      if (server != null) out.add(server);
    }
    return out;
  }

  /// 写回配置，返回写回后的设置（调用方直接拿它替换当前状态）。
  ///
  ///   * [servers] 非空（指"传了"）→ 整套列表落盘，并且**从列表里删掉的服务器，
  ///     它的口令键一起清掉**（不然加密存储里会积一堆没人认领的口令）；
  ///   * [selectedServerId] 传了就写；
  ///   * [passwords] 里出现的服务器 id 会按服务器写进加密存储（空串 = 清掉这一台），
  ///     没出现的保持原样；
  ///   * 口令**永远不写 SharedPreferences**。
  Future<ServerOpsSettings> save({
    List<ServerOpsServer>? servers,
    String? selectedServerId,
    Map<String, String>? passwords,
    Map<String, String>? apiTokens,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final nextPasswords = <String, String>{...this.passwords};
    final nextTokens = <String, String>{...this.apiTokens};

    if (apiTokens != null) {
      for (final entry in apiTokens.entries) {
        if (entry.value.isEmpty) {
          await serverOpsSecretStore.clearApiToken(entry.key);
          nextTokens.remove(entry.key);
        } else {
          // 令牌同样不 trim：粘贴时常带首尾空白，但宁可原样存，读的时候再 trim。
          await serverOpsSecretStore.writeApiToken(entry.key, entry.value);
          nextTokens[entry.key] = entry.value;
        }
      }
    }

    if (passwords != null) {
      for (final entry in passwords.entries) {
        if (entry.value.isEmpty) {
          await serverOpsSecretStore.clearPassword(entry.key);
          nextPasswords.remove(entry.key);
        } else {
          // 口令不做 trim：尾随空格可能是口令的一部分（粘贴场景很常见）。
          await serverOpsSecretStore.writePassword(entry.key, entry.value);
          nextPasswords[entry.key] = entry.value;
        }
      }
    }

    if (servers != null) {
      final kept = {for (final server in servers) server.id};
      for (final gone in effectiveServers) {
        if (kept.contains(gone.id)) continue;
        await serverOpsSecretStore.clearPassword(gone.id);
        nextPasswords.remove(gone.id);
        await serverOpsSecretStore.clearApiToken(gone.id);
        nextTokens.remove(gone.id);
      }
      await prefs.setString(
        serversKey,
        jsonEncode([for (final server in servers) server.toJson()]),
      );
    }

    if (selectedServerId != null) {
      await prefs.setString(selectedKey, selectedServerId.trim());
    }

    return ServerOpsSettings(
      servers: servers ?? this.servers,
      selectedServerId: selectedServerId ?? this.selectedServerId,
      passwords: nextPasswords,
      apiTokens: nextTokens,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ServerOpsSettings &&
      other.selectedServerId == selectedServerId &&
      _sameServers(other.servers, servers) &&
      _samePasswords(other.passwords, passwords) &&
      _samePasswords(other.apiTokens, apiTokens);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(servers),
        selectedServerId,
        Object.hashAll(passwords.entries.map((e) => Object.hash(e.key, e.value))),
        Object.hashAll(apiTokens.entries.map((e) => Object.hash(e.key, e.value))),
      );

  static bool _sameServers(
    List<ServerOpsServer> a,
    List<ServerOpsServer> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _samePasswords(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}

String? _nonEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
