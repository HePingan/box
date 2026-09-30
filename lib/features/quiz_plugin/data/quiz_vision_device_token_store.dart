// 匿名设备令牌 / 设备标识的本机加密存储（quiz-vision 方案 A 第二轮）。
//
// 为什么需要它：读屏改成「客户端零内置密钥」后，**未登录**用户也必须走平台
// 代理，而代理要一个 Bearer。服务端按设备签发匿名令牌（POST
// /api/quiz/vision/device-token），客户端把它和设备标识存本机。
//
// 为什么存 Keystore 而不是 SharedPreferences：令牌是可直接换读屏调用的凭证，
// 与账号 token 同级；Android 侧走 flutter_secure_storage 的 AES-GCM +
// RSA-OAEP 密钥包裹（默认参数）。
//
// 为什么要一个接口而不是直接调：平台通道在单测里根本不存在，测试必须能注入内存实现。
// 与仓库既有风格一致（见 server_ops_secret_store.dart）：模块级单例 + debugSetXxx 接缝。
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 设备标识与设备令牌的读写。实现必须自己处理「没存过」的情况（返回 null）。
abstract class QuizVisionDeviceTokenStore {
  /// 读本机设备标识；没生成过返回 null。
  Future<String?> readDeviceId();

  Future<void> writeDeviceId(String deviceId);

  /// 读本机设备令牌；没签发过返回 null。
  Future<String?> readDeviceToken();

  Future<void> writeDeviceToken(String token);

  /// 令牌被服务端拒（401）时清掉，下次重新签发。
  Future<void> clearDeviceToken();
}

/// 默认实现：flutter_secure_storage（Android Keystore / iOS Keychain）。
class KeystoreQuizVisionDeviceTokenStore implements QuizVisionDeviceTokenStore {
  KeystoreQuizVisionDeviceTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  /// 设备标识键（不透明串，服务端按它签发/限额）。
  static const String deviceIdKey = 'quizVision.deviceId';

  /// 设备令牌键（与设备标识分开命名：令牌会被撤销/重签，标识在设备生命周期内不变）。
  static const String deviceTokenKey = 'quizVision.deviceToken';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readDeviceId() => _storage.read(key: deviceIdKey);

  @override
  Future<void> writeDeviceId(String deviceId) =>
      _storage.write(key: deviceIdKey, value: deviceId);

  @override
  Future<String?> readDeviceToken() => _storage.read(key: deviceTokenKey);

  @override
  Future<void> writeDeviceToken(String token) =>
      _storage.write(key: deviceTokenKey, value: token);

  @override
  Future<void> clearDeviceToken() => _storage.delete(key: deviceTokenKey);
}

QuizVisionDeviceTokenStore _active = KeystoreQuizVisionDeviceTokenStore();

/// 当前生效的存储实现（测试经 `QuizVisionCredentialResolver` 的构造器注入替换）。
QuizVisionDeviceTokenStore get quizVisionDeviceTokenStore => _active;
