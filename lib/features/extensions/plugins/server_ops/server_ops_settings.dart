// 服务器运维插件：运维通道（WebDAV + 终端）的连接参数。
//
// 设计口径（与仓库里 MONITOR_SNAPSHOT_TOKEN 同一套路）：
//   * **运行期秘密一律走构建注入**，不让用户先手输一遍才能用；
//   * 构建注入只是**默认值**，用户在设置里填过就以用户的为准；
//   * 用户名 / 地址 / 终端地址同样有 dart-define 默认值；
//   * 这些参数全部可以经构造参数注入，单测不碰真网络、也不依赖构建参数。
//
// 键一律带 `serverOps.dav.` 前缀：与「远端存储」插件的账户键分开，
// 免得两个插件的地址/口令互相覆盖。

import 'package:shared_preferences/shared_preferences.dart';

import 'package:box/features/extensions/plugins/server_ops/server_ops_secret_store.dart';

class ServerOpsSettings {
  const ServerOpsSettings({
    this.baseUrl,
    this.user,
    this.password,
    this.terminalUrl,
  });

  /// 用户在设置里填的地址；null / 空 = 没填，用构建注入的默认值。
  final String? baseUrl;

  /// 用户在设置里填的用户名；null / 空 = 没填。
  final String? user;

  /// 本机保存的口令；null / 空 = 没配。
  ///
  /// **口令既不进仓库也不进安装包**（C1 中期档）：只由用户首次输入、只存本机
  /// 加密存储（见 [OpsSecretStore]）。这里只有值本身，来源由 [hasPassword] 表达。
  final String? password;

  /// 用户在设置里填的终端地址；null / 空 = 没填。
  final String? terminalUrl;

  // ── 构建注入的默认值 ────────────────────────────────────────────

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

  // ── SharedPreferences 键（前缀 serverOps.dav.） ──────────────────

  static const String baseUrlKey = 'serverOps.dav.baseUrl';
  static const String userKey = 'serverOps.dav.user';
  static const String passwordKey = 'serverOps.dav.password';
  static const String terminalUrlKey = 'serverOps.dav.terminalUrl';

  // ── 生效值 ──────────────────────────────────────────────────────

  String get effectiveBaseUrl => _nonEmpty(baseUrl) ?? defaultBaseUrl;

  String get effectiveUser => _nonEmpty(user) ?? defaultUser;

  /// 生效口令。没有就是空串（文件页/终端页据此给"先去设置里填"的引导）。
  String get effectivePassword => _nonEmpty(password) ?? '';

  /// 生效终端地址。
  String get effectiveTerminalUrl => _nonEmpty(terminalUrl) ?? defaultTerminalUrl;

  /// 有没有可用口令；没有时文件页/终端页要给"先去设置里填"的引导。
  bool get hasPassword => effectivePassword.isNotEmpty;

  bool get usedBuildDefaults =>
      _nonEmpty(baseUrl) == null || _nonEmpty(user) == null;

  /// 从本地读；读不出来就是"全都没填"（地址/用户名的构建默认值照旧生效）。
  static Future<ServerOpsSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return ServerOpsSettings(
        baseUrl: prefs.getString(baseUrlKey),
        user: prefs.getString(userKey),
        password: await _readPassword(prefs),
        terminalUrl: prefs.getString(terminalUrlKey),
      );
    } catch (_) {
      return const ServerOpsSettings();
    }
  }

  /// 口令来源：本机加密存储。
  ///
  /// 289 及以前把口令明文写在 SharedPreferences 里，这里做**一次性迁移**：
  /// 读到老键就搬进加密存储并删掉明文键 —— 不迁移等于老用户升级后要重新输一遍，
  /// 留着明文键则等于"改了但没改干净"。
  static Future<String?> _readPassword(SharedPreferences prefs) async {
    final secure = await serverOpsSecretStore.readPassword();
    if (_nonEmpty(secure) != null) return secure;
    final legacy = prefs.getString(passwordKey);
    if (legacy == null) return null;
    if (legacy.isNotEmpty) {
      await serverOpsSecretStore.writePassword(legacy);
    }
    await prefs.remove(passwordKey);
    return legacy;
  }

  /// 覆盖保存（只写非 null 的项）。空串表示"清掉这一项，回到构建默认"。
  Future<void> save({
    String? baseUrl,
    String? user,
    String? password,
    String? terminalUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (baseUrl != null) {
      await _writeTrimmed(prefs, baseUrlKey, baseUrl);
    }
    if (user != null) {
      await _writeTrimmed(prefs, userKey, user);
    }
    if (terminalUrl != null) {
      await _writeTrimmed(prefs, terminalUrlKey, terminalUrl);
    }
    if (password != null) {
      // 口令不做 trim：尾随空格可能是口令的一部分（粘贴场景很常见）。
      if (password.isEmpty) {
        await serverOpsSecretStore.clearPassword();
      } else {
        await serverOpsSecretStore.writePassword(password);
      }
      // 老版本的明文键必须一并清掉：留着它就是"明文还在 prefs 里"，白改。
      await prefs.remove(passwordKey);
    }
  }

  static Future<void> _writeTrimmed(
    SharedPreferences prefs,
    String key,
    String value,
  ) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, trimmed);
    }
  }

  static String? _nonEmpty(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
