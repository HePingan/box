import 'package:box/app/app_routes.dart';
import 'package:box/novel/pages/source_manager/book_source_bootstrap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 关于页用到的命名路由必须都注册过。
///
/// 由来：关于页里全部入口都走 `Navigator.pushNamed(AppRoutes.xxx)`。少注册一个
/// **编译期查不出来**，只有用户点到那一项时才抛
/// "Could not find a generator for route"。analyze 全绿也拦不住，
/// 所以在这里逐个核对。
void main() {
  // buildRoutes 需要书源引导结果；关于页那些路由不依赖它，给个已配置的空壳即可。
  final routes = AppRoutes.buildRoutes(
    const BookSourceBootstrapResult(configured: true, message: ''),
  );

  test('关于页的每个入口路由都有对应的 builder', () {
    const used = <String>[
      AppRoutes.about,
      AppRoutes.updateCheck,
      AppRoutes.updateHistory,
      AppRoutes.aboutIntroduction,
      AppRoutes.aboutGuide,
      AppRoutes.aboutTutorial,
      AppRoutes.legalUserAgreement,
      AppRoutes.legalPrivacyPolicy,
      AppRoutes.debugLog,
    ];

    for (final name in used) {
      expect(
        routes.containsKey(name),
        isTrue,
        reason: '路由 $name 没注册：用户点到这一项会直接抛路由异常',
      );
    }
  });

  test('路由名以 / 开头且不重复', () {
    for (final name in routes.keys) {
      expect(name.startsWith('/'), isTrue, reason: '路由名 $name 缺少前导 /');
    }
    // Map 本身不允许重复键，这里防的是"两个常量取了同一个字符串值"，
    // 那种情况下后注册的会把前面的覆盖掉，且毫无提示。
    const constants = <String>[
      AppRoutes.about,
      AppRoutes.updateCheck,
      AppRoutes.updateHistory,
      AppRoutes.aboutIntroduction,
      AppRoutes.aboutGuide,
      AppRoutes.aboutTutorial,
      AppRoutes.legalUserAgreement,
      AppRoutes.legalPrivacyPolicy,
    ];
    expect(
      constants.toSet().length,
      constants.length,
      reason: '有两个路由常量取了相同字符串，其中一个页面永远打不开',
    );
  });

  testWidgets('每个关于页路由都能真正构建出页面', (tester) async {
    // 只注册不等于能用：builder 里少传必填参数一样是运行时崩。
    for (final name in <String>[
      AppRoutes.about,
      AppRoutes.aboutIntroduction,
      AppRoutes.aboutGuide,
      AppRoutes.aboutTutorial,
      AppRoutes.legalUserAgreement,
      AppRoutes.legalPrivacyPolicy,
    ]) {
      await tester.pumpWidget(MaterialApp(
        routes: routes,
        initialRoute: name,
      ));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        tester.takeException(),
        isNull,
        reason: '路由 $name 构建时抛异常',
      );
    }
  });
}
