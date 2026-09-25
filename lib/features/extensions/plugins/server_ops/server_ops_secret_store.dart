// 运维通道口令的本机加密存储（C1 中期档）。
//
// 为什么不再把口令打进安装包：APK 挂在公网可直接下载，构建注入等于"谁下载谁就拿到
// 服务器 root"（整盘读写 + root shell）—— 288/289 就是这么发的，反编译取字符串即可。
// 现在的口径：口令**只由用户首次输入、只存本机**，Android 侧走 Keystore 支持的
// AES-GCM 加密 + RSA-OAEP 密钥包裹（flutter_secure_storage 默认参数）。
//
// 为什么要一个接口而不是直接调用：平台通道在单测里根本不存在，测试必须能注入内存实现。
// 与仓库既有风格一致：模块级单例 + debugSetXxx 测试接缝。
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 口令的读写。实现必须自己处理"没存过"的情况（返回 null）。
abstract class OpsSecretStore {
  Future<String?> readPassword();

  Future<void> writePassword(String password);

  Future<void> clearPassword();
}

/// 默认实现：flutter_secure_storage（Android Keystore / iOS Keychain）。
class KeystoreOpsSecretStore implements OpsSecretStore {
  KeystoreOpsSecretStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// 键名与 Settings 里那个明文键同名是刻意的：迁移时一眼能对上。
  static const String key = 'serverOps.dav.password';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readPassword() => _storage.read(key: key);

  @override
  Future<void> writePassword(String password) =>
      _storage.write(key: key, value: password);

  @override
  Future<void> clearPassword() => _storage.delete(key: key);
}

OpsSecretStore _active = KeystoreOpsSecretStore();

/// 当前生效的存储实现（测试注入优先）。
OpsSecretStore get serverOpsSecretStore => _active;

/// 测试接缝：不传参恢复默认实现（与 debugSetServerOpsRuntime 同形状）。
void debugSetOpsSecretStore([OpsSecretStore? store]) {
  _active = store ?? KeystoreOpsSecretStore();
}
