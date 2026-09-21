import 'dart:io';

import 'package:box/design_system/widgets/app_back_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `AppBackButton.label` 语义回归锁。
///
/// 真实现象（用户截图，1.12.x）：知乎日报文章页顶部「热点」和「热点详情」两段
/// 文字左右重叠糊在一起。
///
/// 根因不是布局算错，是**同一个字符串被喂给了两个槽位**
/// （`lib/daily_news_page.dart:56-67`）：
///
/// ```dart
/// leading: AppBackButton(label: '热点详情'),   // leading 槽位固定窄宽
/// title: Text('热点详情'),                     // 紧接其右
/// ```
///
/// `AppBar.leading` 的宽度是固定的（默认 56dp），塞进「图标+4 个汉字」必然
/// 溢出，而 `title` 就从 leading 右边缘开始画 —— 于是两段文字水平重叠。
/// 截图里「热点」和「热点详情」字号还不一样（13 vs 18），正是这两个不同槽位。
///
/// 更根本的是**语义错**：`label` 的意思是「返回到**哪里**」（目的地），
/// 不是「当前页叫什么」。把当前页名填进去，既重复又指错方向 ——
/// 用户看到的是「← 热点详情」，读起来像是「点这里去热点详情」，
/// 而实际上他正在热点详情页里，点了是往外退。
void main() {
  group('AppBackButton 渲染', () {
    testWidgets('不传 label 时只有箭头，没有多余文字', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppBackButton()),
        ),
      );
      expect(find.byType(Text), findsNothing);
      expect(find.byIcon(Icons.keyboard_arrow_left_rounded), findsOneWidget);
    });

    testWidgets('传 label 时渲染该文字', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppBackButton(label: '书架')),
        ),
      );
      expect(find.text('书架'), findsOneWidget);
    });
  });

  group('AppBar 槽位不得重复', () {
    testWidgets('把当前页名同时给 leading 和 title 会挤爆 leading 槽位', (tester) async {
      // 缺陷形状的可执行证据：AppBar.leading 宽度固定（默认 56dp，去掉内边距
      // 只剩 ~34dp 给内容），塞「图标 + 4 个汉字」必然 RenderFlex overflow，
      // 而 title 从 leading 右边缘开始画 —— 视觉上就是两段文字糊在一起。
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              leading: const AppBackButton(label: '热点详情'),
              title: const Text('热点详情'),
            ),
          ),
        ),
      );

      expect(
        tester.takeException(),
        isFlutterError,
        reason: 'leading 槽位装不下「图标+4 汉字」，应当溢出报错',
      );

      // 同一个词被画了两遍，这是重复本身
      expect(find.text('热点详情'), findsNWidgets(2));
    });

    testWidgets('只给 title 时不溢出、只出现一次', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              leading: const AppBackButton(),
              title: const Text('热点详情'),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull, reason: '修好后不应再溢出');
      expect(find.text('热点详情'), findsOneWidget);
    });

    test('daily_news_page 的 leading 不得再带 label', () {
      final src = _read('lib/daily_news_page.dart');
      final args = _leadingBackButtonArgs(src);

      expect(args, isNotEmpty, reason: '页面结构变了，请同步此测试');
      for (final a in args) {
        expect(
          a.contains('label:'),
          isFalse,
          reason: 'label 与 title 同字会在 AppBar 里水平重叠（用户截图的 bug）',
        );
      }
    });
  });

  group('全项目闸门', () {
    test('没有任何 AppBar 的 leading 把当前页标题重复成 label', () {
      final offenders = <String>[];

      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync();
        if (!src.contains('AppBackButton')) continue;

        // 只查 AppBar/SliverAppBar 的 leading —— HeroCard 的 leading 独占一行，
        // 不与 title 争抢横向空间，重复但不重叠，属另一类问题。
        for (final hit in _leadingBackButtonHits(src)) {
          if (!hit.args.contains('label:')) continue;
          // 该 leading 是否属于一个 AppBar / SliverAppBar
          final before = src.substring(0, hit.start);
          final lastAppBar = RegExp(r'(?:Sliver)?AppBar\(')
              .allMatches(before)
              .toList();
          if (lastAppBar.isEmpty) continue;
          // AppBar 到 leading 之间不应再夹别的 Widget 构造收尾（粗判：距离够近）
          if (hit.start - lastAppBar.last.end > 700) continue;
          final line = before.split('\n').length;
          offenders.add('${f.path}:$line');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'AppBar 的 leading 带 label 会与 title 重叠：\n'
            '${offenders.join('\n')}\n'
            'label 应留空（或写「返回到哪儿」），当前页名交给 title。',
      );
    });
  });
}

String _read(String path) {
  final f = File(path);
  if (!f.existsSync()) fail('找不到 $path —— 源码级闸门失效');
  return f.readAsStringSync();
}

class _Hit {
  _Hit(this.start, this.args);
  final int start;
  final String args;
}

/// 抓出所有 `leading: AppBackButton[Light](...)` 的**完整**参数串。
///
/// 必须括号配平地扫：参数里普遍有 `Navigator.pop(context)` 这种内层括号，
/// 用 `[^)]*` 或贪婪 `(.*?)\)` 都会在第一个 `)` 处截断，
/// 于是读不到后面的 `label:` —— 闸门会**假绿**。这个坑本次真踩了一次。
List<_Hit> _leadingBackButtonHits(String src) {
  final hits = <_Hit>[];
  final re = RegExp(r'leading:\s*AppBackButton(?:Light)?\(');
  for (final m in re.allMatches(src)) {
    var depth = 1;
    var i = m.end;
    while (i < src.length && depth > 0) {
      final c = src[i];
      if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
      }
      i++;
    }
    hits.add(_Hit(m.start, src.substring(m.end, i - 1)));
  }
  return hits;
}

List<String> _leadingBackButtonArgs(String src) =>
    _leadingBackButtonHits(src).map((h) => h.args).toList();
