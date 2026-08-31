// 行为回归：证明「await 后无 mounted 守卫的 setState」确实会抛异常。
//
// 上面的静态扫描（mounted_guard_after_await_test.dart）负责覆盖全仓 22 个调用点，
// 这个测试负责证明那个模式**真的会崩**——否则静态规则只是风格偏好，缺少说服力。
//
// 复现的就是 admin_page.dart:111 的结构：
//   final r = await _client.updateQuota(...);   // 网络在途
//   setState(() { ... });                       // 用户已退页面

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 复刻线上写法：await 之后直接 setState，不检查 mounted。
class _UnguardedPage extends StatefulWidget {
  const _UnguardedPage({required this.request});

  final Future<String> Function() request;

  @override
  State<_UnguardedPage> createState() => _UnguardedPageState();
}

class _UnguardedPageState extends State<_UnguardedPage> {
  String _value = 'init';

  Future<void> load() async {
    final result = await widget.request();
    setState(() => _value = result); // ← 缺 if (!mounted) return;
  }

  @override
  Widget build(BuildContext context) => Text(_value, textDirection: TextDirection.ltr);
}

/// 正确写法：await 之后先检查 mounted。
class _GuardedPage extends StatefulWidget {
  const _GuardedPage({required this.request});

  final Future<String> Function() request;

  @override
  State<_GuardedPage> createState() => _GuardedPageState();
}

class _GuardedPageState extends State<_GuardedPage> {
  String _value = 'init';

  Future<void> load() async {
    final result = await widget.request();
    if (!mounted) return;
    setState(() => _value = result);
  }

  @override
  Widget build(BuildContext context) => Text(_value, textDirection: TextDirection.ltr);
}

void main() {
  testWidgets('无守卫：请求在途时退出页面 → setState after dispose 抛异常', (tester) async {
    final completer = Completer<String>();

    await tester.pumpWidget(_UnguardedPage(request: () => completer.future));
    final state = tester.state<_UnguardedPageState>(find.byType(_UnguardedPage));

    final pending = state.load(); // 发起请求，此时未完成

    // 用户退出页面：State 被 dispose
    await tester.pumpWidget(const SizedBox.shrink());

    // 请求这时才返回 → setState 打在已 dispose 的 State 上。
    // 该断言由 framework 直接抛出，不经 takeException，需自行捕获。
    Object? captured;
    completer.complete('done');
    try {
      await pending;
    } catch (error) {
      captured = error;
    }

    expect(
      captured,
      isFlutterError,
      reason: '这正是线上崩溃：await 返回时页面已销毁，setState 抛 called after dispose',
    );
    expect(
      captured.toString(),
      contains('setState() called after dispose()'),
    );
  });

  testWidgets('有守卫：同样时序下安全无异常', (tester) async {
    final completer = Completer<String>();

    await tester.pumpWidget(_GuardedPage(request: () => completer.future));
    final state = tester.state<_GuardedPageState>(find.byType(_GuardedPage));

    final pending = state.load();
    await tester.pumpWidget(const SizedBox.shrink());

    completer.complete('done');
    await pending;

    expect(tester.takeException(), isNull, reason: 'mounted 守卫应拦住 setState');
  });
}
