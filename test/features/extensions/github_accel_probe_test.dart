import 'package:box/features/extensions/plugins/github_accel/github_accel_link.dart';
import 'package:box/features/extensions/plugins/github_accel/github_accel_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 探测目标：真实存在的稳定链接（测试里不联网，靠注入的 probe 函数模拟）。
  const target =
      'https://github.com/rikkahub/rikkahub/releases/latest/download/a.apk';

  group('测速选线', () {
    test('挑中位耗时最小的镜像，而不是第一个返回的', () async {
      // 实测数据形态：gh-proxy 抖动大但中位最好，hk 最慢。
      final samples = <String, List<int>>{
        'https://gh-proxy.com': [1133, 259, 9000, 347, 1304],
        'https://ghfast.top': [1925, 2733, 2944, 2084, 1602],
        'https://hk.gh-proxy.com': [2232, 1931, 3428, 2212, 1776],
      };
      final calls = <String, int>{};

      final ranked = await MirrorProbe(
        rounds: 5,
        probe: (mirror, url) async {
          calls[mirror] = (calls[mirror] ?? 0) + 1;
          final list = samples[mirror]!;
          return MirrorSample(
            mirror: mirror,
            ok: true,
            elapsed: Duration(
              milliseconds: list[(calls[mirror]! - 1) % list.length],
            ),
          );
        },
      ).rank(target, mirrors: samples.keys.toList());

      expect(ranked.first.mirror, 'https://gh-proxy.com');
      expect(ranked.last.mirror, 'https://hk.gh-proxy.com');
      // 中位数而非均值：9000ms 那一次不该把 gh-proxy 拖到最后。
      expect(ranked.first.medianMs, 1133);
    });

    test('单次抽风不改变结论（用中位数抗抖动）', () async {
      final ranked = await MirrorProbe(
        rounds: 3,
        probe: (mirror, url) async {
          // A 稳定 800ms；B 稳定 300ms 但第一次超时。
          if (mirror == 'A') {
            return const MirrorSample(
              mirror: 'A',
              ok: true,
              elapsed: Duration(milliseconds: 800),
            );
          }
          return const MirrorSample(
            mirror: 'B',
            ok: true,
            elapsed: Duration(milliseconds: 300),
          );
        },
      ).rank(target, mirrors: const ['A', 'B']);

      expect(ranked.first.mirror, 'B');
    });

    test('全部失败的镜像排在最后，且标记不可用', () async {
      final ranked = await MirrorProbe(
        rounds: 2,
        probe: (mirror, url) async {
          if (mirror == 'dead') {
            return const MirrorSample(mirror: 'dead', ok: false, error: '证书过期');
          }
          return const MirrorSample(
            mirror: 'alive',
            ok: true,
            elapsed: Duration(milliseconds: 500),
          );
        },
      ).rank(target, mirrors: const ['dead', 'alive']);

      expect(ranked.first.mirror, 'alive');
      expect(ranked.last.mirror, 'dead');
      expect(ranked.last.usable, isFalse);
      expect(ranked.last.error, contains('证书'));
    });

    test('部分成功也可用，按成功样本的中位数排', () async {
      var n = 0;
      final ranked = await MirrorProbe(
        rounds: 3,
        probe: (mirror, url) async {
          n++;
          // 每 3 次里失败 1 次，仍应视为可用。
          if (n % 3 == 0) {
            return MirrorSample(mirror: mirror, ok: false, error: '超时');
          }
          return MirrorSample(
            mirror: mirror,
            ok: true,
            elapsed: const Duration(milliseconds: 600),
          );
        },
      ).rank(target, mirrors: const ['only']);

      expect(ranked.single.usable, isTrue);
      expect(ranked.single.medianMs, 600);
    });

    test('没有任何镜像可用时返回空的可用列表，但不抛异常', () async {
      final ranked = await MirrorProbe(
        rounds: 1,
        probe: (mirror, url) async =>
            MirrorSample(mirror: mirror, ok: false, error: '网络不可达'),
      ).rank(target, mirrors: const ['x', 'y']);

      expect(ranked.every((r) => !r.usable), isTrue);
      expect(ranked.length, 2);
    });

    test('探测并发进行，不是串行等待（10 个镜像不该等 10 倍时间）', () async {
      var inFlight = 0;
      var maxInFlight = 0;

      await MirrorProbe(
        rounds: 1,
        probe: (mirror, url) async {
          inFlight++;
          maxInFlight = maxInFlight > inFlight ? maxInFlight : inFlight;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          inFlight--;
          return MirrorSample(
            mirror: mirror,
            ok: true,
            elapsed: const Duration(milliseconds: 20),
          );
        },
      ).rank(target, mirrors: const ['a', 'b', 'c', 'd']);

      expect(maxInFlight, greaterThan(1), reason: '多个镜像应并发探测');
    });

    test('默认探测内置镜像清单', () async {
      final seen = <String>{};
      await MirrorProbe(
        rounds: 1,
        probe: (mirror, url) async {
          seen.add(mirror);
          return MirrorSample(
            mirror: mirror,
            ok: true,
            elapsed: const Duration(milliseconds: 100),
          );
        },
      ).rank(target);

      for (final m in GithubAccelLink.mirrors) {
        expect(seen, contains(m.url));
      }
    });
  });

  group('探测用的 URL', () {
    test('只取文件头，不整包下载', () {
      final probe = MirrorProbe(probe: (_, _) async => throw 'unused');
      expect(probe.rangeHeader, 'bytes=0-65535');
    });
  });
}
