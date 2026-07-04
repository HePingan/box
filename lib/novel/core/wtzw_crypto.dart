import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

class WtzwCrypto {
  WtzwCrypto._();

  static const String signKey = 'd3dGiJc651gSQ8w1';
  static const String chapterContentKey = '242ccb8230d709e1';
  static const String imeiIp = '2937357107';

  static String md5Sign(Map<String, dynamic> data) {
    final normalized = <String, String>{};
    for (final entry in data.entries) {
      if (entry.value == null) continue;
      normalized[entry.key] = '${entry.value}';
    }

    final keys = normalized.keys.toList()..sort();
    final raw = StringBuffer();
    for (final key in keys) {
      raw.write('$key=${normalized[key] ?? ''}');
    }
    raw.write(signKey);

    return md5.convert(utf8.encode(raw.toString())).toString();
  }

  static Map<String, String> withParamSign(Map<String, dynamic> params) {
    final normalized = <String, String>{};
    for (final entry in params.entries) {
      if (entry.value == null) continue;
      normalized[entry.key] = '${entry.value}';
    }

    normalized['sign'] = md5Sign(normalized);
    return normalized;
  }

  static String encryptChapterContent(String plainText) {
    final key = enc.Key.fromUtf8(chapterContentKey);
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(
      enc.AES(key, mode: enc.AESMode.cbc, padding: 'PKCS7'),
    );

    final encrypted = encrypter.encrypt(plainText, iv: iv);
    final bytes = Uint8List.fromList(iv.bytes + encrypted.bytes);
    return base64Encode(bytes);
  }

  static String decryptChapterContent(String encodedContent) {
    try {
      final raw = encodedContent.trim();
      if (raw.isEmpty) return encodedContent;

      final allBytes = base64Decode(raw);
      if (allBytes.length <= 16) return raw;

      final ivBytes = Uint8List.fromList(allBytes.sublist(0, 16));
      final cipherBytes = Uint8List.fromList(allBytes.sublist(16));

      final encrypter = enc.Encrypter(
        enc.AES(
          enc.Key.fromUtf8(chapterContentKey),
          mode: enc.AESMode.cbc,
          padding: 'PKCS7',
        ),
      );

      return encrypter.decrypt(enc.Encrypted(cipherBytes), iv: enc.IV(ivBytes));
    } catch (_) {
      return encodedContent;
    }
  }
}
