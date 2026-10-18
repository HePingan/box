/// 从片源给的集名里抽出「第几集」。
///
/// ## 为什么需要它
///
/// 集名是**片源原样给的**（`detail_play_parser.dart` 里 `ep.name` 直接透传），
/// 站点之间格式完全不统一。实测见过这些形状：
///
/// ```
/// 第04集          第04集 高清      第4集-中字
/// 天才女友 第04集   04              04-HD
/// ```
///
/// 而详情页的选集格子只有几十 dp 宽、单行截断。站名长一点就变成「第04…」——
/// 用户看不出这是第几集，而"点第几集"恰恰是他唯一在做的事。
///
/// 所以把「序号」与「其余文字」拆开：序号做大且永远完整，其余降级成小字副注。
///
/// ## 刻意保守的地方
///
/// * 抽不出序号就返回 null，**不猜**（宁可显示原名，也不要显示一个错的编号）；
/// * 4 位数且 ≥1900 的当成**年份**跳过（「2026 高清」不是第 2026 集）；
/// * 只认第一个数字段（「第04集 第2部分」取 04，因为集数是主序号）；
/// * 补零到 2 位（`第4集` 与 `第04集` 统一成 `04`），超过 99 集则不补零。
library;

/// 一个集名的拆解结果。
class EpisodeLabelParts {
  const EpisodeLabelParts({required this.number, required this.rest});

  /// 抽到的序号（已补零成至少 2 位，如 `04`、`104`）。抽不到时为 null。
  final String? number;

  /// 去掉序号后剩下的文字（清理过的：去首尾分隔符、压缩空白）。
  /// 没有剩余内容时是空串。
  final String rest;

  /// 是否真的抽到了序号。
  bool get hasNumber => number != null;
}

/// 解析集名。永远返回结果（抽不到序号时 `number` 为 null、`rest` 是清洗后的原名）。
EpisodeLabelParts parseEpisodeLabel(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return const EpisodeLabelParts(number: null, rest: '');
  }

  // 抓第一个数字段。允许前后有「第」「集」「话」「期」这类标记。
  final match = RegExp(r'\d{1,4}').firstMatch(text);
  if (match == null) {
    return EpisodeLabelParts(number: null, rest: _tidy(text));
  }

  final digits = match.group(0)!;
  final value = int.tryParse(digits);

  // 4 位数且像年份：不当集号。1900 是拍的 —— 电视剧没有 1900 集，
  // 而「2024」这类出现在集名里几乎都是年份/清晰度标记。
  if (value == null || (digits.length == 4 && value >= 1900)) {
    return EpisodeLabelParts(number: null, rest: _tidy(text));
  }

  // 补零：<=99 补到 2 位（04），三位及以上原样（104）。
  final number = value <= 99 ? value.toString().padLeft(2, '0') : '$value';

  // 「其余文字」= 去掉数字本身 + 紧邻的「第 / 集 / 话 / 期」标记。
  var rest = text.replaceFirst(match.group(0)!, '\u0000');
  // 先把剩余内容里的编号标记词去掉（只各去掉一次，避免误伤标题里的字）
  for (final marker in const ['第', '集', '話', '话', '期', '话']) {
    rest = rest.replaceFirst(marker, '');
  }
  rest = rest.replaceAll('\u0000', '');
  return EpisodeLabelParts(number: number, rest: _tidy(rest));
}

/// 清洗剩下的文字：去首尾的分隔符与空白，压缩中间空白。
///
/// 为什么要这一步：`第04集 高清` → 去掉编号后剩下「 高清」，前导空格会让
/// 小字副注看起来没对齐；`第04集-中字` 剩下的 `-中字` 前导横线同样难看。
String _tidy(String input) {
  var out = input.replaceAll(RegExp(r'\s+'), ' ').trim();
  // 反复剥掉首尾的分隔符（`-中字` → `中字`，`(高清)` 保留括号）
  const trims = ['-', '_', '|', '/', '·', '：', ':', '，', ',', '.', '、'];
  var changed = true;
  while (changed && out.isNotEmpty) {
    changed = false;
    for (final t in trims) {
      if (out.startsWith(t)) {
        out = out.substring(t.length).trim();
        changed = true;
      }
      if (out.endsWith(t)) {
        out = out.substring(0, out.length - t.length).trim();
        changed = true;
      }
    }
  }
  return out;
}

/// 判断一个线路名是不是**站点技术名**（`lzm3u8` / `liangzi` / `quantum` / `line1`）。
///
/// ## 为什么需要判断
///
/// 线路名同样是片源原样给的。实测有「量子资源」「lzm3u8」「line1」三种形态：
/// 前一种用户能读，后两种是站点的接口标识 —— 直接摆在主位置像乱码。
///
/// ## 判据（保守：宁可判成人话，也不要把它改掉）
///
/// 满足**任一**就算技术名：
///   * 不含任何中日韩字符（纯 ASCII 且长度 <= 24）；
///   * 含下划线/点号这类编程标识符字符，且不含空格。
///
/// 刻意**不**把「HD」「高清」「4K」这类当技术名 —— 它们是用户能理解的描述。
bool looksLikeTechnicalLineName(String name) {
  final text = name.trim();
  if (text.isEmpty) return false;

  // 用户能读懂的中文/日文/韩文：直接判成人话
  if (RegExp(r'[\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]').hasMatch(text)) {
    return false;
  }
  // 常见清晰度标记也是人话
  final lower = text.toLowerCase();
  if (const ['hd', 'sd', '4k', '8k', '1080p', '720p', '蓝光', '超清', '高清']
      .contains(lower)) {
    return false;
  }
  // 纯 ASCII 且短 → 像接口标识
  if (text.length <= 24 && RegExp(r'^[A-Za-z0-9_.\-]+$').hasMatch(text)) {
    return true;
  }
  return false;
}

/// 给线路一个**用户能读**的显示名。
///
/// 返回 `(主显示, 副注)`：
///   * 人话名 → `('量子资源', '')`
///   * 技术名 → `('线路 1', 'lzm3u8')` —— 序号由调用方给（从 1 开始）
String lineDisplayName(String rawName, int index) {
  final name = rawName.trim();
  if (name.isEmpty) {
    return '线路 ${index + 1}';
  }
  if (!looksLikeTechnicalLineName(name)) {
    return name;
  }
  return '线路 ${index + 1}';
}

/// 技术名时返回原名（作副注用），人话名返回空串。
String lineSubName(String rawName) {
  final name = rawName.trim();
  return looksLikeTechnicalLineName(name) ? name : '';
}
