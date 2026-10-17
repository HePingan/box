import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 源码级闸门：启动路径上不许有「纯诊断」的阻塞调用。
///
/// 为什么需要它：`AppBootstrap.initialize()` 返回之前，`main.dart` 只画一个
/// 转圈（`_bootstrap == null` 那条分支）。也就是说**里面每一个 await 都是用户
/// 白等的时间**。诊断通道（`invokeMethod('ready')` + 视口诊断 attach）是纯增强
/// 能力：它晚 50ms 接上，用户完全无感；但它排在首帧前，就是每个用户每次启动
/// 都要多等一次平台往返。
///
/// 这类回归没有任何运行期测试会发现 —— 把它改回 `await _attachWindowDiagnostics()`
/// 全量测试照样全绿，只有真机上"启动慢了一点点"。所以用源码顺序锁住。
void main() {
  late String bootstrapSource;

  setUpAll(() {
    bootstrapSource = File('lib/app/app_bootstrap.dart').readAsStringSync();
  });

  test('诊断通道不在启动关键路径上 await', () {
    expect(
      bootstrapSource.contains('await _attachWindowDiagnostics()'),
      isFalse,
      reason: '诊断是纯增强能力，不能 blocking 冷启动；'
          '要用 _scheduleWindowDiagnostics() 放到首帧后',
    );
  });

  test('诊断通道仍然被接上（没有被顺手删掉）', () {
    expect(
      bootstrapSource.contains('_scheduleWindowDiagnostics()'),
      isTrue,
      reason: '推迟 ≠ 不做：删掉就不会再收到原生窗口事件了',
    );
    expect(
      bootstrapSource.contains('addPostFrameCallback'),
      isTrue,
      reason: '必须放在首帧之后，不能阻塞冷启动',
    );
  });

  test('诊断注册仍排在 logger 之后（否则早期事件会落空）', () {
    final loggerAt = bootstrapSource.indexOf('await _initLogger()');
    final scheduleAt = bootstrapSource.indexOf('_scheduleWindowDiagnostics()');

    expect(loggerAt, greaterThan(-1));
    expect(scheduleAt, greaterThan(-1));
    expect(
      scheduleAt,
      greaterThan(loggerAt),
      reason: '原生会回放引擎就绪前缓冲的事件，AppLogger 没 init 就落空了',
    );
  });

  test('诊断报告头也不许在启动关键路径上 await', () {
    // 只看非注释行：注释里会引用旧写法（"以前这里是 await ..."），
    // 直接 contains 会被自己的说明文字骗到。
    final codeLines = bootstrapSource
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    // 只看启动主流程：`initialize()` 的函数体。
    final initStart = codeLines.indexOf('static Future<AppBootstrapResult> initialize()');
    final initEnd = codeLines.indexOf('static Future<void> _initLogger()');
    final initBody = codeLines.substring(initStart, initEnd);
    expect(
      initBody.contains('DiagnosticHeader.prime()'),
      isFalse,
      reason: 'prime() 走 PackageInfo 平台通道且带 2 秒超时，'
          '不该让每次冷启动为「复制诊断报告」排队；要用 unawaited 放后台',
    );
    expect(
      bootstrapSource.contains('_primeDiagnosticHeader'),
      isTrue,
      reason: '推迟 ≠ 不做：删掉的话复制报告会落到占位值',
    );
  });
}
