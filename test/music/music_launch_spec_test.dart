import 'dart:io';

import 'package:box/features/music/domain/music_launch_spec.dart';
import 'package:flutter_test/flutter_test.dart';

/// `openMusic` 的 payload 解析（插件 → 页面的唯一入口）。
///
/// 背景：这个动作以前只打开音乐页、**payload 被完全丢弃**，所以市场里的
/// 「专注白噪音 / 睡眠电台」只能写 toast 当占位。加了解析之后，一个市场条目
/// 就能声明「播哪一条、要不要自动播、要不要循环」。解析必须只放行 http(s)：
/// 市场条目是外部投稿，不能成为本地文件读取或脚本执行的入口。
void main() {
  group('MusicLaunchSpec.parse', () {
    test('空 / null / 空白 → 空 spec', () {
      for (final input in [null, '', '   ', '\n']) {
        final spec = MusicLaunchSpec.parse(input);
        expect(spec.isEmpty, isTrue, reason: '输入 $input 应为空');
        expect(spec.autoPlay, isFalse);
      }
    });

    test('纯字符串当成 URL，且默认自动播放', () {
      final spec = MusicLaunchSpec.parse(
        '  https://box.hpa888.top/updates/box/media/music/white-noise-5min.mp3  ',
      );
      expect(spec.url,
          'https://box.hpa888.top/updates/box/media/music/white-noise-5min.mp3');
      expect(spec.autoPlay, isTrue, reason: '作者只写一行 URL 时，点开就该播');
      expect(spec.loop, isFalse);
      expect(spec.title, isEmpty);
    });

    test('JSON：url + title + autoplay + loop 全字段', () {
      final spec = MusicLaunchSpec.parse(
        '{"url":"https://example.com/a.mp3","title":"专注白噪音",'
        '"autoplay":true,"loop":true}',
      );
      expect(spec.url, 'https://example.com/a.mp3');
      expect(spec.title, '专注白噪音');
      expect(spec.autoPlay, isTrue);
      expect(spec.loop, isTrue);
    });

    test('JSON 别名：link/href/src 与 name/label 都认', () {
      expect(MusicLaunchSpec.parse('{"link":"https://a.com/1.mp3"}').url,
          'https://a.com/1.mp3');
      expect(MusicLaunchSpec.parse('{"href":"https://a.com/2.mp3"}').url,
          'https://a.com/2.mp3');
      expect(MusicLaunchSpec.parse('{"src":"https://a.com/3.mp3"}').url,
          'https://a.com/3.mp3');
      expect(
        MusicLaunchSpec.parse('{"url":"https://a.com/4.mp3","name":"睡眠电台"}').title,
        '睡眠电台',
      );
      expect(
        MusicLaunchSpec.parse('{"url":"https://a.com/5.mp3","label":"电台"}').title,
        '电台',
      );
    });

    test('JSON 里 autoplay 写成字符串 "1"/"yes"/"true" 也算真', () {
      for (final v in ['true', '"1"', '"yes"', '1']) {
        final spec =
            MusicLaunchSpec.parse('{"url":"https://a.com/x.mp3","autoplay":$v}');
        expect(spec.autoPlay, isTrue, reason: 'autoplay=$v 应识别为真');
      }
      expect(
        MusicLaunchSpec.parse('{"url":"https://a.com/x.mp3","autoplay":false}')
            .autoPlay,
        isFalse,
      );
    });

    test('非 http(s) 一律拒绝（file/javascript/content 不能被打开）', () {
      for (final payload in [
        'file:///etc/passwd',
        'javascript:alert(1)',
        'content://media/external/audio/1',
        'ftp://example.com/a.mp3',
        '/data/local/tmp/a.mp3',
      ]) {
        final spec = MusicLaunchSpec.parse(payload);
        expect(spec.url, isEmpty, reason: '$payload 不该被当成可播地址');
        expect(spec.isEmpty, isTrue);
      }
      expect(
        MusicLaunchSpec.parse('{"url":"file:///etc/passwd","autoplay":true}').url,
        isEmpty,
      );
    });

    test('半截 URL（只有 scheme）也算无效', () {
      expect(MusicLaunchSpec.parse('https://').url, isEmpty);
      expect(MusicLaunchSpec.parse('http://').url, isEmpty);
    });

    test('坏 JSON 不抛异常，退化成空 spec', () {
      expect(MusicLaunchSpec.parse('{"url": ').isEmpty, isTrue);
      expect(MusicLaunchSpec.parse('[1,2,3]').isEmpty, isTrue);
      expect(MusicLaunchSpec.parse('null').isEmpty, isTrue);
    });

    test('toJson 往返一致（市场条目里 payload 就是这么写的）', () {
      const original = MusicLaunchSpec(
        url: 'https://a.com/a.mp3',
        title: '电台',
        autoPlay: true,
        loop: true,
      );
      final round = MusicLaunchSpec.parse(
        '{"url":"${original.url}","title":"${original.title}",'
        '"autoplay":${original.autoPlay},"loop":${original.loop}}',
      );
      expect(round.url, original.url);
      expect(round.title, original.title);
      expect(round.autoPlay, original.autoPlay);
      expect(round.loop, original.loop);
      expect(original.toJson()['url'], original.url);
    });
  });

  group('接线（源码契约）', () {
    test('openMusic 动作优先走带 payload 的构造器', () {
      final source = File(
        'lib/features/extensions/core/home_plugin_core.dart',
      ).readAsStringSync();
      expect(source, contains('lookupPayload('));
      expect(source, contains('registerPayload('));
      expect(
        source,
        contains("HomePluginRouteRegistry.lookupPayload('openMusic')"),
        reason: '音乐动作必须把 payload 交给页面，否则插件只能 toast 占位',
      );
    });

    test('音乐页接收 initialAudioUrl / autoPlay / loop 并透传给播放器', () {
      final source = File(
        'lib/features/music/presentation/music_placeholder_page.dart',
      ).readAsStringSync();
      expect(source, contains('this.initialAudioUrl'));
      expect(source, contains('this.autoPlay'));
      expect(source, contains('addPostFrameCallback'));
      expect(source, contains('looping: widget.loop'));

      final player = File(
        'lib/features/extensions/plugins/remote_storage/presentation/remote_storage_player_page.dart',
      ).readAsStringSync();
      expect(player, contains('this.looping = false'));
      expect(player, contains('looping: widget.looping'));
    });

    test('市场里两条音乐条目已从占位变成真播放', () {
      final source = File(
        'lib/features/extensions/market/domain/plugin_market_manifest.dart',
      ).readAsStringSync();
      for (final id in ['market_music_focus', 'market_music_sleep']) {
        final start = source.indexOf("id: '$id'");
        expect(start, greaterThan(0), reason: '$id 应仍存在');
        final block = source.substring(start, start + 700);
        expect(block, contains("actionCode: 'openMusic'"),
            reason: '$id 应指向真播放动作');
        expect(block, contains('"autoplay":true'),
            reason: '$id 应点开即播');
        expect(block, contains('"loop":true'),
            reason: '白噪音/电台必须单曲循环，否则 5 分钟就停');
        expect(block, isNot(contains('comingSoon: true')),
            reason: '$id 不该再是「即将上线」');
      }
    });
  });
}
