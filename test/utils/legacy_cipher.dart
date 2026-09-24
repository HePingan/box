// 测试专用：按"旧版实现"（固定盐 + AES-CBC）生成密文。
//
// 存在的意义只有一个：验证 C1 的迁移路径——旧版本写下的密文，新版本必须还能
// 解出来（用户升级后不被登出），并且解出来后会被重写成新格式。
// 新代码不得使用本文件。

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// 旧格式加密：`base64(iv(16) ‖ AES-CBC(密钥 = sha256(salt)))`。
String legacyEncrypt(String plainText, String legacySalt) {
  final key = enc.Key(
    Uint8List.fromList(sha256.convert(utf8.encode(legacySalt)).bytes),
  );
  final iv = enc.IV.fromSecureRandom(16);
  final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
  final encrypted = encrypter.encrypt(plainText, iv: iv);
  final combined = Uint8List(iv.bytes.length + encrypted.bytes.length);
  combined.setRange(0, iv.bytes.length, iv.bytes);
  combined.setRange(iv.bytes.length, combined.length, encrypted.bytes);
  return base64.encode(combined);
}
