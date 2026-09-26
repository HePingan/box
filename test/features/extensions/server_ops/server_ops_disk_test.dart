// 磁盘卡片的纯逻辑用例。
//
// 最要紧的一条：`du -h` 给的是 "9.0M" / "10G" 这种**字符串**，按字符串排序会把
// 9.0M 排到 10G 前面（'9' > '1'）—— 屏幕上看着挺正常，于是没人发现"最大的那个"
// 被埋在下面。这条断言就是为它写的。

import 'package:box/features/extensions/plugins/server_ops/server_ops_api_client.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_disk.dart';
import 'package:flutter_test/flutter_test.dart';

OpsDiskRow _row(String size, String path) => OpsDiskRow(size: size, path: path);

void main() {
  group('du 的人类可读串 → 字节', () {
    test('常见写法都对', () {
      expect(opsParseHumanSize('1.2G'), 1288490189);
      expect(opsParseHumanSize('512M'), 536870912);
      expect(opsParseHumanSize('4.0K'), 4096);
      expect(opsParseHumanSize('123'), 123);
      expect(opsParseHumanSize('1.5T'), 1649267441664);
      expect(opsParseHumanSize('2.0P'), 2251799813685248);
    });

    test('大小写、空格、带 iB 都认（du 在不同机器上写法不同）', () {
      expect(opsParseHumanSize(' 1.2g '), opsParseHumanSize('1.2G'));
      expect(opsParseHumanSize('512MiB'), opsParseHumanSize('512M'));
    });

    test('认不出来返回 0（不抛、不丢行）——一行脏数据不该让整张卡片打不开', () {
      expect(opsParseHumanSize(''), 0);
      expect(opsParseHumanSize('abc'), 0);
      expect(opsParseHumanSize('-5M'), 0);
      expect(opsParseHumanSize('G'), 0);
    });
  });

  group('按占用倒排', () {
    test('10G 在 9.0M 前面（按字符串排会反过来）', () {
      final sorted = opsSortDiskRowsBySize([
        _row('9.0M', '/a'),
        _row('10G', '/b'),
        _row('1.0K', '/c'),
      ]);
      expect(sorted.map((r) => r.path).toList(), ['/b', '/a', '/c']);
    });

    test('同样大小时按路径定序（顺序稳定，界面不跳）', () {
      final sorted = opsSortDiskRowsBySize([
        _row('1G', '/z'),
        _row('1G', '/a'),
      ]);
      expect(sorted.map((r) => r.path).toList(), ['/a', '/z']);
    });

    test('不改原列表（服务端那份的先后顺序另有用途）', () {
      final rows = [_row('1K', '/a'), _row('1G', '/b')];
      opsSortDiskRowsBySize(rows);
      expect(rows.first.path, '/a');
    });
  });

  group('占比条', () {
    test('分母是最大的那一项，不是它们的和', () {
      final rows = [_row('10G', '/big'), _row('1G', '/small')];
      expect(opsDiskBarShare(opsParseHumanSize('10G'), rows), 1.0);
      expect(opsDiskBarShare(opsParseHumanSize('1G'), rows), closeTo(0.1, 0.001));
    });

    test('全是 0 / 空列表不炸（不返回 NaN，界面画得出来）', () {
      expect(opsDiskBarShare(0, [_row('0', '/a')]), 0);
      expect(opsDiskBarShare(100, const []), 0);
    });
  });

  group('上一级', () {
    test('普通路径', () {
      expect(opsParentPath('/var/log'), '/var');
      expect(opsParentPath('/var'), '/');
      expect(opsParentPath('/var/log/'), '/var');
    });

    test('到根就没了（界面据此禁用按钮）', () {
      expect(opsParentPath('/'), isNull);
      expect(opsParentPath(''), isNull);
    });
  });

  group('清理文案', () {
    test('清出东西要说人话', () {
      expect(opsCleanupResultText('apt', 80949248), contains('77.2 MB'));
    });

    test('没清出东西要说"本来就很干净"，不能说"清出 0 B"', () {
      expect(opsCleanupResultText('journal', 0), contains('没什么可清'));
    });

    test('字节格式', () {
      expect(opsFormatBytes(512), '512 B');
      expect(opsFormatBytes(1024), '1.0 KB');
      expect(opsFormatBytes(5 * 1024 * 1024 * 1024), '5.0 GB');
      expect(opsFormatBytes(150 * 1024 * 1024), '150 MB');
    });
  });

  test('清理项固定这三类（服务端也只认这三个 key）', () {
    expect(kOpsCleanupModes.map((m) => m.key).toList(), ['journal', 'tmp', 'apt']);
  });
}
