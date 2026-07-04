import 'package:encrypt/encrypt.dart' as enc;

/// 规则书源加解密工具
class CryptoUtils {
  const CryptoUtils();

  /// 解析 @js: 表达式中的 AES 解密调用
  /// 支持格式: `java.aesBase64DecodeToString(result, "key", "AES/CBC/PKCS5Padding", "iv")`
  String evalJs(String jsExpr, String result) {
    final expr = jsExpr.trim();

    final aes = RegExp(
      r'java\.aesBase64DecodeToString\(\s*result\s*,\s*"([^"]+)"\s*,'
      r'\s*"AES/CBC/PKCS5Padding"\s*,\s*"([^"]+)"\s*\)',
    ).firstMatch(expr);

    if (aes != null) {
      final key = aes.group(1) ?? '';
      final iv = aes.group(2) ?? '';
      return aesBase64DecodeToString(result, key, iv);
    }

    return result;
  }

  /// AES/CBC/PKCS5Padding Base64 解码
  String aesBase64DecodeToString(String input, String key, String iv) {
    try {
      final normalized = normalizeBase64(input);
      final encrypter = enc.Encrypter(
        enc.AES(
          enc.Key.fromUtf8(key),
          mode: enc.AESMode.cbc,
          padding: 'PKCS7',
        ),
      );

      final plain = encrypter.decrypt64(
        normalized,
        iv: enc.IV.fromUtf8(iv),
      );

      return plain
          .replaceAll(r'\/', '/')
          .replaceAll('\\/', '/')
          .replaceAll('"', '')
          .trim();
    } catch (_) {
      return input;
    }
  }

  /// 标准化 Base64 字符串（处理 URL-safe 变体 + 补全填充）
  String normalizeBase64(String input) {
    var s = input.trim().replaceAll('-', '+').replaceAll('_', '/');
    final mod = s.length % 4;
    if (mod != 0) {
      s += '=' * (4 - mod);
    }
    return s;
  }
}
