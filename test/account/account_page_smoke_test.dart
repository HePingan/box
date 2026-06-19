import 'package:box/features/account/presentation/account_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('AccountPage renders without assertion', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MaterialApp(home: AccountPage()));
    await tester.pumpAndSettle();

    expect(find.text('账号中心'), findsWidgets);
    expect(find.text('登录 Box 平台账号'), findsOneWidget);
  });
}
