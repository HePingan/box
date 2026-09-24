// 本地密文编解码：每安装随机密钥 + AES-GCM（带认证）+ 旧格式兼容读。
//
// 为什么需要它（原方案 §6.1 已如实标注的缺口）：
// 旧实现是 `密钥 = sha256('box-xxx-v1')`——**盐是编译期常量，所以所有用户的
// 密钥完全相同**，密文只是"每次随机 IV"不同。一次密钥泄露（逆向一份 APK 即可）
// 就能解开所有安装的凭据；且 AES-CBC 无认证，密文被改动只会解出乱码而不是报错。
//
// 本文件的两处升级：
// 1. 密钥材料是**每安装随机 32 字节**（首次使用时生成并落盘），按模块 context
//    派生各自密钥——一次泄露不再横扫所有安装，模块之间也不共用密钥；
// 2. 算法换 **AES-GCM**：密文被改动会解密失败（返回 null），不会静默解出垃圾。
//
// 仍然**不防逆向/不防 root**（密钥与密文同在一台设备上）：真正要防这两者需要
// Android Keystore 包裹密钥（需引入 flutter_secure_storage 之类的插件，且只能
// 在真机上验证），属于 C1 的剩余部分。本文件把这件事隔离在 `openWithPrefs` 一处，
// 将来换成 Keystore 只需要改这一个函数。

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 每安装密钥材料的存储键（32 字节的 base64）。
///
/// 材料本身不是"机密"（它和密文在同一台设备上），但它决定"这份安装的密钥"，
/// 因此不能跨安装复用、不能进备份——备份开关见 AndroidManifest 的 allowBackup。
const String kLocalKeyMaterialPrefsKey = 'box.localKeyMaterial.v1';

/// 新格式密文前缀：`B2` + base64(nonce ‖ ciphertext‖tag)。
///
/// 带前缀是为了**区分新旧格式**：读取时先按新格式解，不像旧格式再看旧格式，
/// 从而支持"装上新版后第一次读就自动迁移"。
const String _v2Magic = 'B2';

/// GCM nonce 长度（12 字节是 GCM 的标准长度）。
const int _nonceLength = 12;

/// 本地密文编解码器。用 [open] 或 [openWithPrefs] 获取实例。
class LocalSecretCodec {
  LocalSecretCodec._(this._key, this.context);

  final enc.Key _key;

  /// 模块标识（如 `remote-storage` / `account`）：同一次安装里不同模块派生
  /// 不同密钥，避免一个模块的密钥泄露连带另一个模块。
  final String context;

  /// 打开（必要时创建）本安装的密钥材料，并派生 [context] 专用密钥。
  static Future<LocalSecretCodec> open(String context) async {
    final prefs = await SharedPreferences.getInstance();
    return openWithPrefs(prefs, context);
  }

  /// 同 [open]，但由调用方提供 prefs（测试与"同一事务里读写多个键"用）。
  ///
  /// **这是唯一接触密钥材料的地方**：将来用 Android Keystore 包裹密钥（C1 剩余
  /// 部分）时，只改这个函数即可，其余加密/解密路径不用动。
  static Future<LocalSecretCodec> openWithPrefs(
    SharedPreferences prefs,
    String context,
  ) async {
    var material = prefs.getString(kLocalKeyMaterialPrefsKey);
    if (material == null || material.trim().isEmpty) {
      material = base64.encode(_secureRandom(32));
      await prefs.setString(kLocalKeyMaterialPrefsKey, material);
    }
    return LocalSecretCodec._(_deriveKey(material, context), context);
  }

  /// 加密：`B2` + base64(nonce ‖ 密文+认证标签)。
  String encrypt(String plainText) {
    final nonce = enc.IV(_secureRandom(_nonceLength));
    final encrypter = enc.Encrypter(enc.AES(_key, mode: enc.AESMode.gcm));
    final cipher = encrypter.encrypt(plainText, iv: nonce);
    final combined = Uint8List(nonce.bytes.length + cipher.bytes.length);
    combined.setRange(0, nonce.bytes.length, nonce.bytes);
    combined.setRange(nonce.bytes.length, combined.length, cipher.bytes);
    return '$_v2Magic${base64.encode(combined)}';
  }

  /// 解密新格式；格式不符、被篡改（GCM 认证失败）、密钥不对都返回 null。
  String? decrypt(String encoded) {
    if (!encoded.startsWith(_v2Magic)) return null;
    try {
      final raw = base64.decode(encoded.substring(_v2Magic.length));
      if (raw.length <= _nonceLength) return null;
      final nonce = enc.IV(Uint8List.fromList(raw.sublist(0, _nonceLength)));
      final cipher = enc.Encrypted(
        Uint8List.fromList(raw.sublist(_nonceLength)),
      );
      final encrypter = enc.Encrypter(enc.AES(_key, mode: enc.AESMode.gcm));
      return encrypter.decrypt(cipher, iv: nonce);
    } catch (_) {
      return null;
    }
  }

  /// 是否像旧格式（固定盐 AES-CBC）的密文。
  static bool looksLegacy(String encoded) => !encoded.startsWith(_v2Magic);

  /// 旧格式解密：`base64(iv(16) ‖ AES-CBC(密钥 = sha256(legacySalt)))`。
  ///
  /// 只为迁移而存在：读到旧密文能解出来就用它，随后由调用方按新格式重写。
  /// 新代码不允许用它加密。
  static String? decryptLegacy(String encoded, String legacySalt) {
    try {
      final raw = base64.decode(encoded);
      if (raw.length < 17) return null;
      final key = sha256.convert(utf8.encode(legacySalt)).bytes;
      final iv = enc.IV(Uint8List.fromList(raw.sublist(0, 16)));
      final cipher = enc.Encrypted(Uint8List.fromList(raw.sublist(16)));
      final encrypter = enc.Encrypter(
        enc.AES(enc.Key(Uint8List.fromList(key)), mode: enc.AESMode.cbc),
      );
      return encrypter.decrypt(cipher, iv: iv);
    } catch (_) {
      return null;
    }
  }

  /// 由密钥材料与 context 派生该模块的 32 字节密钥。
  ///
  /// 这里用一次 SHA-256 而不是 PBKDF2：材料本身就是 32 字节全熵随机量，没有
  /// 需要"拉伸"的低熵口令；把 context 拼进去是为了让不同模块密钥不同。
  static enc.Key _deriveKey(String material, String context) {
    final digest = sha256.convert(
      utf8.encode('box-local-key-v2|$context|$material'),
    ).bytes;
    return enc.Key(Uint8List.fromList(digest));
  }

  static Uint8List _secureRandom(int length) =>
      enc.IV.fromSecureRandom(length).bytes;

  @override
  String toString() => 'LocalSecretCodec($context)';
}
