import 'package:box/video_module.dart';
import 'package:box/video/services/source_capability.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ① 的**接线**护栏：这套源可见性 API 以前全仓零调用，坏源每次搜索都陪跑。
/// 这里守两件事：
/// 1. 接口层坏的源（1002 / 返回网页 / 404）被探测判定后 → 真的进了「自动隐藏」；
/// 2. 网络类失败（超时 / 403）→ 不被隐藏（换条路可能还能用）。
/// 两条都从 `visibleSourcesOf` 这个**搜索实际使用的入口**读结果。
VideoSource _source({required String id, required String url}) {
  return VideoSource(
    id: id,
    name: id,
    url: url,
    detailUrl: url,
    isEnabled: true,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    VideoModule.resetForTest();
  });

  test('接口层坏的源被自动隐藏，下次聚合搜索直接跳过', () async {
    final bad = _source(id: '豆瓣', url: 'https://dbzy.example.test/api');
    final html = _source(id: '卧龙', url: 'https://wolong.example.test/api');
    final gone = _source(id: '艾旦', url: 'https://lovedan.example.test/api');
    final blocked = _source(id: '无尽', url: 'https://wujin.example.test/api');

    final probe = SourceSearchCapabilityProbe(
      probeOverride: (baseUrl, keyword) async {
        if (baseUrl.contains('dbzy')) {
          return const SourceProbeResponse(
            statusCode: 200,
            body: '{"code":1002,"msg":"Current API forbids keyword search"}',
          );
        }
        if (baseUrl.contains('wolong')) {
          return const SourceProbeResponse(
            statusCode: 200,
            body: '<html>天涯影视资源</html>',
          );
        }
        if (baseUrl.contains('lovedan')) {
          return const SourceProbeResponse(statusCode: 404, body: 'not found');
        }
        // 无尽：403（WAF 拦机房 IP，不算接口层坏）。
        return const SourceProbeResponse(statusCode: 403, body: 'Forbidden');
      },
    );

    final hidden = await VideoModule.autoHideStructurallyBrokenSources([
      bad,
      html,
      gone,
      blocked,
    ], probe: probe);

    expect(hidden.map((s) => s.id).toSet(), {'豆瓣', '卧龙', '艾旦'});

    // 搜索实际用的入口：坏的不在了，被 403 挡住的还在。
    final visible = VideoModule.visibleSourcesOf([bad, html, gone, blocked]);
    expect(visible.map((s) => s.id).toSet(), {'无尽'});

    // 判定理由要留在记录里，便于源管理页解释「为什么它不见了」。
    final record = VideoModule.getVisibilityRecord(bad);
    expect(record, isNotNull);
    expect(record.autoHidden, isTrue);
    expect(record.lastReason, contains('接口层不可用'));
  });

  test('全部源都判「接口层坏」时不隐藏任何源（更像出口/代理问题）', () async {
    final sources = [
      _source(id: 'A', url: 'https://a.example.test/api'),
      _source(id: 'B', url: 'https://b.example.test/api'),
      _source(id: 'C', url: 'https://c.example.test/api'),
    ];
    // 代理挂掉时典型表现：每个源都返回同一个 HTML 错误页。
    final probe = SourceSearchCapabilityProbe(
      probeOverride: (baseUrl, keyword) async => const SourceProbeResponse(
        statusCode: 200,
        body: '<html><title>502 Bad Gateway</title></html>',
      ),
    );

    final hidden = await VideoModule.autoHideStructurallyBrokenSources(
      sources,
      probe: probe,
    );

    expect(hidden, isEmpty, reason: '一次出口抖动不该把整个源列表抹掉');
    expect(VideoModule.visibleSourcesOf(sources).length, 3);
  });

  test('探测整体失败时不动任何源（探测不该反噬搜索）', () async {
    final source = _source(id: '正常源', url: 'https://ok.example.test/api');
    final probe = SourceSearchCapabilityProbe(
      probeOverride: (baseUrl, keyword) async =>
          throw StateError('network down'),
    );

    final hidden = await VideoModule.autoHideStructurallyBrokenSources([
      source,
    ], probe: probe);

    expect(hidden, isEmpty);
    expect(VideoModule.visibleSourcesOf([source]).map((s) => s.id), ['正常源']);
  });

  test('搜索成功后失败计数清零，源重回可见', () async {
    final source = _source(id: '抖动源', url: 'https://flaky.example.test/api');

    await VideoModule.markSourceFailure(
      source,
      reason: '聚合搜索失败',
      autoHide: false,
    );
    await VideoModule.markSourceSuccess(source);

    final record = VideoModule.getVisibilityRecord(source);
    expect(record.failCount, 0);
    expect(record.autoHidden, isFalse);
    expect(VideoModule.visibleSourcesOf([source]).length, 1);
  });
}
