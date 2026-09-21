/// 批次 2 的纯本地逻辑：JSON / 正则 / Base64 / 哈希 / URL 编码 / 文本统计 /
/// 颜文字。
///
/// 和 [local_tool_math] 一样的分工：这里全是确定性纯函数（能在单测里全量
/// 覆盖），UI 层只管收输入、画结果。不联网、不碰平台通道。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 文本类工具的输入错误。
class TextToolError implements Exception {
  const TextToolError(this.message);

  final String message;

  @override
  String toString() => message;
}

// ───────────────────────────────── JSON ─────────────────────────────────

/// 美化 JSON。两空格缩进，**保留中文原样**（`jsonEncode` 默认不转义非 ASCII，
/// 直接用它；之前有人用 `JsonEncoder.withIndent` 配 `toEncodable` 反而把中文
/// 转成 `\uXXXX` 了）。
String formatJson(String input) {
  final v = _decodeJsonObject(input);
  return const JsonEncoder.withIndent('  ').convert(v);
}

/// 压缩 JSON：去掉所有非必要空白。
String minifyJson(String input) {
  final v = _decodeJsonObject(input);
  return jsonEncode(v);
}

/// 解析并校验「顶层必须是对象或数组」。
///
/// 裸的 `123` / `"abc"` / `true` 是合法 JSON，但作为「JSON 格式化」的输入
/// 一定是用户搞错了 —— 直接明说，不返回一个看起来成功的 `123`。
Object? _decodeJsonObject(String input) {
  final s = input.trim();
  if (s.isEmpty) throw const TextToolError('请输入要处理的 JSON');
  Object? v;
  try {
    v = jsonDecode(s);
  } on FormatException catch (e) {
    throw TextToolError('JSON 格式不对：${e.message}');
  }
  if (v is! Map && v is! List) {
    throw const TextToolError(
      '顶层要是一个对象 {} 或数组 [] —— 现在这个不是',
    );
  }
  return v;
}

// ──────────────────────────────── 正则 ────────────────────────────────

/// 一条匹配结果。
class RegexMatch {
  const RegexMatch({
    required this.text,
    required this.start,
    required this.end,
    required this.groups,
  });

  /// 整段匹配到的文本。
  final String text;
  final int start;
  final int end;

  /// 捕获组内容（不含组 0）；未参与匹配的组为 null。
  final List<String?> groups;
}

class RegexResult {
  const RegexResult({required this.matches, required this.elapsedMicros});

  final List<RegexMatch> matches;
  final int elapsedMicros;

  bool get isEmpty => matches.isEmpty;
  int get count => matches.length;
}

/// 在 [input] 里跑 [pattern]，列出**所有**匹配（默认全局，不只是第一个）。
RegexResult testRegex(String pattern, String input) {
  if (pattern.isEmpty) throw const TextToolError('请输入正则表达式');
  late final RegExp re;
  try {
    re = RegExp(pattern);
  } on FormatException catch (e) {
    throw TextToolError('正则写错了：${e.message}');
  }

  final sw = Stopwatch()..start();
  final out = <RegexMatch>[];
  for (final m in re.allMatches(input)) {
    out.add(
      RegexMatch(
        text: m.group(0) ?? '',
        start: m.start,
        end: m.end,
        groups: [
          for (var i = 1; i <= m.groupCount; i++) m.group(i),
        ],
      ),
    );
  }
  sw.stop();
  return RegexResult(matches: out, elapsedMicros: sw.elapsedMicroseconds);
}

// ─────────────────────────────── Base64 ───────────────────────────────

/// 文本 → Base64（UTF-8 编码，中文可用）。
String base64EncodeText(String input) =>
    base64Encode(utf8.encode(input));

/// Base64 → 文本。容忍换行/空格（很多地方会折行粘贴）。
String base64DecodeText(String input) {
  final clean = input.replaceAll(RegExp(r'\s+'), '');
  if (clean.isEmpty) throw const TextToolError('请输入要解码的 Base64');
  try {
    return utf8.decode(base64Decode(clean));
  } on FormatException catch (e) {
    throw TextToolError('不是合法的 Base64：${e.message}');
  }
}

// ──────────────────────────────── 哈希 ────────────────────────────────

enum HashAlgo {
  md5('MD5'),
  sha1('SHA-1'),
  sha256('SHA-256');

  const HashAlgo(this.label);

  final String label;
}

