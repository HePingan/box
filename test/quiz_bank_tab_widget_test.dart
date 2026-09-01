import 'dart:convert';

import 'package:box/features/admin/data/quiz_bank_admin_client.dart';
import 'package:box/features/admin/presentation/widgets/quiz_bank_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 首界面重构的 widget 层回归。
///
/// 重构把首屏从七层压到四层（顶栏 / 三格汇总 / 筛选行 / 列表），并把搜索框
/// 改成默认收起、筛选全进底部弹层、多选改成长按进入。这些都是 UI 行为，
/// 纯 filter 单测覆盖不到，之前两轮的 bug（顶栏漏做、筛选写进影子变量、
/// 批量操作后卡在多选态）恰好都是这一层。这里用 MockClient 喂真实 provider，
/// 把交互钉住。
void main() {
  /// 五道题，覆盖判断/单选/多选 + 有图/无图，够撑起筛选断言。
  List<Map<String, dynamic>> sampleQuestions() => [
    {
      'id': 'q-1',
      'question': '地球是圆的',
      'options': ['正确', '错误'],
      'answer': '正确',
      'status': 'published',
      'image': 'https://cdn.example.com/earth.png',
      'category': '常识',
    },
    {
      'id': 'q-2',
      'question': '以下哪个是编程语言',
      'options': ['Dart', '苹果', '桌子'],
      'answer': 'A',
      'status': 'published',
    },
    {
      'id': 'q-3',
      'question': '哪些属于水果',
      'options': ['苹果', '香蕉', '铅笔'],
      'answer': 'AB',
      'status': 'pending',
      'image': 'data:image/png;base64,!!!broken!!!',
    },
    {
      'id': 'q-4',
      'question': '水的沸点是一百摄氏度',
      'options': ['正确', '错误'],
      'answer': '正确',
      'status': 'rejected',
    },
    {
      'id': 'q-5',
      'question': '选出最大的数',
      'options': ['1', '2', '3'],
      'answer': 'C',
      'status': 'published',
      'image': 'https://cdn.example.com/num.png',
    },
    {
      'id': 'q-6',
      'question': '这是什么交通标志',
      'options': ['停车让行', '减速让行', '会车让行'],
      'answer': 'A',
      'status': 'published',
      // 生产库里所有有图题目都是这种相对路径（/api/quiz/images/...），
      // 之前 fixture 只有绝对 URL，所以漏掉了缩略图不显示的 bug。
      'image': '/api/quiz/images/quiz_1787373575843_de237bc49c4585a6.jpg',
      'category': '交通标志',
    },
  ];

  /// 拦下 tab 启动时的四个 GET，其余一律空。
  /// 图片请求返回 1x1 PNG，避免 Image.network 在测试里报 400。
  MockClient buildClient({
    List<Map<String, dynamic>>? questions,
    List<Map<String, dynamic>> pending = const [],
    List<Map<String, dynamic>> incomplete = const [],
    List<Map<String, dynamic>> imports = const [],
    void Function(http.Request request)? onRequest,
  }) {
    return MockClient((request) async {
      onRequest?.call(request);
      final path = request.url.path;
      if (path.endsWith('/admin/quiz/questions')) {
        return http.Response(
          jsonEncode({'questions': questions ?? sampleQuestions()}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (path.contains('/admin/quiz/submissions')) {
        return http.Response(
          jsonEncode({'submissions': pending}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (path.endsWith('/admin/quiz/incomplete')) {
        return http.Response(
          jsonEncode({'items': incomplete}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (path.endsWith('/admin/quiz/imports')) {
        return http.Response(
          jsonEncode({'imports': imports}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response(
        jsonEncode({'ok': true}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
  }

  /// 顶栏溢出菜单：卡片上也有 PopupMenuButton，必须按 tooltip 精确定位。
  final overflowMenu = find.byWidgetPredicate(
    (w) => w is PopupMenuButton<String> && w.tooltip == '更多操作',
  );

  Future<void> pumpTab(
    WidgetTester tester, {
    MockClient? client,
    Size size = const Size(400, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = QuizBankResourceProvider(
      client: QuizBankAdminClient(httpClient: client ?? buildClient()),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuizBankAdminTab(
            provider: provider,
            serverUrl: 'https://example.com',
            token: 'test-token',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('首屏结构', () {
    testWidgets('顶栏、三格汇总、筛选行、列表在第一屏同时可见', (tester) async {
      await pumpTab(tester);

      // 顶栏：标题 + 三个动作
      expect(find.text('题库管理'), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(find.byIcon(Icons.add_circle_rounded), findsOneWidget);
      expect(overflowMenu, findsOneWidget);

      // 汇总三格。「待审核」「待补全」在筛选 chip 里也是同名文案，
      // 所以按「格子里的数字 + 标签同属一个 Column」来定位，避免误判。
      for (final (label, value) in [('总题', '6'), ('待审', '0'), ('残缺', '0')]) {
        final cell = find.ancestor(
          of: find.text(label),
          matching: find.byType(Column),
        );
        expect(
          find.descendant(of: cell.first, matching: find.text(value)),
          findsWidgets,
          reason: '汇总格「$label」应显示计数 $value',
        );
      }

      // 筛选行 + 列表：重构的核心目标就是列表不被挤到折叠线以下
      expect(find.text('筛选'), findsOneWidget);
      // 前两张卡在第一屏内就已挂载（SliverList 懒建，第五张在视口外不建，
      // 所以这里只钉住列表确实出现在折叠线以上，不断言全部五题）。
      expect(find.text('地球是圆的'), findsOneWidget);
      expect(find.text('以下哪个是编程语言'), findsOneWidget);
    });

    testWidgets('搜索框默认收起，点放大镜才展开一行', (tester) async {
      await pumpTab(tester);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      // 再点收起，同时清空搜索词
      await tester.tap(find.byIcon(Icons.search_off_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('无筛选时筛选行显示总题数', (tester) async {
      await pumpTab(tester);
      expect(find.text('共 6 题'), findsOneWidget);
    });
  });

  group('筛选弹层', () {
    testWidgets('弹层选状态后列表真的过滤，且筛选按钮显示角标', (tester) async {
      await pumpTab(tester);
      expect(find.text('地球是圆的'), findsOneWidget);

      await tester.tap(find.text('筛选'));
      await tester.pumpAndSettle();

      // 弹层三组条件都在，图片组带实时计数
      expect(find.text('状态'), findsOneWidget);
      expect(find.text('图片'), findsOneWidget);
      expect(find.text('题型'), findsOneWidget);
      // 3 道题里有 2 道有效图片（q-1 和 q-5），q-3 是脏 data URL 降级占位
      expect(find.textContaining('有图 (3)'), findsOneWidget);

      await tester.tap(find.text('待审核').last);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('应用'));
      await tester.pumpAndSettle();

      // 只剩 pending 那道
      expect(find.text('哪些属于水果'), findsOneWidget);
      expect(find.text('地球是圆的'), findsNothing);
      expect(find.text('筛选 · 1'), findsOneWidget);
    });

    testWidgets('弹层取消不改动已生效的筛选', (tester) async {
      await pumpTab(tester);

      await tester.tap(find.text('筛选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('待审核').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.text('地球是圆的'), findsOneWidget);
      expect(find.text('筛选'), findsOneWidget);
    });

    testWidgets('生效条件 chip 可以单独叉掉', (tester) async {
      // 视口给高一点：SliverList 懒建，400x800 只挂前三张卡，
      // 叉掉筛选后要断言第四题回来，卡必须真的在视口里。
      await pumpTab(tester, size: const Size(400, 2400));

      await tester.tap(find.text('筛选'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('有图 (3)'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('应用'));
      await tester.pumpAndSettle();

      expect(find.text('筛选 · 1'), findsOneWidget);
      expect(find.text('水的沸点是一百摄氏度'), findsNothing);

      // chip 上的叉号清掉这一维（Chip.onDeleted 默认渲染 Icons.cancel）
      await tester.tap(find.byIcon(Icons.cancel).first);
      await tester.pumpAndSettle();

      expect(find.text('筛选'), findsOneWidget);
      expect(find.text('水的沸点是一百摄氏度'), findsOneWidget);
    });

    testWidgets('搜索词与弹层条件叠加过滤，收起搜索会清掉搜索词', (tester) async {
      await pumpTab(tester);

      await tester.tap(find.text('筛选'));
      await tester.pumpAndSettle();
      // 注意两套文案：弹层选项叫「已通过」，卡片状态标签叫「已发布」。
      // 且必须限定到 FilterChip 内，否则会点到列表卡片上、筛选根本没生效。
      await tester.tap(
        find.descendant(
          of: find.byType(FilterChip),
          matching: find.text('已通过'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('应用'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '编程');
      await tester.pumpAndSettle();

      // 搜索展开时筛选行被搜索框顶掉（v8 设计：顶栏同一行二选一），
      // 所以先验筛选真的生效了：只剩同时命中「已发布 + 编程」的那题。
      expect(find.text('以下哪个是编程语言'), findsOneWidget);
      expect(find.text('地球是圆的'), findsNothing);

      // 收起搜索：按钮此时是 search_off，且实现里会顺手 clear() 搜索词，
      // 所以回到「只剩状态一个条件」，列表恢复到该状态下的全部题目。
      await tester.tap(find.byIcon(Icons.search_off_rounded));
      await tester.pumpAndSettle();
      expect(find.text('筛选 · 1'), findsOneWidget);
      expect(find.text('地球是圆的'), findsOneWidget);
    });
  });

  group('题目卡片', () {
    testWidgets('默认矮身，点一下展开看选项和答案', (tester) async {
      await pumpTab(tester);

      // 收起态不显示展开区（小节标题是「选项」「答案」，不带冒号）
      expect(find.text('选项'), findsNothing);

      await tester.tap(find.text('以下哪个是编程语言'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Dart'), findsOneWidget);
      expect(find.text('选项'), findsOneWidget);
      expect(find.text('答案'), findsOneWidget);

      // 再点收起
      await tester.tap(find.text('以下哪个是编程语言'));
      await tester.pumpAndSettle();
      expect(find.text('选项'), findsNothing);
    });

    testWidgets('脏 data URL 的缩略图降级占位，不抛异常糊掉列表项', (tester) async {
      await pumpTab(tester);

      // q-3 的 image 是被截断的 base64，旧实现会在 build 里抛 FormatException
      expect(tester.takeException(), isNull);
      expect(find.text('哪些属于水果'), findsOneWidget);
      expect(find.byIcon(Icons.image_not_supported), findsWidgets);
    });

    testWidgets('相对路径题图要拼上服务器地址真的发请求，不能降级成占位图', (tester) async {
      // 生产库里 image 全是 /api/quiz/images/xxx 这种相对路径。
      // 旧实现调 QuizThumbImageSource.parse(image) 没传 base，
      // 相对路径一律落到 placeholder 分支 → 后台有图的题全显示"无图"图标。
      await pumpTab(tester, size: const Size(400, 2800));

      expect(find.text('这是什么交通标志'), findsOneWidget);

      // Image.network 走 Flutter 自己的 HttpClient（测试环境一律 400），
      // 抓不到 MockClient 上，所以断言渲染出的 NetworkImage 地址：
      // 必须是 serverUrl + 相对路径拼出来的完整 URL。
      final networkUrls = tester
          .widgetList<Image>(find.byType(Image))
          .map((w) => w.image)
          .whereType<NetworkImage>()
          .map((p) => p.url)
          .toList();

      expect(
        networkUrls,
        contains(
          'https://example.com/api/quiz/images/'
          'quiz_1787373575843_de237bc49c4585a6.jpg',
        ),
        reason: '相对路径题图没拼上 serverUrl，说明又降级成占位图了。\n'
            '实际渲染的图片地址：$networkUrls',
      );
    });
  });

  group('多选模式', () {
    testWidgets('长按进入多选并浮出操作条，点关闭退出', (tester) async {
      // 五张卡都要挂载才能数满 5 个 Checkbox（SliverList 懒建）
      await pumpTab(tester, size: const Size(400, 2400));

      // 默认没有操作条
      expect(find.textContaining('已选'), findsNothing);

      await tester.longPress(find.text('地球是圆的'));
      await tester.pumpAndSettle();

      expect(find.textContaining('已选 1 题'), findsOneWidget);
      expect(find.byType(Checkbox), findsNWidgets(6));

      // 多选态里加选第二题。进入多选后每张卡多出一个 Checkbox、
      // 高度变化会让卡片整体下移，所以按当前帧的 Checkbox 定位，
      // 不能复用进入多选前算出的文本坐标（会点到上一张卡上）。
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();
      expect(find.textContaining('已选 2 题'), findsOneWidget);

      // 点击是加选，不是展开
      expect(find.text('选项'), findsNothing);

      // 退出多选：操作条最左侧的关闭按钮（tooltip 定位，避开卡片上的其他图标）
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == '退出多选',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('已选'), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('多选态下滚动列表不崩溃', (tester) async {
      // 回归：操作条曾用 pinned SliverPersistentHeader，声明固定 56 的
      // min/maxExtent，上方内容滚出视口时 layoutExtent 超过 paintExtent，
      // 抛「SliverGeometry is not valid」糊红整页。
      await pumpTab(tester, size: const Size(400, 600));

      await tester.longPress(find.text('地球是圆的'));
      await tester.pumpAndSettle();
      expect(find.textContaining('已选 1 题'), findsOneWidget);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('已选 1 题'), findsOneWidget);
    });

    testWidgets('取消最后一个选中项自动退出多选态', (tester) async {
      await pumpTab(tester);

      await tester.longPress(find.text('地球是圆的'));
      await tester.pumpAndSettle();
      expect(find.textContaining('已选 1 题'), findsOneWidget);

      // 取消唯一的选中项（用当前帧的 Checkbox，避开布局位移）
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      // 已选归零时不能停在多选态：操作条不显示，用户会失去出口
      expect(find.textContaining('已选'), findsNothing);
      expect(find.byType(Checkbox), findsNothing);

      // 回到普通态：点击应该是展开，不是加选
      await tester.tap(find.text('以下哪个是编程语言'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Dart'), findsOneWidget);
    });
  });

  group('顶栏溢出菜单', () {
    testWidgets('菜单三项齐全，导入记录带条数', (tester) async {
      await pumpTab(
        tester,
        client: buildClient(
          imports: [
            {'id': 'imp-1', 'count': 3},
            {'id': 'imp-2', 'count': 5},
          ],
        ),
      );

      await tester.tap(overflowMenu);
      await tester.pumpAndSettle();

      expect(find.text('刷新'), findsOneWidget);
      expect(find.text('导入 JSON'), findsOneWidget);
      expect(find.text('导入记录（2）'), findsOneWidget);
    });

    testWidgets('刷新重新拉取题库', (tester) async {
      var questionCalls = 0;
      await pumpTab(
        tester,
        client: buildClient(
          onRequest: (request) {
            if (request.url.path.endsWith('/admin/quiz/questions') &&
                request.method == 'GET') {
              questionCalls++;
            }
          },
        ),
      );
      expect(questionCalls, 1);

      await tester.tap(overflowMenu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('刷新'));
      await tester.pumpAndSettle();

      expect(questionCalls, 2);
    });
  });
}