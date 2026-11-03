/// 口令的摘要与比较。
///
/// 单独一个文件、只依赖 `crypto`（纯 Dart，不需要 Flutter/Android），
/// 目的是让这部分**能真跑起来验证** —— 定长时间比较这种「看起来对、
/// 其实早退」的实现，只有真跑一遍才敢说它对。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 口令长度范围。4 位太短容易被试，12 位以上没人愿意输。
const int kMinPinLength = 4;
const int kMaxPinLength = 12;

/// 口令只允许纯数字：计算器界面上只能输数字，允许字母等于自相矛盾。
bool isValidPin(String pin) {
  if (pin.length < kMinPinLength || pin.length > kMaxPinLength) return false;
  return RegExp(r'^[0-9]+$').hasMatch(pin);
}

/// 生成每安装随机的 16 字节盐（hex）。
String randomSaltHex() {
  final random = Random.secure();
  final bytes = Uint8List(16);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// `sha256("<salt>:<pin>")` 的 hex 形式。
String hashPin(String salt, String pin) {
  final digest = sha256.convert(utf8.encode('$salt:$pin'));
  return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// 定长时间 hex 比较。
///
/// 为什么不能直接用 `==`：Dart 的字符串比较遇到第一个不同的字符就返回。
/// 时间差虽小，但对同一个口令反复试探时可以统计出来。这里把两个 hex 都摊成
/// 固定 32 字节再逐字节异或累加，**循环次数与会话内容无关**，也不提前 return。
bool constantTimeHexEquals(String a, String b) {
  final left = _hexToFixedBytes(a);
  final right = _hexToFixedBytes(b);
  var diff = 0;
  for (var i = 0; i < left.length; i++) {
    diff |= left[i] ^ right[i];
  }
  // 长度信息也参与判定，但同样不提前返回。
  diff |= (a.length == b.length) ? 0 : 1;
  return diff == 0;
}

/// 恢复码字母表。
///
/// 为什么不是口令那套 0–9：恢复码要**手抄**，而且不能被旁边看一眼就记住。
/// 所以它有字母、有 16 位；同时刻意剔掉了 `0 O 1 I L` —— 这几个字符在纸上
/// 和屏幕上是同一种糊，抄错一位就等于把用户锁在门外。
const String kRecoveryAlphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

/// 恢复码的有效字符数（不含分组连字符）。
const int kRecoveryLength = 16;

/// 每组长度：`XXXX-XXXX-XXXX-XXXX`。
const int kRecoveryGroup = 4;

/// 生成一枚恢复码，形如 `K7QT-M2XR-9WPD-4FZG`。
///
/// 熵：31^16 ≈ 2^79，离线爆破不现实；所以**不需要**再给恢复码加尝试次数限制，
/// 加了反而会在计算器界面上暴露「这里有个东西在防爆破」。
String randomRecoveryCode() {
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < kRecoveryLength; i++) {
    buffer.write(kRecoveryAlphabet[random.nextInt(kRecoveryAlphabet.length)]);
  }
  return formatRecoveryCode(buffer.toString());
}

/// 把裸串排成 4 组 4 位；长度不对就只做归一化后原样返回（由调用方去判非法）。
String formatRecoveryCode(String raw) {
  final normalized = normalizeRecoveryCode(raw);
  if (normalized.length != kRecoveryLength) return normalized;
  final buffer = StringBuffer();
  for (var i = 0; i < normalized.length; i++) {
    if (i > 0 && i % kRecoveryGroup == 0) buffer.write('-');
    buffer.write(normalized[i]);
  }
  return buffer.toString();
}

/// 归一化用户输入：只保留字母数字并转大写。
///
/// 抄写时随手加的空格、换行、连字符全部忽略；用户把小写抄成大写也不影响。
/// 反过来，输入里不该出现的字符（`0 O 1 I L`）**故意不映射**：恢复码本身
/// 不含这些字母，映射只会把「抄错了」伪装成「码不对」。
String normalizeRecoveryCode(String input) {
  final buffer = StringBuffer();
  for (final rune in input.toUpperCase().runes) {
    final char = String.fromCharCode(rune);
    if (_isAsciiAlnum(char)) buffer.write(char);
  }
  return buffer.toString();
}

bool _isAsciiAlnum(String char) {
  final code = char.codeUnitAt(0);
  final isDigit = code >= 0x30 && code <= 0x39;
  final isUpper = code >= 0x41 && code <= 0x5a;
  return isDigit || isUpper;
}

/// 把任意 hex 字符串读成固定 32 字节（不足补 0，超长截断，非法字符整段作废）。
Uint8List _hexToFixedBytes(String hex) {
  final bytes = Uint8List(32);
  var byteIndex = 0;
  for (var i = 0; i + 1 < hex.length && byteIndex < bytes.length; i += 2) {
    final value = int.tryParse(hex.substring(i, i + 2), radix: 16);
    if (value == null) {
      // 非法字符：整段判为不匹配，但仍然返回固定长度、不改变上层循环次数。
      bytes.fillRange(0, bytes.length, 0xff);
      return bytes;
    }
    bytes[byteIndex++] = value;
  }
  return bytes;
}
