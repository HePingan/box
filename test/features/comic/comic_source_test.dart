// 漫画源：解析 / 规则 / 自检流程 的用例（纯 Dart + 假取数，不联网、不起 WebView）。
//
// 说明：**引擎本身（页面里那段 JS）没法在 Dart 单测里执行** —— Dart 没有 JS 运行环境。
// 它的正确性由真机上的「漫画源自检」当场证明（界面上会逐项给结论）。这里能锁的是：
// 规则解析、生成出来的 JS 脚本形状、以及自检流程的判定与失败说明。
import 'package:box/features/comic/domain/comic_source.dart';
import 'package:box/features/comic/domain/comic_source_diagnostics.dart';
import 'package:box/features/comic/domain/comic_source_engine.dart';
import 'package:box/features/comic/domain/sources/seed_comic_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假取数：按"规则文本 → 值"和"CSS → 命中数"作答，并记录打开过的地址。
class _FakeTarget implements ComicSourceTarget {
  _FakeTarget({
    this.counts = const {},
    this.values = const {},
    this.jsText = const {},
    this.title = '🐴 某漫画页',
    List<String>? opened,
    this.hrefs = const {},
    this.failHosts = const {},
    this.failFirstNAttempts = 0,
  }) : opened = opened ?? [];

  final Map<String, int> counts;
  final Map<String, List<String>> values;
  final Map<String, String> jsText;
  final String title;
  final List<String> opened;
  final Map<String, String> hrefs;

  /// 按**主机**配置的永久失败（模拟某一跳被重置/502）。
  final Map<String, ComicLoadFailure> failHosts;

  /// 同一地址前 N 次尝试失败、之后成功（模拟"重试一次就好了"）。
  final int failFirstNAttempts;

  final Map<String, int> hits = {};
  ComicLoadFailure? _last;

  String currentUrlValue = '';

  @override
  ComicLoadFailure? get lastLoadError => _last;

  @override
  Future<void> open(String url, {Map<String, String>? headers}) async {
    currentUrlValue = url;
    opened.add(url);
    final n = (hits[url] ?? 0) + 1;
    hits[url] = n;
    if (n <= failFirstNAttempts) {
      _last = const ComicLoadFailure(
        code: -6,
        description: 'net::ERR_CONNECTION_RESET',
      );
      return;
    }
    final host = Uri.tryParse(url)?.host ?? '';
    _last = failHosts[host];
  }

  @override
  Future<String> currentUrl() async => currentUrlValue;

  @override
  Future<String> pageTitle() async => title;

  @override
  Future<int> countOf(String css) async => counts[css] ?? 0;

  @override
  Future<String?> attrOf(String css, String attr) async => hrefs[css];

  @override
  Future<String> evalRaw(String script) async {
    // 取值脚本：从 JS 里把规则文本抠出来（引擎在真机里跑，这里只做映射）。
    final m = RegExp(r'legadoExtract\("((?:[^"\\]|\\.)*)"\)').firstMatch(script);
    if (m != null) {
      final rule = m.group(1)!.replaceAll(r'\"', '"');
      // 计数脚本（`…@href` 这种是页面里直取，这里按 values 提供）
      final list = values[rule];
      if (list == null) return '{"values":[]}';
      return '{"values":[${list.map((v) => '"${v.replaceAll('"', r'\"')}"').join(',')}]}';
    }
    // JS 段：返回 scripted 文本
    for (final entry in jsText.entries) {
      if (script.contains(entry.key)) return '{"text":${_json(entry.value)}}';
    }
    return '{"text":""}';
  }

  static String _json(String s) =>
      '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n')}"';
}

