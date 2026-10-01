// 仓库护栏：读屏插件里**被 await 的平台通道调用必须带终点**（.timeout）。
//
// 2026-10-01 事故的机制就是这个：`invokeMethod(...)` 等原生回包，原生在被更新的请求
// 顶掉时不回包 → await 永不返回 → 界面永远「读屏中」、服务端零请求。
// 事后统计：这个插件里有 28 处 await 的通道调用没有超时（只给截图那 3 处加过）。
//
// 这条用例把它们挡住：新增代码漏加 `.timeout` 会在 CI 直接红。
// 确实不需要终点的调用（例如等用户操作的通道已在实现里用长时限覆盖）请在语句里显式写
// `// no-timeout: <原因>` —— 让"豁免"是被读到的决定，而不是被忽略的疏漏。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('读屏插件里 await 的通道调用必须带 .timeout', () {
    final offenders = <String>[];

    for (final entity in Directory(
      'lib/features/quiz_plugin',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final src = entity.readAsStringSync();
      var offset = 0;
      for (final stmt in src.split(';')) {
        final line = src.substring(0, offset).split('\n').length;
        offset += stmt.length + 1;
        if (!stmt.contains('invokeMethod(')) continue;
        if (!stmt.contains('await')) continue; // 不 await 的不阻塞流程
        if (stmt.contains('.timeout(')) continue;
        if (stmt.contains('// no-timeout:')) continue;
        final cmd = RegExp(
          r"invokeMethod(?:<[^>]*>)?\(\s*\n?\s*'([^']+)'",
        ).firstMatch(stmt);
        offenders.add('${entity.path}:$line  ${cmd?.group(1) ?? '?'}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '这些通道调用没有终点，原生不回包时会永久悬挂：\n${offenders.join('\n')}\n'
          '加 .timeout(QuizVisionTimeouts.channel, onTimeout: () => null)，'
          '或写明 `// no-timeout: 原因`',
    );
  });
}
