// 传输限速原语（285 P2）：判定是纯函数，不需要真等时间。
import 'package:box/features/extensions/plugins/remote_storage/domain/transfer_throttle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lag：按"已传字节 vs 已用时间"算还需补等多久', () {
    test('跑得比目标快 → 需要补等；跑得慢 → 不用等', () {
      final t = TransferThrottle(1000); // 1000 B/s
      // 传了 2000 字节只用了 1s，目标应花 2s → 还差 1s
      expect(t.lag(2000, const Duration(seconds: 1)), const Duration(seconds: 1));
      // 传了 500 字节用了 1s，目标 0.5s → 已经慢于目标，不用等
      expect(t.lag(500, const Duration(seconds: 1)), Duration.zero);
    });

    test('刚好追上目标 → 不用等（边界）', () {
      final t = TransferThrottle(1024);
      expect(t.lag(1024, const Duration(seconds: 1)), Duration.zero);
    });

    test('没传字节 / 速率为 0 → 不用等（不产生负延迟）', () {
      expect(TransferThrottle(1000).lag(0, const Duration(seconds: 5)), Duration.zero);
      expect(TransferThrottle(1000).lag(-1, Duration.zero), Duration.zero);
    });

    test('大文件下不会因为整数除法而漂移', () {
      final t = TransferThrottle(1000000); // 1 MB/s
      // 传了 10MB 用了 5s，目标 10s → 还差 5s
      expect(t.lag(10 * 1000 * 1000, const Duration(seconds: 5)),
          const Duration(seconds: 5));
    });
  });

  group('limit：必要时才等', () {
    test('超前时等、落后时不等', () async {
      final waits = <Duration>[];
      final t = TransferThrottle(1000, wait: (d) async => waits.add(d));
      await t.limit(2000, const Duration(seconds: 1)); // 超前 → 等 1s
      await t.limit(500, const Duration(seconds: 3)); // 落后 → 不等
      expect(waits, [const Duration(seconds: 1)]);
    });
  });
}
