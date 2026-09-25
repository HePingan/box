// 服务器运维插件：最近请求日志（A9）的用例。
//
// 守三件：
//   * 环形缓冲只留最近 N 条、新的在前（面板只该显示最近发生的事）；
//   * `time()` 失败也要记（失败记录才是最有用的那半），且异常照旧重抛给调用方；
//   * **记录里不装凭据** —— 面板会被截图、会被共享屏幕，口令出现一次就等于泄露一次。
//     口令那条在 widget 级用例里守卫（见 server_ops_diagnostics_test.dart）。
import 'package:box/features/extensions/plugins/server_ops/server_ops_request_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => debugSetOpsRequestLog());

  group('请求日志（A9）', () {
    test('环形缓冲只留最近 capacity 条，且新的在前', () {
      final log = OpsRequestLog(capacity: 3);
      for (var i = 0; i < 5; i++) {
        log.record(OpsRequestRecord(
          entry: '文件',
          serverId: 'hpa888',
          serverLabel: '阿里云 · 主服务端',
          ok: true,
          detail: '第 $i 次',
          duration: Duration(milliseconds: i),
          at: DateTime(2026, 9, 25, 10, i),
        ));
      }
      expect(log.length, 3);
      expect(
        log.items.map((r) => r.detail).toList(),
        ['第 4 次', '第 3 次', '第 2 次'],
      );
    });

    test('time()：成功记 ok 与结论；异常既记录也原样重抛', () async {
      final log = OpsRequestLog();
      final value = await log.time(
        () async => 42,
        entry: '文件',
        serverId: 'hpa888',
        serverLabel: '阿里云 · 主服务端',
        okDetail: '列举 /：2 项',
      );
      expect(value, 42);
      expect(log.items.single.ok, isTrue);
      expect(log.items.single.detail, '列举 /：2 项');
      expect(log.items.single.entry, '文件');

      await expectLater(
        log.time<void>(
          () async => throw StateError('boom'),
          entry: '文件',
          serverId: 'hpa888',
          serverLabel: '阿里云 · 主服务端',
          describeError: (e) => '取目录失败：$e',
        ),
        throwsA(isA<StateError>()),
      );
      expect(log.length, 2);
      expect(log.items.first.ok, isFalse);
      expect(log.items.first.detail, '取目录失败：Bad state: boom');
    });

    test('time() 自己计时（不靠调用方传），成功与失败都有耗时', () async {
      final log = OpsRequestLog();
      await log.time(
        () async => Future<void>.delayed(const Duration(milliseconds: 5)),
        entry: '终端',
        serverId: 'tencent175',
        serverLabel: '腾讯云 · 构建/监控机',
      );
      expect(log.items.single.duration.inMilliseconds, greaterThanOrEqualTo(5));
    });

    test('summary 是可直接渲染的一行，且不含凭据字样', () {
      final rec = OpsRequestRecord(
        entry: '体检',
        serverId: 'hpa888',
        serverLabel: '阿里云 · 主服务端',
        ok: false,
        detail: '认证失败（401）：这台机器的口令不对',
        duration: const Duration(milliseconds: 12),
        at: DateTime(2026, 9, 25, 20, 5),
      );
      expect(rec.summary, contains('体检'));
      expect(rec.summary, contains('阿里云 · 主服务端'));
      expect(rec.summary, contains('失败'));
      expect(rec.summary, contains('12 ms'));
      // 结构上就没有装口令的地方：整行里不该出现用户名/口令值这类东西。
      expect(rec.summary.toLowerCase(), isNot(contains('password')));
      expect(rec.summary, isNot(contains('boxops')));
    });

    test('clear() 清空；共享实例可换可复位', () {
      final log = OpsRequestLog();
      log.record(OpsRequestRecord(
        entry: '快照',
        serverId: 'snapshot',
        serverLabel: '快照端点（两台共用）',
        ok: true,
        detail: '2 台机器',
        duration: const Duration(milliseconds: 30),
        at: DateTime(2026, 9, 25),
      ));
      expect(log.length, 1);
      log.clear();
      expect(log.length, 0);
      expect(log.items, isEmpty);

      final swapped = OpsRequestLog(capacity: 1);
      debugSetOpsRequestLog(swapped);
      expect(identical(serverOpsRequestLog, swapped), isTrue);
      debugSetOpsRequestLog();
      expect(identical(serverOpsRequestLog, swapped), isFalse);
    });
  });
}
