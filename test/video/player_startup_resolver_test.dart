import 'package:box/video/services/cloud_play_url_resolver.dart';
import 'package:box/video/services/player_startup_resolver.dart';
import 'package:box/video/services/stream_resolve_cache.dart';
import 'package:box/video/widgets/player/player_stream_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假云播页解析器：把「网页地址」换成一条媒体地址（只记调用次数）。
class _FakeCloud extends CloudPlayUrlResolver {
  _FakeCloud({this.throws_, this.keepsPage = false});

  final Object? throws_;

  /// true = 模拟「归一化之后还是网页」（原样返回）。
  final bool keepsPage;

  /// 归一化后应该拿到的媒体地址。
  static final Uri media = Uri.parse('https://cdn.example/media/abc.m3u8');

  int calls = 0;

  @override
  Future<Uri> resolve(
    Uri uri, {
    required Map<String, String> headers,
    MediaProbe? probe,
  }) async {
    calls++;
    if (throws_ != null) throw throws_!;
    return keepsPage ? uri : media;
  }
}

/// 假直连解析器：把地址原样当媒体地址返回（顺便记调用次数）。
class _FakeStream extends PlayerStreamResolver {
  _FakeStream();

  int calls = 0;

  @override
  Future<Uri> resolveDirectM3u8(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    calls++;
    return uri;
  }
}

const _headers = <String, String>{
  'User-Agent': 'ua',
  'Referer': 'https://source.example/',
};

void main() {
  group('PlayerStartupResolver', () {
    test('云播页地址走两段链，结果进缓存；第二次不再联网', () async {
      final cloud = _FakeCloud();
      final stream = _FakeStream();
      final r = PlayerStartupResolver(
        cloud: cloud,
        stream: stream,
        cache: StreamResolveCache(),
      );
      final raw = Uri.parse('https://v.example/play/abc');

      final first = await r.resolve(raw, headers: _headers);
      expect(first, _FakeCloud.media);
      expect(cloud.calls, 1);
      expect(stream.calls, 1);

      final second = await r.resolve(raw, headers: _headers);
      expect(second, first);
      expect(cloud.calls, 1, reason: '第二次应命中缓存，不再解析');
      expect(stream.calls, 1);
      expect(r.cache.hits, 1);
    });

    test('归一化后仍是网页地址 → 抛 UnresolvedCloudPageException（明确判死）', () async {
      final cloud = _FakeCloud(keepsPage: true); // 返回原地址 = 仍是网页
      final r = PlayerStartupResolver(
        cloud: cloud,
        stream: _FakeStream(),
        cache: StreamResolveCache(),
      );
      await expectLater(
        r.resolve(Uri.parse('https://v.example/share/xyz'), headers: _headers),
        throwsA(isA<UnresolvedCloudPageException>()),
      );
    });

    test('预热：先写缓存，起播时零等待；已热则不再重复请求', () async {
      final cloud = _FakeCloud();
      final stream = _FakeStream();
      final r = PlayerStartupResolver(
        cloud: cloud,
        stream: stream,
        cache: StreamResolveCache(),
      );
      final raw = Uri.parse('https://v.example/play/abc');

      r.prewarm(raw, headers: _headers);
      expect(r.isWarm(raw, _headers), isFalse, reason: '预热是异步的，此刻还没写完');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(r.isWarm(raw, _headers), isTrue);

      final callsAfterPrewarm = cloud.calls;
      await r.resolve(raw, headers: _headers);
      expect(cloud.calls, callsAfterPrewarm, reason: '起播应直接吃预热结果');

      r.prewarm(raw, headers: _headers);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(cloud.calls, callsAfterPrewarm, reason: '已热就不该再发请求');
    });

    test('不同 Referer 分开缓存（源按 Referer 签名时不会互相污染）', () async {
      final cloud = _FakeCloud();
      final r = PlayerStartupResolver(
        cloud: cloud,
        stream: _FakeStream(),
        cache: StreamResolveCache(),
      );
      final raw = Uri.parse('https://v.example/play/abc');

      await r.resolve(raw, headers: _headers);
      await r.resolve(raw, headers: const {
        'User-Agent': 'ua',
        'Referer': 'https://other.example/',
      });
      expect(cloud.calls, 2);
      expect(r.cache.size, 2);
    });

    test('invalidate 后重新解析（失败重试要拿到新地址）', () async {
      final cloud = _FakeCloud();
      final r = PlayerStartupResolver(
        cloud: cloud,
        stream: _FakeStream(),
        cache: StreamResolveCache(),
      );
      final raw = Uri.parse('https://v.example/play/abc');

      await r.resolve(raw, headers: _headers);
      r.invalidate(raw, _headers);
      await r.resolve(raw, headers: _headers);
      expect(cloud.calls, 2);
    });

    test('预热失败不影响调用方（不抛错）', () async {
      final cloud = _FakeCloud(throws_: const UnresolvedCloudPageException());
      final r = PlayerStartupResolver(
        cloud: cloud,
        stream: _FakeStream(),
        cache: StreamResolveCache(),
      );
      r.prewarm(Uri.parse('https://v.example/play/abc'), headers: _headers);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(r.isWarm(Uri.parse('https://v.example/play/abc'), _headers), isFalse);
    });
  });
}
