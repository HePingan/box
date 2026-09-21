import 'package:box/features/about/presentation/legal_consent_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 首启协议闸门行为回归。
///
/// 闸门的价值全在「拦得住」上，所以这里重点测的是绕过路径：
/// 返回键、未读完就同意、写入失败仍放行。
void main() {
  Widget host({
    required Future<bool> Function() onAccept,
    VoidCallback? onDecline,
    bool isReconsent = false,
  }) =>
      MaterialApp(
        home: LegalConsentGate(
          isReconsent: isReconsent,
          onAccept: onAccept,
          onDecline: onDecline ?? () {},
        ),
      );

  testWidgets('未滚到底时同意按钮禁用（同意要有据可依）', (tester) async {
    var accepted = false;
    await tester.pumpWidget(host(onAccept: () async {
      accepted = true;
      return true;
    }));
    await tester.pumpAndSettle();

    final agree = find.widgetWithText(FilledButton, '同意并继续');
    expect(agree, findsOneWidget);

    await tester.tap(agree);
    await tester.pumpAndSettle();

    expect(
      accepted,
      isFalse,
      reason: '没读完就能同意的话，"滚到底才可同意"这条约束等于没有',
    );
  });

  testWidgets('滚到底后可以同意，回调被调用', (tester) async {
    var accepted = false;
    await tester.pumpWidget(host(onAccept: () async {
      accepted = true;
      return true;
    }));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -30000));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '同意并继续'));
    await tester.pumpAndSettle();

    expect(accepted, isTrue);
  });

  testWidgets('写入失败时提示重试，不静默放行', (tester) async {
    await tester.pumpWidget(host(onAccept: () async => false));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -30000));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '同意并继续'));
    await tester.pumpAndSettle();

    // 失败必须看得见：假装成功的话用户下次启动会再被拦，且不知道为什么。
    expect(find.textContaining('保存失败'), findsOneWidget);
  });

  testWidgets('返回键拦得住：不触发同意也不放行', (tester) async {
    var accepted = false;
    await tester.pumpWidget(host(onAccept: () async {
      accepted = true;
      return true;
    }));
    await tester.pumpAndSettle();

    // 真按一次系统返回键：比只读 canPop 更接近真实操作。
    final popped = await tester.binding.handlePopRoute()
        .then((_) => true)
        .catchError((_) => false);
    await tester.pumpAndSettle();

    // 闸门必须还在（没被 pop 掉），且没有触发同意。
    expect(
      find.byType(LegalConsentGate),
      findsOneWidget,
      reason: '按返回键后闸门消失了，用户就绕过协议进了应用（popped=$popped）',
    );
    final widget = tester.widget<PopScope>(find.byType(PopScope).first);
    expect(
      widget.canPop,
      isFalse,
      reason: 'canPop 一旦为 true，用户按返回就绕过闸门直接进应用了',
    );
    expect(accepted, isFalse);
  });

  testWidgets('协议改版时措辞是「已更新」，不是「首次」', (tester) async {
    await tester.pumpWidget(
      host(isReconsent: true, onAccept: () async => true),
    );
    await tester.pumpAndSettle();

    // 老用户看到"请阅读并同意"会以为应用被重装了。
    expect(find.textContaining('已更新'), findsWidgets);
  });
}
