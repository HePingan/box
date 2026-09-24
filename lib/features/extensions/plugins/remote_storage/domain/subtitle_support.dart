// 远程存储字幕支持（279 B3）的**纯逻辑**：只做候选识别与匹配排序。
//
// 真正的下载在播放页（需要网络 + video_player）。这里保持无 IO，便于单测。

import 'remote_storage_models.dart';

/// 支持的字幕扩展名（video_player 自带这两个解析器）。
const List<String> kSubtitleExtensions = <String>['.srt', '.vtt'];

/// 是否是字幕文件（按扩展名，大小写不敏感）。
bool isSubtitleFileName(String name) {
  final lower = name.toLowerCase();
  for (final ext in kSubtitleExtensions) {
    if (lower.endsWith(ext)) return true;
  }
  return false;
}

/// 是否是 WebVTT（决定用哪个解析器；其余按 SubRip 处理）。
bool isWebVttFileName(String name) => name.toLowerCase().endsWith('.vtt');

/// 去掉最后一个扩展名：`movie.zh.srt` → `movie.zh`。
String fileNameStem(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return name;
  return name.substring(0, dot);
}

/// 字幕是否对应这个视频：`movie.mp4` ↔ `movie.srt` / `movie.zh.srt`。
///
/// 判据是"去扩展名后相等，或以「视频名 + .」为前缀"，所以 `movie2020.srt`
/// 不会被误配到 `movie.mp4`。
bool subtitleMatchesVideo(String subtitleName, String videoName) {
  final sub = fileNameStem(subtitleName).toLowerCase();
  final video = fileNameStem(videoName).toLowerCase();
  if (sub.isEmpty || video.isEmpty) return false;
  return sub == video || sub.startsWith('$video.');
}

/// 候选字幕：同目录下所有字幕文件，**与视频同名的排前面**。
///
/// 用"稳定分区"而不是整体排序：同类之间保持服务端返回的顺序（通常已是名称序），
/// 用户看到的下标不会莫名其妙跳。
List<RemoteStorageEntry> subtitleCandidates(
  List<RemoteStorageEntry> entries,
  String videoName,
) {
  final subs = <RemoteStorageEntry>[
    for (final entry in entries)
      if (!entry.isDirectory && isSubtitleFileName(entry.name)) entry,
  ];
  final matched = <RemoteStorageEntry>[];
  final others = <RemoteStorageEntry>[];
  for (final entry in subs) {
    if (subtitleMatchesVideo(entry.name, videoName)) {
      matched.add(entry);
    } else {
      others.add(entry);
    }
  }
  return <RemoteStorageEntry>[...matched, ...others];
}

/// 一条字幕（解析结果，与 video_player 解耦，便于单测）。
class ParsedSubtitleCue {
  const ParsedSubtitleCue({
    required this.index,
    required this.start,
    required this.end,
    required this.text,
  });

  /// 序号（从 1 开始，解析时按出现顺序重新编号）。
  final int index;
  final Duration start;
  final Duration end;
  final String text;
}

/// 时间戳：`00:00:01,000`（SRT）/ `00:00:01.000`、`00:01.000`（VTT 允许省略小时）。
///
/// 解析失败返回 null——**不当成 0 处理**：把坏时间轴当成 0 会让整条字幕在第一秒闪一下，
/// 不如直接丢掉这一条（坏块的常见成因是编码错误，丢掉比乱显示诚实）。
Duration? parseSubtitleTimestamp(String raw) {
  final cleaned = raw.trim().replaceAll(',', '.');
  final match = RegExp(
    r'^(?:(\d+):)?(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?$',
  ).firstMatch(cleaned);
  if (match == null) return null;
  final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
  final minutes = int.tryParse(match.group(2) ?? '') ?? 0;
  final seconds = int.tryParse(match.group(3) ?? '') ?? 0;
  final fraction = match.group(4) ?? '';
  final millis = fraction.isEmpty ? 0 : int.parse(fraction.padRight(3, '0'));
  return Duration(
    hours: hours,
    minutes: minutes,
    seconds: seconds,
    milliseconds: millis,
  );
}

/// 去掉字幕正文里的排版标记：`<i>`/`<b>`/`<font …>`、`{\an8}`、`<00:00:01.000>`
/// 以及常见实体。
///
/// 播放器自己不做行内样式渲染，留着标签只会把 `<i>` 原样显示出来。
String stripSubtitleMarkup(String raw) => raw
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll(RegExp(r'\{[^}]*\}'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .trim();

/// 解析字幕文本（SRT / WebVTT 共用一套逻辑，差别只在时间戳分隔符与头部）。
///
/// video_player 包只导出了 `ClosedCaptionFile` 抽象，`SubRipCaptionFile` /
/// `WebVTTCaptionFile` 都在 `src/` 下没有导出，所以这里自己解析。
/// 坏块（无时间行、时间轴解析失败、正文为空）直接跳过，不影响其余字幕。
List<ParsedSubtitleCue> parseSubtitleText(String text, {bool webVtt = false}) {
  final normalized = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceFirst('\uFEFF', '');
  final cues = <ParsedSubtitleCue>[];
  final blocks = normalized.split(RegExp(r'\n[ \t]*\n'));
  for (final block in blocks) {
    final lines = <String>[
      for (final line in block.split('\n'))
        if (line.trim().isNotEmpty) line,
    ];
    if (lines.isEmpty) continue;
    var timeIndex = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].contains('-->')) {
        timeIndex = i;
        break;
      }
    }
    if (timeIndex < 0) continue; // `WEBVTT` 头、`NOTE` 注释块
    final parts = lines[timeIndex].split('-->');
    if (parts.length != 2) continue;
    final start = parseSubtitleTimestamp(parts[0]);
    // 结束时间后面可能跟 VTT cue 设置（`align:start position:10%`），只取第一段。
    final endField = parts[1].trim().split(RegExp(r'\s+')).first;
    final end = parseSubtitleTimestamp(endField);
    if (start == null || end == null) continue;
    final body = stripSubtitleMarkup(lines.skip(timeIndex + 1).join('\n'));
    if (body.isEmpty) continue;
    cues.add(
      ParsedSubtitleCue(
        index: cues.length + 1,
        start: start,
        end: end,
        text: body,
      ),
    );
  }
  return cues;
}

/// 打开视频时自动加载的字幕：同名匹配里的第一个；没有匹配就返回 null。
///
/// 刻意不做"瞎猜"（同目录任意字幕也硬挂上）：外语片目录里混着两个字幕时，
/// 猜错比不加载更让人困惑——由用户从 CC 菜单里选。
RemoteStorageEntry? defaultSubtitleFor(
  List<RemoteStorageEntry> candidates,
  String videoName,
) {
  for (final entry in candidates) {
    if (subtitleMatchesVideo(entry.name, videoName)) return entry;
  }
  return null;
}
