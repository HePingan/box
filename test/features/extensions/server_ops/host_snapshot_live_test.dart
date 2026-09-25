@Tags(['live'])
library;

// 主机快照（hosts.json）真数据契约测试。
//
// 存在的理由：解析器的单测数据都是构造出来的，而真实快照里数值是活的
// （CPU 0.1~99.9 的小数、离线的机器整段字段缺失、服务端以后可能把数字写成字符串）。
// "解析器被真实数据打脸"这种事只有打真端点才看得见 —— 与运维通道的
// ops_webdav_live_test.dart 同一个口径。
//
//   HOSTS_URL=https://box.hpa888.top/hosts.json HOSTS_TOKEN=... \
//   flutter test --tags live test/features/extensions/server_ops/host_snapshot_live_test.dart
//
// 令牌不进仓库：没给环境变量时整组 skip。
import 'dart:io';

import 'package:box/features/extensions/plugins/server_ops/host_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final url = Platform.environment['HOSTS_URL'] ?? '';
  final token = Platform.environment['HOSTS_TOKEN'] ?? '';
  final missing = (url.isEmpty || token.isEmpty)
      ? '未提供 HOSTS_URL/HOSTS_TOKEN —— 跳过主机快照 live 测试'
      : null;

  group('主机快照（真服务端）', () {
    test('线上 hosts.json 能解析，在线机器字段自洽', () async {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      try {
        final req = await client.getUrl(Uri.parse('$url?token=$token'));
        final resp = await req.close();
        expect(resp.statusCode, 200, reason: '带令牌应能取到快照（404 = 令牌不对）');
        final body =
            await resp.transform(const SystemEncoding().decoder).join();
        expect(body.trim(), isNotEmpty);

        final snapshot = HostSnapshot.parse(body);
        expect(snapshot.generatedAt, isNotNull, reason: '快照必须带采样时刻');
        expect(snapshot.hosts, isNotEmpty);

        final online = snapshot.hosts.where((h) => h.online).toList();
        expect(
          online,
          isNotEmpty,
          reason: '至少应有一台在线，否则是采集链断了（不是本插件的问题，但要让测试红出来）',
        );

        for (final host in online) {
          expect(host.name, isNotEmpty);
          expect(host.cpuPercent, isNotNull, reason: '${host.id} 缺 CPU');
          expect(host.memPercent, isNotNull, reason: '${host.id} 缺内存百分比');
          expect(host.diskPercent, isNotNull, reason: '${host.id} 缺磁盘百分比');
          expect(host.memTotalBytes ?? 0, greaterThan(0));
          expect(host.diskTotalBytes ?? 0, greaterThan(0));
          // 百分比必须落在 0~100：>100 说明解析时把 used/total 弄反了。
          expect(host.memPercent!, inInclusiveRange(0, 100));
          expect(host.diskPercent!, inInclusiveRange(0, 100));
          expect(host.cpuPercent!, inInclusiveRange(0, 100));
        }

        // 离线机器的其余字段必须是 null（界面据此显示"离线"，不是 0%）。
        for (final host in snapshot.hosts.where((h) => !h.online)) {
          expect(host.cpuPercent, isNull, reason: '${host.id} 离线却带着 CPU 值');
        }

        // 290 A7 的扩展字段（盘 IO / Swap / 温度）：**允许缺**（289 老快照、
        // 云主机没有温度传感器都是常态），但给出来了就必须是合理值——
        // 温度 0 那种"假读数"已在解析层滤成 null，这里再兜一道。
        for (final host in online) {
          for (final rate in [
            host.diskReadBytesPerSec,
            host.diskWriteBytesPerSec,
          ]) {
            if (rate != null) {
              expect(rate, greaterThanOrEqualTo(0), reason: '${host.id} 盘 IO 速率不能为负');
            }
          }
          final celsius = host.temperatureC;
          if (celsius != null) {
            expect(celsius, inInclusiveRange(0, 150), reason: '${host.id} 温度不在合理范围');
          }
          final swapTotal = host.swapTotalBytes;
          if (swapTotal != null && swapTotal > 0) {
            expect(
              host.swapPercent,
              isNotNull,
              reason: '${host.id} 有 swap 却没算出百分比（used/total 应能反算）',
            );
            expect(host.swapPercent!, inInclusiveRange(0, 100));
          }
        }
      } finally {
        client.close(force: true);
      }
    });
  }, skip: missing);
}
