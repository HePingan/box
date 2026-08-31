// 静态回归：禁止「await 之后不检查 mounted 就 setState」。
//
// 为什么用静态扫描而不是 widget 测试：这类崩溃分散在 8 个页面的 22 个调用点，
// 且触发条件是「用户在网络请求在途时退出页面」——逐个搭 widget 测试要 mock
// 每个页面的 HTTP 客户端（BoxAdminClient 虽可注入 http.Client，但页面内部是
// `final _client = BoxAdminClient()` 硬编码的，测试改不到）。静态扫描能一次
// 覆盖全仓并防止新代码再引入，成本和收益都更合适。
//
// 崩溃形态：
//   final r = await _client.updateQuota(...);   // 用户此时返回上一页
//   setState(() { _users = ... });              // State 已 dispose → 抛异常
//     FlutterError: setState() called after dispose()
//
// 正确写法（本仓已有 9 处这样写，属于风格不一致漏写）：
//   final r = await _client.updateQuota(...);
//   if (!mounted) return;
//   setState(() { ... });

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 匹配「await ... ; setState(」且中间不出现 mounted / setState 的片段。
///
/// 惰性量词 + 上限 400 字符：只看紧邻的调用点，避免跨越半个文件产生误报。
final _awaitThenSetState = RegExp(
  r'await(?:(?!mounted|setState|\n  \}|\n      \}\n)[\s\S]){0,400}?;\s*setState\(',
);

/// 跨函数边界的假阳性：`await` 收尾了上一个方法，`setState` 属于下一个方法。
/// 片段中间出现新的方法签名即判定为跨函数。
final _methodSignature = RegExp(
  r'\n\s*(?:Future|void|Widget|String|bool|int|double|List|Map)[\w<>,\s?]*\s+_?\w+\(',
);

void main() {
  test('await 之后 setState 必须先检查 mounted', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();

      for (final match in _awaitThenSetState.allMatches(source)) {
        final snippet = match.group(0)!;
        if (_methodSignature.hasMatch(snippet)) continue; // 跨函数，跳过

        final line = source.substring(0, match.start).split('\n').length;
        offenders.add('${entity.path}:$line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '以下位置在 await 之后直接 setState，未检查 mounted。\n'
          '用户在请求在途时退出页面会抛 setState() called after dispose()。\n'
          '修法：在 setState 前加 `if (!mounted) return;`\n\n'
          '${offenders.join('\n')}',
    );
  });
}
