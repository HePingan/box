import 'package:box/features/extensions/plugins/github_accel/github_accel_probe.dart';
import 'package:flutter_test/flutter_test.dart';

/// UI 层的选线行为：验证「测速后自动切到最快线路」这个决策逻辑本身。
///
/// 面板 widget 依赖 Dio 真实网络，这里不整体挂载；改为验证选线算法在
/// 实测数据形态下的输出，与面板里 `_probeMirrors` 用的是同一套 rank 逻辑。
void main() {
  test('实测数据形态下选出 gh-proxy（中位 1133ms）而非 ghfast（2084ms）', () async {
    // 来自真实 curl 采样：每镜像 5 轮 64KB。
    final real = <String, List<int>>{
      'https://gh-proxy.com': [1133, 259, 99000, 347, 1304],
      'https://ghfast.top': [1925, 2733, 2944, 2084, 1602],
      'https://ghproxy.net': [], // 证书过期，全失败
      'https://hk.gh-proxy.com': [2232, 1931, 3428, 2212, 1776],
    };
    final idx = <String, int>{};

    final ranked = await MirrorProbe(
      rounds: 5,
      probe: (mirror, url) async {
        final list = real[mirror]!;
        if (list.isEmpty) {
          return MirrorSample(
            mirror: mirror,
            ok: false,
            error: '证书已过期',
          );
        }
        final i = idx[mirror] = (idx[mirror] ?? 0);
        idx[mirror] = i + 1;
        return MirrorSample(
          mirror: mirror,
          ok: true,
          elapsed: Duration(milliseconds: list[i % list.length]),
        );
      },
    ).rank('https://github.com/o/r/releases/download/1/a.apk',
        mirrors: real.keys.toList());

    expect(ranked.first.mirror, 'https://gh-proxy.com');
    expect(ranked.first.medianMs, 1133);

    // 证书过期那条必须垫底且不可用，UI 会置灰它。
    final dead = ranked.firstWhere((r) => r.mirror.contains('ghproxy.net'));
    expect(dead.usable, isFalse);
    expect(ranked.last.mirror, contains('ghproxy.net'));
    expect(dead.summary, contains('证书'));
  });

  test('可用镜像的 summary 给出耗时，部分失败时标注成功次数', () {
    const full = MirrorRanking(
      mirror: 'https://gh-proxy.com',
      usable: true,
      medianMs: 900,
      okCount: 3,
      total: 3,
    );
    expect(full.summary, '900ms');
    expect(full.label, 'gh-proxy.com');

    const partial = MirrorRanking(
      mirror: 'https://x.com',
      usable: true,
      medianMs: 1200,
      okCount: 2,
      total: 3,
    );
    expect(partial.summary, contains('2/3'));
  });
}
