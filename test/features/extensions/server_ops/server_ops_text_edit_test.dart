// 文件编辑的纯逻辑：能不能编辑 / 怎么还原原风格 / 备份命名与清理 / 哪些文件要多确认。
//
// 这些判断错了后果很实在（把 GBK 配置存成乱码、覆盖别人刚改的文件、改坏 sshd
// 把自己锁在门外），所以每条都得能对着断言看。

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/extensions/plugins/server_ops/server_ops_text_edit.dart';

Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('能不能当文本编辑', () {
    test('有 NUL 字节 → 判二进制', () {
      expect(opsLooksBinary(Uint8List.fromList([104, 105, 0, 33])), isTrue);
      expect(opsLooksBinary(bytesOf('#!/bin/sh\necho hi\n')), isFalse);
    });

    test('前 8KB 之外的 NUL 不算（只看开头，够用且快）', () {
      final big = Uint8List(9000);
      big.fillRange(0, 9000, 65); // 'A'
      big[8500] = 0;
      expect(opsLooksBinary(big), isFalse);
    });

    test('UTF-8 合法性：中文可以，GBK 字节不行', () {
      expect(opsIsValidUtf8(bytesOf('你好，世界\n')), isTrue);
      // GBK 的「你」= 0xC4 0xE3：在 UTF-8 里是非法序列
      expect(opsIsValidUtf8(Uint8List.fromList([0xC4, 0xE3, 0xBA, 0xC3])), isFalse);
    });
  });

  group('按原风格回写', () {
    test('LF 文件：结尾换行保留，不加 BOM', () {
      final style = OpsTextStyle.detect(bytesOf('a\n'), 'a\n');
      expect(style.bom, isFalse);
      expect(style.crlf, isFalse);
      expect(style.trailingNewline, isTrue);
      final out = opsEncodeWithStyle('a\nb', style);
      expect(utf8.decode(out), 'a\nb\n', reason: '结尾换行要补回来');
    });

    test('有 BOM 的文件：BOM 原样带回去', () {
      final raw = Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode('a\n')]);
      final style = OpsTextStyle.detect(raw, 'a\n');
      expect(style.bom, isTrue);
      final out = opsEncodeWithStyle('a\n', style);
      expect(out.sublist(0, 3), <int>[0xEF, 0xBB, 0xBF]);
    });

    test('CRLF 文件：换行还原成 CRLF，且不会变成 \\r\\r\\n', () {
      final style = OpsTextStyle.detect(bytesOf('a\r\nb\r\n'), 'a\r\nb\r\n');
      expect(style.crlf, isTrue);
      final out = opsEncodeWithStyle('a\nb\n', style);
      expect(utf8.decode(out), 'a\r\nb\r\n');
      // 编辑器里如果混进了 CRLF（粘贴），也不能双写
      final out2 = opsEncodeWithStyle('a\r\nb\n', style);
      expect(utf8.decode(out2), 'a\r\nb\r\n');
    });

    test('原来没有结尾换行 → 也不会硬补一个', () {
      final style = OpsTextStyle.detect(bytesOf('a\nb'), 'a\nb');
      expect(style.trailingNewline, isFalse);
      expect(utf8.decode(opsEncodeWithStyle('a\nb', style)), 'a\nb');
    });
  });

  group('备份命名与清理', () {
    test('备份名带时间戳，原名可反推', () {
      final name = opsBackupName('/etc/hosts', DateTime(2026, 9, 26, 15, 0, 1));
      expect(name, '/etc/hosts.box-bak-20260926-150001');
      expect(opsIsBackupName('hosts.box-bak-20260926-150001'), isTrue);
      expect(opsIsBackupName('hosts'), isFalse);
      expect(opsOriginalNameFromBackup('hosts.box-bak-20260926-150001'), 'hosts');
    });

    test('只留最近 3 份：返回该删的那些（最新在前排）', () {
      final names = <String>[
        'a.box-bak-20260926-100000',
        'a.box-bak-20260926-120000',
        'a.box-bak-20260926-110000',
        'a.box-bak-20260926-090000',
      ];
      expect(
        opsBackupsToPrune(names),
        <String>['a.box-bak-20260926-090000'],
        reason: '最新的三份是 12/11/10 点，9 点那份该删',
      );
      expect(opsBackupsToPrune(names, keep: 10), isEmpty);
    });
  });

  group('会把自己锁在门外的文件，保存前要多一道确认', () {
    test('锁门名单上的都提醒', () {
      expect(opsLockoutWarning('/etc/ssh/sshd_config'), isNotNull);
      expect(opsLockoutWarning('/etc/fstab'), isNotNull);
      expect(opsLockoutWarning('/etc/shadow'), isNotNull);
      expect(opsLockoutWarning('/root/.ssh/authorized_keys'), isNotNull);
      expect(opsLockoutWarning('/www/server/nginx/conf/box-ops.htpasswd'), isNotNull);
      expect(
        opsLockoutWarning('/www/server/panel/vhost/nginx/box.hpa888.top.conf'),
        isNotNull,
      );
      expect(opsLockoutWarning('/etc/systemd/system/box-ops-api.service'), isNotNull);
      expect(opsLockoutWarning('/etc/netplan/01-netcfg.yaml'), isNotNull);
    });

    test('日常要手改的普通文件不打扰（hosts 就在这儿）', () {
      expect(opsLockoutWarning('/etc/hosts'), isNull);
      expect(opsLockoutWarning('/root/box/README.md'), isNull);
      expect(opsLockoutWarning('/www/wwwroot/app/index.html'), isNull);
      expect(opsLockoutWarning('/tmp/box-gate-probe.txt'), isNull);
      expect(opsLockoutWarning('/root/box/lib/main.dart'), isNull);
    });
  });
}
