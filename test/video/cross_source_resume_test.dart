import 'package:box/video/services/cross_source_resume.dart';
import 'package:box/video/services/source_match.dart';
import 'package:box/video_module.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 换源找片：原片源没了之后，按片名在**可用**片源里找同一部片。
///
/// 三条硬规矩（都有用例）：
///   1. 只搜可见源 —— ① 自动隐藏的坏源不该再花用户流量；
///   2. 命中必须是归一化片名**精确相等**，模糊命中等于放错片；
///   3. 搜到 0 结果**不算源坏**（老片本来就没有），只有请求失败才记账且不隐藏。
VideoSource src(String id, String name) => VideoSource(
  id: id,
  name: name,
  url: 'https://$id/api.php/provide/vod',
  detailUrl: '',
);

VodItem vod(int id, String name) =>
    VodItem(vodId: id, typeId: 0, vodName: name);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VideoModule.resetForTest();
  });

  test('命中的是「归一化片名精确相等」的那家，且返回它自己的 vodId', () async {
    final sources = [src('a.com', '🎬甲源'), src('b.com', '🎬乙源')];
    const finder = CrossSourceMovieFinder(concurrency: 2);

    final report = await finder.find(
      sources: sources,
      vodName: '欢迎来龙餐馆',
      search: (source, keyword) async {
        if (source.id == 'b.com') {
          return [vod(777, '欢迎来龙餐馆（HD）'), vod(778, '欢迎来龙餐馆')];
        }
        // 甲源只有别的片 —— 不许模糊命中。
        return [vod(1, '欢迎来龙餐馆2：重返龙村')];
      },
    );

    expect(report.hit, isNotNull);
    expect(report.hit!.source.id, 'b.com');
    expect(report.hit!.vodId, 778, reason: '要精确那一条，不是「名字里含它」的第一条');
  });

  test('只搜可见源：被 ① 自动隐藏的坏源一次请求都不发', () async {
    final sources = [src('bad.com', '🎬坏源'), src('good.com', '🎬好源')];
    await VideoModule.setSourceAutoHidden(
      sources.first,
      true,
      reason: '接口禁止关键词搜索',
    );

    final searchedIds = <String>[];
    final report = await const CrossSourceMovieFinder(concurrency: 2).find(
      sources: sources,
      vodName: '欢迎来龙餐馆',
      search: (source, keyword) async {
        searchedIds.add(source.id);
        return [vod(9, '欢迎来龙餐馆')];
      },
    );

    expect(searchedIds, ['good.com']);
    expect(report.hit!.source.id, 'good.com');
  });

  test('搜到 0 结果不算源坏：不记账、不隐藏', () async {
    final sources = [src('a.com', '🎬甲源'), src('b.com', '🎬乙源')];
    final report = await const CrossSourceMovieFinder(concurrency: 2).find(
      sources: sources,
      vodName: '一部老片',
      search: (source, keyword) async => const <VodItem>[],
    );

    expect(report.hit, isNull);
    expect(report.searched, 2);
    expect(report.failedSources, isEmpty);
    for (final source in sources) {
      final record = VideoModule.getVisibilityRecord(source);
      expect(record.failCount, 0, reason: '「这个源没有这部片」不是源故障');
      expect(record.isHidden, isFalse);
    }
  });

  test('请求失败的源：只记一笔（failCount+1），绝不自动隐藏', () async {
    final sources = [src('dead.com', '🎬挂掉的源'), src('ok.com', '🎬好源')];
    final report = await const CrossSourceMovieFinder(concurrency: 2).find(
      sources: sources,
      vodName: '欢迎来龙餐馆',
      search: (source, keyword) async {
        if (source.id == 'dead.com') throw StateError('boom');
        return [vod(9, '欢迎来龙餐馆')];
      },
    );

    expect(report.hit!.source.id, 'ok.com');
    expect(report.failedSources, ['🎬挂掉的源']);
    final record = VideoModule.getVisibilityRecord(sources.first);
    expect(record.failCount, 1);
    expect(
      record.autoHidden,
      isFalse,
      reason: '换源失败是网络层面的事（也可能是我们出口的问题），一次失败不许拉黑',
    );
  });

  test('并发窗口有上限（默认 4），且先命中就提前收工', () async {
    final sources = List.generate(8, (i) => src('s$i.com', '🎬源$i'));
    var live = 0;
    var peak = 0;
    var searched = 0;

    final report = await const CrossSourceMovieFinder().find(
      sources: sources,
      vodName: '欢迎来龙餐馆',
      search: (source, keyword) async {
        searched++;
        live++;
        if (live > peak) peak = live;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        live--;
        // 第一个源就有 —— 后面的不该被叫醒。
        return [vod(9, '欢迎来龙餐馆')];
      },
    );

    expect(report.hit, isNotNull);
    expect(peak, lessThanOrEqualTo(4), reason: '并发窗口压不住会打爆源站/代理');
    expect(searched, lessThanOrEqualTo(4), reason: '命中后不必再搜剩下的源');
  });

  test('总预算到点就返回（不无限等）', () async {
    final sources = List.generate(6, (i) => src('s$i.com', '🎬源$i'));
    final report =
        await const CrossSourceMovieFinder(
          budget: Duration(milliseconds: 50),
        ).find(
          sources: sources,
          vodName: '欢迎来龙餐馆',
          search: (source, keyword) async {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            return const <VodItem>[];
          },
        );

    expect(report.hit, isNull);
    expect(report.searched, lessThan(sources.length), reason: '预算用完就不再往下叫源了');
  });

  test('归一片名/剧集名：装饰符与数字前导零都不影响判断', () {
    expect(normalizeSourceName('🎬量子资源'), '量子资源');
    expect(normalizeEpisodeName('第03集'), '第3集');
    expect(normalizeEpisodeName('【HD中字】'), 'hd中字');
    expect(
      normalizeEpisodeName('第03集'),
      normalizeEpisodeName('第3集'),
      reason: '不同采集站写法不同，同一集必须认成同一集',
    );
    expect(normalizeEpisodeName(''), '');
  });
}
