import 'dart:convert';

import 'package:box/features/admin/data/quiz_bank_admin_client.dart';
import 'package:box/features/admin/presentation/widgets/quiz_bank_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 编辑器顶部功能区的布局回归。
///
/// 用户反馈「编辑题目最上面一排功能按钮有点显示不全」。这一排是
/// AppBar.bottom 里的固定高 48px Row：3 个题型 chip + 3 个状态 ChoiceChip
/// 挤在一行，窄屏必然横向溢出，且 Row 不会自动裁剪 → RenderFlex overflow。
void main() {
  List<Map<String, dynamic>> sampleQuestions() => [
    {
      'id': 'q-1',
      'question': '地球是圆的',
      'options': ['正确', '错误'],
      'answer': '正确',
      'status': 'published',
      'category': '常识',
    },
  ];

  MockClient buildClient() => MockClient((request) async {
    if (request.url.path.contains('/api/quiz/questions')) {
      return http.Response(
        jsonEncode({'questions': sampleQuestions(), 'total': 1}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response(
      '{}',
      200,
      headers: {'content-type': 'application/json'},
    );
  });

  Future<void> openEditor(
    WidgetTester tester, {
    Size size = const Size(400, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = QuizBankResourceProvider(
      client: QuizBankAdminClient(httpClient: buildClient()),
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

    // 走真实入口：顶栏「添加题目」按钮
    await tester.tap(find.byIcon(Icons.add_circle_rounded));
    await tester.pumpAndSettle();
  }

  group('编辑器顶部功能区', () {
    testWidgets('窄屏 360 宽下顶部一排功能按钮不溢出', (tester) async {
      await openEditor(tester, size: const Size(360, 800));

      expect(find.text('添加题目'), findsOneWidget);
      // 三个题型入口都要在
      expect(find.text('单选'), findsOneWidget);
      expect(find.text('多选'), findsOneWidget);
      expect(find.text('判断'), findsOneWidget);
      // 三个状态入口都要在
      expect(find.text('草稿'), findsOneWidget);
      expect(find.text('待审核'), findsOneWidget);
      expect(find.text('已发布'), findsOneWidget);

      // 关键断言：不能有 overflow 异常
      expect(tester.takeException(), isNull);
    });

    testWidgets('极窄屏 320 宽下顶部一排仍不溢出', (tester) async {
      await openEditor(tester, size: const Size(320, 700));

      expect(find.text('单选'), findsOneWidget);
      expect(find.text('已发布'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
