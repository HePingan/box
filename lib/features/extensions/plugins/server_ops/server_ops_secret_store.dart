// 运维通道口令的本机加密存储（C1 中期档 / B1 多服务器）。
//
// 为什么不再把口令打进安装包：APK 挂在公网可直接下载，构建注入等于"谁下载谁就拿到
// 服务器 root"（整盘读写 + root shell）—— 288/289 就是这么发的，反编译取字符串即可。
// 现在的口径：口令**只由用户首次输入、只存本机**，Android 侧走 Keystore 支持的
// AES-GCM 加密 + RSA-OAEP 密钥包裹（flutter_secure_storage 默认参数）。
//
// B1 起口令**按服务器分键**：一台机器一个键 `serverOps.dav.password.<服务器 id>`。
// 两台机器口令不同是常态（175 是运维机），共用一个键等于"改一台把另一台的口令也改了"。
// 单服务器时代的老键 `serverOps.dav.password`（只有一台机器、没有后缀）由
// ServerOpsSettings.load() 做一次性迁移 —— 见那里的 _migrateLegacy()。
//
// 为什么要一个接口而不是直接调用：平台通道在单测里根本不存在，测试必须能注入内存实现。
// 与仓库既有风格一致：模块级单例 + debugSetXxx 测试接缝。
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 口令的读写。实现必须自己处理"没存过"的情况（返回 null）。
abstract class OpsSecretStore {
  /// 读某台服务器保存的口令；没存过返回 null。
  Future<String?> readPassword(String serverId);

  Future<void> writePassword(String serverId, String password);

  Future<void> clearPassword(String serverId);

  /// 读**老键**（单服务器时代的 `serverOps.dav.password`）：只在迁移时用一次。
  Future<String?> readLegacyPassword();

  /// 删掉老键；迁移完成后必须调，否则老口令会一直留在加密存储里。
  Future<void> clearLegacyPassword();
}

/// 默认实现：flutter_secure_storage（Android Keystore / iOS Keychain）。
class KeystoreOpsSecretStore implements OpsSecretStore {
  KeystoreOpsSecretStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// 老键（289–290 的单服务器时代）：键名与 SharedPreferences 里那个明文键同名是
  /// 刻意的 —— 迁移时一眼能对上。
  static const String legacyKey = 'serverOps.dav.password';

  /// 某台服务器的口令键：`serverOps.dav.password.<id>`。
  static String keyFor(String serverId) => '$legacyKey.$serverId';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readPassword(String serverId) =>
      _storage.read(key: keyFor(serverId));

  @override
  Future<void> writePassword(String serverId, String password) =>
      _storage.write(key: keyFor(serverId), value: password);

  @override
  Future<void> clearPassword(String serverId) =>
      _storage.delete(key: keyFor(serverId));

  @override
  Future<String?> readLegacyPassword() => _storage.read(key: legacyKey);

  @override
  Future<void> clearLegacyPassword() => _storage.delete(key: legacyKey);
}

OpsSecretStore _active = KeystoreOpsSecretStore();

/// 当前生效的存储实现（测试注入优先）。
OpsSecretStore get serverOpsSecretStore => _active;

/// 测试接缝：不传参恢复默认实现（与 debugSetServerOpsRuntime 同形状）。
void debugSetOpsSecretStore([OpsSecretStore? store]) {
  _active = store ?? KeystoreOpsSecretStore();
}
