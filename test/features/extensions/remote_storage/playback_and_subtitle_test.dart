// 279 B3 纯逻辑单测：续播判定与字幕解析（都不依赖平台通道）。

import 'package:box/features/extensions/plugins/remote_storage/domain/playback_progress.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/subtitle_support.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('续播判定（B3）', () {
    test('太靠前不记：15 秒以内当没看过', () {
      expect(
        shouldResumePlayback(const Duration(seconds: 14), const Duration(minutes: 30)),
        isFalse,
      );
      expect(
        shouldResumePlayback(const Duration(seconds: 15), const Duration(minutes: 30)),
        isTrue,
      );
    });

    test('接近片尾不当续播起点（避免"续播到片尾再回到列表"）', () {
      const duration = Duration(minutes: 100);
      expect(
        shouldResumePlayback(const Duration(minutes: 94), duration),
        isTrue,
      );
      // 95% 起算看完：100 分钟片子的 95 分钟后不再续播。
      expect(
        shouldResumePlayback(const Duration(minutes: 95), duration),
        isFalse,
      );
    });

    test('时长未知（直播/拿不到总长）时只按位置判断', () {
      expect(
        shouldResumePlayback(const Duration(seconds: 30), Duration.zero),
        isTrue,
      );
      expect(
        shouldResumePlayback(const Duration(seconds: 5), Duration.zero),
        isFalse,
      );
    });

    test('看完判定与续播判定互斥', () {
      const duration = Duration(minutes: 10);
      const position = Duration(minutes: 9, seconds: 40);
      expect(isPlaybackFinished(position, duration), isTrue);
      expect(shouldResumePlayback(position, duration), isFalse);
    });

    test('进度文案：小时位只在需要时出现', () {
      expect(formatPlaybackPosition(const Duration(seconds: 0)), '0:00');
      expect(formatPlaybackPosition(const Duration(minutes: 12, seconds: 34)), '12:34');
      expect(
        formatPlaybackPosition(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });

    test('存储键带账户前缀（同路径不同账户不互相覆盖）', () {
      expect(
        playbackProgressKey('acc1', 'a/movie.mp4'),
        isNot(playbackProgressKey('acc2', 'a/movie.mp4')),
      );
      expect(playbackProgressKey('acc1', 'a/movie.mp4'), contains('a/movie.mp4'));
    });
  });

  group('字幕候选识别（B3）', () {
    RemoteStorageEntry file(String name) =>
        RemoteStorageEntry(name: name, path: name, isDirectory: false);

    test('只认 .srt / .vtt，大小写不敏感', () {
      expect(isSubtitleFileName('a.SRT'), isTrue);
      expect(isSubtitleFileName('a.vtt'), isTrue);
      expect(isSubtitleFileName('a.ass'), isFalse);
      expect(isSubtitleFileName('a.txt'), isFalse);
    });

    test('同名匹配：允许语言后缀，不允许"以视频名开头但不同名"', () {
      expect(subtitleMatchesVideo('movie.srt', 'movie.mp4'), isTrue);
      expect(subtitleMatchesVideo('movie.zh.srt', 'movie.mp4'), isTrue);
      expect(subtitleMatchesVideo('Movie.zh-CN.vtt', 'movie.mp4'), isTrue);
      // 'movie2.srt' 不该配到 'movie.mp4'
      expect(subtitleMatchesVideo('movie2.srt', 'movie.mp4'), isFalse);
    });

    test('候选列表：同名在前，其余保持原有顺序', () {
      final entries = [
        file('other.srt'),
        file('movie.mp4'),
        file('movie.vtt'),
        file('movie.zh.srt'),
        file('movie.ass'),
      ];
      final candidates = subtitleCandidates(entries, 'movie.mp4');
      expect(
        candidates.map((e) => e.name).toList(),
        ['movie.vtt', 'movie.zh.srt', 'other.srt'],
      );
    });

    test('默认字幕：只认同名，不瞎猜别的字幕', () {
      final entries = [file('other.srt'), file('movie.zh.srt')];
      expect(
        defaultSubtitleFor(subtitleCandidates(entries, 'movie.mp4'), 'movie.mp4')?.name,
        'movie.zh.srt',
      );
      expect(
        defaultSubtitleFor(subtitleCandidates([file('other.srt')], 'movie.mp4'), 'movie.mp4'),
        isNull,
      );
    });
  });

  group('字幕解析（B3：SRT / VTT）', () {
    test('SRT：序号行 + 逗号毫秒 + 多行正文', () {
      const srt = '1\n'
          '00:00:01,000 --> 00:00:04,500\n'
          '你好\n'
          '世界\n'
          '\n'
          '2\n'
          '00:01:02,250 --> 00:01:03,000\n'
          'second\n';
      final cues = parseSubtitleText(srt);
      expect(cues, hasLength(2));
      expect(cues[0].start, const Duration(seconds: 1));
      expect(cues[0].end, const Duration(seconds: 4, milliseconds: 500));
      expect(cues[0].text, '你好\n世界');
      expect(cues[0].index, 1);
      expect(cues[1].start, const Duration(minutes: 1, seconds: 2, milliseconds: 250));
      expect(cues[1].index, 2);
    });

    test('VTT：跳过 WEBVTT 头与 NOTE，支持省略小时与 cue 设置', () {
      const vtt = 'WEBVTT\n'
          '\n'
          'NOTE 这是注释\n'
          '不该被解析\n'
          '\n'
          '00:01.000 --> 00:02.000 align:start position:10%\n'
          'hi\n'
          '\n'
          '00:00:03.500 --> 00:00:04.000\n'
          'bye\n';
      final cues = parseSubtitleText(vtt, webVtt: true);
      expect(cues, hasLength(2));
      expect(cues[0].start, const Duration(seconds: 1));
      expect(cues[0].end, const Duration(seconds: 2));
      expect(cues[0].text, 'hi');
      expect(cues[1].start, const Duration(seconds: 3, milliseconds: 500));
    });

    test('排版标记被清掉：行内标签、{\\an8}、实体', () {
      const srt = '1\n'
          '00:00:01,000 --> 00:00:02,000\n'
          '<i>斜体</i>{\\an8}&amp;符号\n';
      final cues = parseSubtitleText(srt);
      expect(cues.single.text, '斜体&符号');
    });

    test('坏块被跳过而不是污染时间轴：时间戳解析失败 / 空正文', () {
      const srt = '1\n'
          '00:00:01,000 --> 00:00:02,000\n'
          'good\n'
          '\n'
          '2\n'
          'bad --> worse\n'
          'should be skipped\n'
          '\n'
          '3\n'
          '00:00:05,000 --> 00:00:06,000\n'
          '\n'
          '4\n'
          '00:00:07,000 --> 00:00:08,000\n'
          'again\n';
      final cues = parseSubtitleText(srt);
      expect(cues.map((c) => c.text).toList(), ['good', 'again']);
      // 序号按"有效条目"重排，不是文件里的原始序号（避免跳号）。
      expect(cues.map((c) => c.index).toList(), [1, 2]);
    });

    test('时间戳解析：非法输入返回 null，不当成 0', () {
      expect(parseSubtitleTimestamp('00:00:01,000'), const Duration(seconds: 1));
      expect(parseSubtitleTimestamp('01:02:03.004'), const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 4));
      expect(parseSubtitleTimestamp('02:03'), const Duration(minutes: 2, seconds: 3));
      expect(parseSubtitleTimestamp('not a time'), isNull);
      expect(parseSubtitleTimestamp(''), isNull);
    });

    test('空文件 / 全是头信息 → 空列表（播放页据此提示可能是编码问题）', () {
      expect(parseSubtitleText(''), isEmpty);
      expect(parseSubtitleText('WEBVTT\n\n'), isEmpty);
    });

    test('CRLF 与 BOM 不影响解析', () {
      const srt = '\uFEFF1\r\n00:00:01,000 --> 00:00:02,000\r\nwin\r\n';
      final cues = parseSubtitleText(srt);
      expect(cues.single.text, 'win');
    });

    test('.vtt 走 VTT 判定的判定函数', () {
      expect(isWebVttFileName('a.VTT'), isTrue);
      expect(isWebVttFileName('a.srt'), isFalse);
    });
  });
}