void main() {
  group('书源解析', () {
    test('内置书源可解析：名字、域名、搜索模板都在', () {
      final source = ComicSource.tryParse(kSeedComicSourceJson);
      expect(source, isNotNull, reason: '内置书源必须解析得出来');
      expect(source!.name, contains('包子漫画'));
      expect(source.baseUrl, startsWith('https://'));
      expect(source.searchUrl, contains('{{key}}'));
      expect(source.searchRules['bookList'], isNotEmpty);
      expect(source.contentRules['content'], contains('getElements'));
    });

    test('搜索地址会做 URL 编码（中文关键字必须编码）', () {
      final source = ComicSource.tryParse(kSeedComicSourceJson)!;
      final url = source.searchUrlFor('海贼 王');
      expect(url, isNotNull);
      expect(url, contains('%E6%B5%B7%E8%B4%BC'), reason: '中文要编码');
      expect(url, isNot(contains('{{key}}')));
    });

    test('相对地址补成绝对地址；绝对地址原样返回', () {
      final source = ComicSource.tryParse(kSeedComicSourceJson)!;
      expect(source.absolute('/comic/abc'), startsWith('https://'));
      expect(source.absolute('/comic/abc'), endsWith('/comic/abc'));
      expect(
        source.absolute('https://x.example/a'),
        'https://x.example/a',
      );
    });

    test('缺名字或域名的书源判为不认识（不带着半残的源往下跑）', () {
      expect(ComicSource.tryParse(''), isNull);
      expect(ComicSource.tryParse('[]'), isNull);
      expect(ComicSource.tryParse('{"bookSourceName":"x"}'), isNull);
      expect(
        ComicSource.tryParse('{"bookSourceUrl":"https://a.b"}'),
        isNull,
      );
    });

    test('内置书源的每条规则都认得出来（这是"这份源在 App 里可用"的锁）', () {
      final source = ComicSource.tryParse(kSeedComicSourceJson)!;
      expect(
        source.unknownRules(),
        isEmpty,
        reason: '有认不出来的规则段就等于这份源用不了，必须当场暴露',
      );
    });
  });

  group('规则解析', () {
    test('多个类名属于同一元素，取值步取文本', () {
      final p = parseComicRule('class.comics-card__title text-truncate@text', valueRule: true);
      expect(p.ok, isTrue);
      expect(p.steps, hasLength(2));
      final sel = p.steps.first as ComicSelectorStep;
      expect(sel.css, '.comics-card__title.text-truncate');
      expect((p.steps.last as ComicValueStep).isText, isTrue);
    });

    test('tag + 索引 + 属性：tag.amp-img.0@src', () {
      final p = parseComicRule('tag.amp-img.0@src', valueRule: true);
      expect(p.ok, isTrue);
      final sel = p.steps.first as ComicSelectorStep;
      expect(sel.css, 'amp-img');
      expect(sel.index, 0);
      expect((p.steps.last as ComicValueStep).kind, 'src');
    });

    test('裸标签名也认（这份源的 class.comic-contain@amp-img）', () {
      final p = parseComicRule('class.comic-contain@amp-img');
      expect(p.ok, isTrue, reason: '裸 amp-img 要当作标签选择器');
      expect(cssFromComicRule('class.comic-contain@amp-img'), '.comic-contain amp-img');
    });

    test('索引写在类名后面：class.comics-chapters__item.0@text', () {
      final p = parseComicRule('class.comics-chapters__item.0@text', valueRule: true);
      expect(p.ok, isTrue);
      expect((p.steps.first as ComicSelectorStep).index, 0);
    });

    test('不认识的段要报出来（不静默返回空）', () {
      final p = parseComicRule('class.a@@[bad]', valueRule: true);
      expect(p.ok, isFalse);
      expect(p.unknown, isNotNull);
    });

    test('JS 规则单独识别，不会被当选择器硬解', () {
      const rule = '<js>java.t2s(result)</js>';
      expect(isComicJsRule(rule), isTrue);
      expect(comicJsBody(rule), 'java.t2s(result)');
      expect(parseComicRule(rule).unknown, contains('JS'));
    });
  });

  group('生成的 JS 脚本', () {
    test('取值脚本带上引擎与规则，且规则字符串被正确转义', () {
      final script = buildComicRuleScript('class.a"b@text');
      expect(script, contains('window.legadoExtract'));
      expect(script, contains(r'class.a\"b@text'), reason: '引号必须转义');
      expect(script, startsWith('javascript:'));
    });

    test('计数脚本只做 querySelectorAll 计数', () {
      final script = buildComicCountScript('.a b');
      expect(script, contains('querySelectorAll'));
      expect(script, contains('.a b'));
    });

    test('取值步必须先判、再判选择器（顺序反了会把 href 当类选择器 .href 找）', () {
      // 真机上就是这么踩的：bookUrl 规则 `…@tag.a@href` 报"没有取值步"。
      // 顺序是这段 JS 的正确性核心，所以锁在源码里，不只是锁行为。
      final valueCheck = kComicSourceEngineJs.indexOf('VALUE_HOLDERS.indexOf(step)');
      final selectorCheck = kComicSourceEngineJs.indexOf('var built = buildCss(toks);');
      expect(valueCheck, greaterThan(0), reason: '要在引擎里找到取值判断');
      expect(selectorCheck, greaterThan(0), reason: '要在引擎里找到选择器判断');
      expect(
        valueCheck,
        lessThan(selectorCheck),
        reason: '取值判断必须写在选择器判断前面',
      );
    });

    test('裸 token 开头按标签算，不是按类算', () {
      expect(
        kComicSourceEngineJs,
        contains("type === 'id' ? '#' + first : (type === 'class' ? '.' + first : first)"),
        reason: '裸标签名（amp-img）不能变成 .amp-img',
      );
    });

    test('字符串转义覆盖引号、反斜杠、换行与控制字符', () {
      expect(jsonEncodeJs('a"b'), r'"a\"b"');
      expect(jsonEncodeJs(r'a\b'), r'"a\\b"');
      expect(jsonEncodeJs('a\nb'), r'"a\nb"');
      expect(jsonEncodeJs('\u0001'), r'"\u0001"');
    });
  });

  group('自检流程', () {
    ComicSource source() => ComicSource.tryParse(kSeedComicSourceJson)!;

    test('三步全通：给出服务名、章节数与首图地址', () async {
      final cardCss = cssFromComicRule(source().searchRules['bookList']!)!;
      final detailCss = cssFromComicRule(source().bookInfoRules['name']!)!;
      final tocCss = cssFromComicRule(source().bookInfoRules['tocUrl']!)!;

      final fake = _FakeTarget(
        counts: {cardCss: 77, detailCss: 1, '$tocCss a[href]': 1211},
        values: {
          source().searchRules['name']!: ['海贼王'],
          source().searchRules['bookUrl']!: ['/comic/haizeiwang'],
          source().bookInfoRules['name']!: ['航海王'],
          source().bookInfoRules['author']!: ['尾田荣一郎'],
        },
        hrefs: {'$tocCss a[href]': '/user/page_direct?comic_id=x&chapter_slot=1186'},
        jsText: {
          'java.getElements': '<img src="https://static-tw.baozimhcn.com/1.jpg">\n'
              '<img src="https://static-tw.baozimhcn.com/2.jpg">',
        },
      );

      final report = await runComicSourceProbe(
        target: fake,
        source: source(),
        key: '海贼',
        waitTimeout: const Duration(seconds: 1),
        pollInterval: const Duration(milliseconds: 1),
      );

      expect(report.allOk, isTrue, reason: '三步都该通过');
      expect(report.tocCount, 1211);
      expect(report.firstImageUrl, contains('static-tw.baozimhcn.com'));
      expect(report.steps.map((s) => s.name), ['搜索', '详情', '章节取图']);
      expect(fake.opened.first, contains('%E6%B5%B7%E8%B4%BC'), reason: '搜索用编码后的关键字');
    });

    test('卡片 0 命中且页面是 502：原因里必须说出来（不能只说"没数据"）', () async {
      final cardCss = cssFromComicRule(source().searchRules['bookList']!)!;
      final fake = _FakeTarget(title: '🐴 502 Bad Gateway');
      expect(fake.counts[cardCss], isNull);

      final report = await runComicSourceProbe(
        target: fake,
        source: source(),
        waitTimeout: const Duration(milliseconds: 300),
        pollInterval: const Duration(milliseconds: 1),
      );

      final search = report.steps.first;
      expect(search.ok, isFalse);
      expect(search.note, contains('0 命中'));
      expect(search.note, contains('502'), reason: '502 这种错误只看"命中 0"看不出来');
      expect(search.pageTitle, contains('502'));
    });

    test('还停在人机验证页：原因要指出来', () async {
      final fake = _FakeTarget(title: '正在验证浏览器');
      final report = await runComicSourceProbe(
        target: fake,
        source: source(),
        waitTimeout: const Duration(milliseconds: 200),
        pollInterval: const Duration(milliseconds: 1),
      );
      expect(report.steps.first.note, contains('人机验证'));
    });

    test('上一步失败时，后续步骤是"跳过"，不是"通过"', () async {
      final fake = _FakeTarget(title: '🐴 502 Bad Gateway');
      final report = await runComicSourceProbe(
        target: fake,
        source: source(),
        waitTimeout: const Duration(milliseconds: 200),
        pollInterval: const Duration(milliseconds: 1),
      );

      expect(report.steps, hasLength(3));
      expect(report.steps[1].ok, isFalse);
      expect(report.steps[1].note, contains('跳过'));
      expect(report.steps[2].ok, isFalse);
      expect(report.steps[2].note, contains('跳过'));
      expect(report.firstImageUrl, isNull);
    });

    test('取值规则不认识：这一步说明里带规则原文，且不当成"打不开页面"', () async {
      const broken = ComicSource(
        name: '坏源',
        baseUrl: 'https://x.example',
        searchUrl: 'https://x.example/s?q={{key}}',
        searchRules: {'bookList': 'class.a', 'name': 'class.b@@[bad]'},
      );
      final report = await runComicSourceProbe(
        target: _FakeTarget(counts: const {'.a': 3}),
        source: broken,
        waitTimeout: const Duration(milliseconds: 200),
        pollInterval: const Duration(milliseconds: 1),
      );
      final search = report.steps.first;
      expect(search.ok, isFalse);
      expect(search.note, contains('规则不认识'));
      expect(search.note, contains('class.b@@[bad]'));
      expect(search.note, isNot(contains('打不开')));
    });

    test('主站这一跳被重置：自动换镜像打开，并把波折写进结论', () async {
      final cardCss = cssFromComicRule(source().searchRules['bookList']!)!;
      final detailCss = cssFromComicRule(source().bookInfoRules['name']!)!;
      final tocCss = cssFromComicRule(source().bookInfoRules['tocUrl']!)!;
      final openUrl = source().searchUrlFor('海贼')!;
      const detailPath = '/comic/haizeiwang-weitianrongyilang';

      final fake = _FakeTarget(
        counts: {cardCss: 77, detailCss: 1, '$tocCss a[href]': 1211},
        values: {
          source().searchRules['name']!: ['海贼王'],
          source().searchRules['bookUrl']!: [detailPath],
          source().bookInfoRules['name']!: ['航海王'],
        },
        hrefs: {'$tocCss a[href]': '/user/page_direct?comic_id=x&chapter_slot=1186'},
        // 主站被重置，镜像能开
        failHosts: {
          'cn.baozimhcn.com': const ComicLoadFailure(
            code: -6,
            description: 'net::ERR_CONNECTION_RESET',
          ),
        },
        jsText: {'java.getElements': '<img src="https://static-tw.baozimhcn.com/1.jpg">'},
      );

      final report = await runComicSourceProbe(
        target: fake,
        source: source(),
        key: '海贼',
        waitTimeout: const Duration(seconds: 1),
        pollInterval: const Duration(milliseconds: 1),
      );

      final detail = report.steps[1];
      expect(detail.ok, isTrue, reason: '换镜像后应该能打开详情页');
      expect(detail.note, contains('连接被重置'), reason: '失败原因要说出来');
      expect(detail.note, contains('cn.bzmgcn.com'), reason: '要说清最后用的哪个地址');
      expect(
        fake.opened.any((u) => u.contains('cn.bzmgcn.com')),
        isTrue,
        reason: '确实去试了镜像',
      );
      expect(openUrl, contains('%E6%B5%B7%E8%B4%BC'));
    });

    test('主站第一次被重置、重试就成功：如实说明"第 2 次才成功"', () async {
      final cardCss = cssFromComicRule(source().searchRules['bookList']!)!;
      final fake = _FakeTarget(
        counts: {cardCss: 77},
        values: {
          source().searchRules['name']!: ['海贼王'],
          source().searchRules['bookUrl']!: ['/comic/haizeiwang-weitianrongyilang'],
        },
        failFirstNAttempts: 1,
      );
      final report = await runComicSourceProbe(
        target: fake,
        source: source(),
        waitTimeout: const Duration(seconds: 1),
        pollInterval: const Duration(milliseconds: 1),
      );
      final search = report.steps.first;
      expect(search.ok, isTrue, reason: '重试后取到内容就算通过');
      expect(search.note, contains('第 2 次才成功'));
      expect(fake.opened.length, greaterThan(1), reason: '确实重试了');
    });

    test('手机没网：只试一次就停，并说清是没有网络', () async {
      final fake = _FakeTarget(
        failHosts: {
          'cn.baozimhcn.com': const ComicLoadFailure(
            code: -106,
            description: 'net::ERR_INTERNET_DISCONNECTED',
          ),
          'cn.bzmgcn.com': const ComicLoadFailure(
            code: -106,
            description: 'net::ERR_INTERNET_DISCONNECTED',
          ),
        },
      );
      final report = await runComicSourceProbe(
        target: fake,
        source: source(),
        waitTimeout: const Duration(milliseconds: 200),
        pollInterval: const Duration(milliseconds: 1),
      );
      final search = report.steps.first;
      expect(search.ok, isFalse);
      expect(search.note, contains('没有网络'));
      expect(
        fake.opened.length,
        1,
        reason: '没网时换镜像/重试都没意义，不该白等',
      );
    });

    test('所有候选都打不开：把每个地址的错都列出来', () async {
      final fake = _FakeTarget(
        failHosts: {
          'cn.baozimhcn.com': const ComicLoadFailure(
            code: -6,
            description: 'net::ERR_CONNECTION_RESET',
          ),
          'cn.bzmgcn.com': const ComicLoadFailure(
            code: -502,
            description: 'HTTP 502',
          ),
          'www.baozimh.com': const ComicLoadFailure(
            code: -7,
            description: 'net::ERR_TIMED_OUT',
          ),
        },
      );
      final report = await runComicSourceProbe(
        target: fake,
        source: source(),
        waitTimeout: const Duration(milliseconds: 200),
        pollInterval: const Duration(milliseconds: 1),
      );
      final note = report.steps.first.note;
      expect(report.steps.first.ok, isFalse);
      expect(note, contains('cn.baozimhcn.com'));
      expect(note, contains('cn.bzmgcn.com'));
      expect(note, contains('www.baozimh.com'));
      expect(note, contains('连接被重置'));
      expect(note, contains('超时'), reason: '每个地址的错都要能区分');
    });

    test('列表规则不认识：这一步直接说"配置问题"，不冒充"命中 0"', () async {
      const broken = ComicSource(
        name: '坏源',
        baseUrl: 'https://x.example',
        searchUrl: 'https://x.example/s?q={{key}}',
        searchRules: {'bookList': 'class.a@@[bad]'},
      );
      final report = await runComicSourceProbe(
        target: _FakeTarget(counts: {'.a': 3}),
        source: broken,
        waitTimeout: const Duration(milliseconds: 200),
        pollInterval: const Duration(milliseconds: 1),
      );
      expect(report.steps.first.ok, isFalse);
      expect(report.steps.first.note, contains('配置问题'));
      expect(report.steps.first.note, contains('bookList'));
    });
  });

  group('加载错误分类与镜像候选', () {
    test('按描述文本判种类（数字码各平台不一致，描述最忠实）', () {
      expect(
        classifyComicLoadError(description: 'net::ERR_CONNECTION_RESET'),
        ComicLoadErrorKind.connectionReset,
      );
      expect(
        classifyComicLoadError(description: 'net::ERR_TIMED_OUT'),
        ComicLoadErrorKind.timeout,
      );
      expect(
        classifyComicLoadError(description: 'net::ERR_NAME_NOT_RESOLVED'),
        ComicLoadErrorKind.nameNotResolved,
      );
      expect(
        classifyComicLoadError(description: 'net::ERR_INTERNET_DISCONNECTED'),
        ComicLoadErrorKind.offline,
      );
      expect(
        classifyComicLoadError(code: 42, description: '说不清'),
        ComicLoadErrorKind.other,
      );
      // 描述读不出来时退回数字码：-6=连接失败、-7/-8=超时、-2=解析失败
      expect(classifyComicLoadError(code: -6), ComicLoadErrorKind.connectionOther);
      expect(classifyComicLoadError(code: -8), ComicLoadErrorKind.timeout);
      expect(classifyComicLoadError(code: -2), ComicLoadErrorKind.nameNotResolved);
    });

    test('只有"没网"不值得再试', () {
      expect(comicLoadErrorRetryable(ComicLoadErrorKind.connectionReset), isTrue);
      expect(comicLoadErrorRetryable(ComicLoadErrorKind.timeout), isTrue);
      expect(comicLoadErrorRetryable(ComicLoadErrorKind.offline), isFalse);
    });

    test('错误说明是人话（带原始串，便于对号入座）', () {
      expect(
        comicLoadErrorText(code: -6, description: 'net::ERR_CONNECTION_RESET'),
        contains('连接被重置'),
      );
      expect(
        comicLoadErrorText(code: -106, description: 'net::ERR_INTERNET_DISCONNECTED'),
        contains('没有网络'),
      );
    });

    test('候选地址：主站优先、镜像按序、去重；完整地址拆成路径再拼', () {
      const src = ComicSource(
        name: 'x',
        baseUrl: 'https://a.example',
        mirrors: ['https://b.example', 'https://a.example'],
      );
      expect(comicMirrorCandidates(src, '/comic/x'), [
        'https://a.example/comic/x',
        'https://b.example/comic/x',
      ]);
      expect(comicMirrorCandidates(src, 'https://a.example/comic/x?q=1'), [
        'https://a.example/comic/x?q=1',
        'https://b.example/comic/x?q=1',
      ]);
      expect(comicMirrorCandidates(src, ''), isEmpty);
    });

    test('内置源配了镜像，且第一个就是主站', () {
      final src = ComicSource.tryParse(kSeedComicSourceJson)!;
      expect(src.mirrors, isNotEmpty);
      expect(src.mirrors.first, src.baseUrl);
    });
  });
}