/// 计算摘要，返回小写十六进制。
String hashText(String input, HashAlgo algo) {
  final bytes = utf8.encode(input);
  final digest = switch (algo) {
    HashAlgo.md5 => md5.convert(bytes),
    HashAlgo.sha1 => sha1.convert(bytes),
    HashAlgo.sha256 => sha256.convert(bytes),
  };
  return digest.toString();
}

// ────────────────────────────── URL 编码 ──────────────────────────────

/// RFC 3986 的 unreserved 字符集：`A-Z a-z 0-9 - _ . ~`。
///
/// Dart 的 `Uri.encodeComponent` 保留得太少（把 `-_.~` 之外的都编了），
/// 而且空格会编成 `%20`（这个是对的，比 `+` 通用）—— 这里显式白名单，
/// 让编码结果和标准一致、可读。
final RegExp _unreserved = RegExp(r'[A-Za-z0-9\-_.~]');

String urlEncodeText(String input) {
  final buf = StringBuffer();
  for (final byte in utf8.encode(input)) {
    final ch = String.fromCharCode(byte);
    if (byte < 0x80 && _unreserved.hasMatch(ch)) {
      buf.write(ch);
    } else {
      buf.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return buf.toString();
}

/// 百分号解码。非法序列（`%` 后面不是两位十六进制）明确报错 ——
/// 静默留下 `%E4` 会让人以为解码成功了。
String urlDecodeText(String input) {
  final out = <int>[];
  for (var i = 0; i < input.length; i++) {
    final c = input[i];
    if (c != '%') {
      out.addAll(utf8.encode(c));
      continue;
    }
    if (i + 2 >= input.length) {
      throw TextToolError('第 ${i + 1} 个位置的 % 后面不完整');
    }
    final hex = input.substring(i + 1, i + 3);
    final v = int.tryParse(hex, radix: 16);
    if (v == null) {
      throw TextToolError('第 ${i + 1} 个位置不是合法百分号编码：%$hex');
    }
    out.add(v);
    i += 2;
  }
  try {
    return utf8.decode(out);
  } on FormatException catch (e) {
    throw TextToolError('解码后不是合法 UTF-8：${e.message}');
  }
}

// ────────────────────────────── 文本统计 ──────────────────────────────

class TextStats {
  const TextStats({
    required this.chars,
    required this.charsNoSpace,
    required this.lines,
    required this.words,
  });

  final int chars;
  final int charsNoSpace;
  final int lines;

  /// 词数：连续的拉丁字母/数字算一个词，连续的 CJK 字符算一个词。
  final int words;
}

TextStats textStats(String input) {
  if (input.isEmpty) {
    return const TextStats(chars: 0, charsNoSpace: 0, lines: 0, words: 0);
  }
  final runes = input.runes.length;
  final noSpace = input.replaceAll(RegExp(r'\s'), '').runes.length;
  final lines = input.split('\n').length;

  // 拉丁/数字块 + CJK 块，各算一个词。
  final wordRe = RegExp(
    r'[A-Za-z0-9]+|[\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]+',
  );
  final words = wordRe.allMatches(input).length;

  return TextStats(
    chars: runes,
    charsNoSpace: noSpace,
    lines: lines,
    words: words,
  );
}

// ────────────────────────────── 颜文字 ──────────────────────────────

/// 内置颜文字表。纯静态数据，不依赖任何接口。
const List<String> kaomojiList = [
  '(＾▽＾)',
  '(￣▽￣)',
  '(๑•̀ㅂ•́)و✧',
  '(╯°□°）╯',
  '(づ｡◕‿‿◕｡)づ',
  '(´・ω・`)',
  'ಠ_ಠ',
  '(；一_一)',
  '(=￣ω￣=)',
  '(っ °Д °;)っ',
  '¯\\_(ツ)_/¯',
  '(๑´ㅂ`๑)',
  '(*/ω＼*)',
  '(＾• ω •＾)',
  'ヽ(￣ω￣(￣ω￣〃)ゞ',
  '(￣ε￣＠)',
  '(๑˘︶˘๑)',
  '(￣﹃￣)',
  'Σ(っ °Д °;)っ',
  '(눈_눈)',
  '(◕ᴗ◕✿)',
  '(◍•ᴗ•◍)',
  '(◔◡◔)',
  '(*・ω・)ﾉ',
];

/// 按下标取颜文字，越界自动取模（不会抛异常）。
String pickKaomoji(int index) =>
    kaomojiList[index % kaomojiList.length];
