// 网页源码获取：注入假取数，单测不联网。
//
// 守的底线：
//   1. 认不出的地址当场说清楚，不装作在拉；
//   2. 失败必须写出原因（超时/DNS/握手），不能只转圈；
//   3. 截断了要明说，不做假完整；
//   4. 非 2xx 要标出来 —— 404 的页面源码也有用，但不能当成"拉取成功"。
import 'package:box/features/tools/presentation/source_fetch_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeFetch implements SourceFetch {
  _FakeFetch(this.result);

  final SourceFetchResult result;
  final List<String> asked = [];

  @override
  Future<SourceFetchResult> fetch(
    String url, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    asked.add(url);
    return result;
  }
}

Future<void> _pump(WidgetTester tester, SourceFetch fetch) async {
  await tester.pumpWidget(MaterialApp(home: SourceFetchPage(fetch: fetch)));
  await tester.pumpAndSettle();
}

Future<void> _runWith(WidgetTester tester, String url) async {
  await tester.enterText(find.byType(TextField), url);
  await tester.tap(find.text('拉取源码'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('认不出的地址：当场红字，不去发请求', (tester) async {
    final fake = _FakeFetch(const SourceFetchResult(bytes: [], statusCode: 200));
    await _pump(tester, fake);

    await _runWith(tester, '这不是地址');

    expect(find.textContaining('认不出'), findsOneWidget);
    expect(fake.asked, isEmpty, reason: '地址不合法就不该发请求');
  });

  testWidgets('200：显示源码、状态码与大小', (tester) async {
    final fake = _FakeFetch(
      SourceFetchResult(
        bytes: '{"latestVersionCode": 315}'.codeUnits,
        statusCode: 200,
        contentType: 'application/json',
        finalUrl: 'https://box.hpa888.top/x.json',
      ),
    );
    await _pump(tester, fake);

    await _runWith(tester, 'box.hpa888.top/x.json');

    expect(fake.asked.single, 'https://box.hpa888.top/x.json', reason: '没写协议按 https 试');
    expect(find.textContaining('HTTP 200'), findsOneWidget);
    expect(find.textContaining('latestVersionCode'), findsOneWidget);
    expect(find.textContaining('没拉到内容'), findsNothing);
  });

  testWidgets('截断：明说截断，不假装内容完整', (tester) async {
    final fake = _FakeFetch(
      SourceFetchResult(
        bytes: List<int>.filled(kSourceFetchMaxBytes, 65),
        statusCode: 200,
        truncated: true,
      ),
    );
    await _pump(tester, fake);

    await _runWith(tester, 'example.com/huge');

    expect(find.textContaining('已截断'), findsOneWidget);
  });

  testWidgets('失败：写出原因，而不是一直转圈', (tester) async {
    final fake = _FakeFetch(
      const SourceFetchResult(bytes: [], error: '域名解析不了（DNS 查不到这台主机）'),
    );
    await _pump(tester, fake);

    await _runWith(tester, 'nope.invalid');

    expect(find.textContaining('没拉到内容'), findsOneWidget);
    expect(find.textContaining('域名解析不了'), findsOneWidget);
    expect(find.textContaining('拉取中'), findsNothing);
  });

  testWidgets('404：标出来，但仍把源码给出来（调试时有用）', (tester) async {
    final fake = _FakeFetch(
      SourceFetchResult(bytes: '<html>404 Not Found</html>'.codeUnits, statusCode: 404),
    );
    await _pump(tester, fake);

    await _runWith(tester, 'example.com/missing');

    expect(find.textContaining('HTTP 404'), findsOneWidget);
    expect(find.textContaining('404 Not Found'), findsOneWidget);
  });
}
