// 分享文件模型（286 P3）：跨进程传来的结构一律不采信，逐条校验。
import 'package:box/features/extensions/plugins/remote_storage/domain/share_inbox_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 诚实计数（287 P2）的用例在文件末尾，这里挂上去。
  _honestCounts();
  group('tryParse', () {
    test('正常条目：字段齐全', () {
      final f = SharedInboxFile.tryParse(<Object?, Object?>{
        'path': '/data/cache/shared_inbox/1_a.jpg',
        'name': 'a.jpg',
        'sizeBytes': 1234,
        'mimeType': 'image/jpeg',
      })!;
      expect(f.path, '/data/cache/shared_inbox/1_a.jpg');
      expect(f.name, 'a.jpg');
      expect(f.sizeBytes, 1234);
      expect(f.mimeType, 'image/jpeg');
      expect(f.isVideo, isFalse);
    });

    test('视频识别', () {
      final f = SharedInboxFile.tryParse(<Object?, Object?>{
        'path': '/x/v.mp4',
        'name': 'v.mp4',
        'mimeType': 'video/mp4',
      })!;
      expect(f.isVideo, isTrue);
    });

    test('缺 path / path 为空 / 缺 name → 判为坏数据', () {
      expect(SharedInboxFile.tryParse(null), isNull);
      expect(SharedInboxFile.tryParse('not a map'), isNull);
      expect(SharedInboxFile.tryParse(<Object?, Object?>{'name': 'a.jpg'}), isNull);
      expect(
        SharedInboxFile.tryParse(
            <Object?, Object?>{'path': '', 'name': 'a.jpg'}),
        isNull,
      );
      expect(
        SharedInboxFile.tryParse(
            <Object?, Object?>{'path': '/x', 'name': ''}),
        isNull,
      );
    });

    test('sizeBytes 缺失/负数/类型不对 → 归 0，不整条作废', () {
      for (final raw in <Object?>[null, -5, 'x', 3.5]) {
        final f = SharedInboxFile.tryParse(<Object?, Object?>{
          'path': '/x/a.jpg',
          'name': 'a.jpg',
          'sizeBytes': raw,
        });
        expect(f, isNotNull);
        expect(f!.sizeBytes, 0);
      }
    });

    test('mimeType 缺失 → 空串（界面上按图片图标处理）', () {
      final f = SharedInboxFile.tryParse(<Object?, Object?>{
        'path': '/x/a',
        'name': 'a',
      })!;
      expect(f.mimeType, '');
      expect(f.isVideo, isFalse);
    });
  });

  group('parseList', () {
    test('非列表 → 空', () {
      expect(SharedInboxFile.parseList(null), isEmpty);
      expect(SharedInboxFile.parseList('x'), isEmpty);
      expect(SharedInboxFile.parseList(<Object?, Object?>{}), isEmpty);
    });

    test('混着坏数据：好的留下，坏的跳过（不整份作废）', () {
      final files = SharedInboxFile.parseList(<Object?>[
        <Object?, Object?>{'path': '/x/1.jpg', 'name': '1.jpg'},
        'bad',
        <Object?, Object?>{'name': 'no-path.jpg'},
        <Object?, Object?>{'path': '/x/2.mp4', 'name': '2.mp4', 'mimeType': 'video/mp4'},
      ]);
      expect(files.map((f) => f.name), <String>['1.jpg', '2.mp4']);
      expect(files.last.isVideo, isTrue);
    });

    test('同步反射：toString 不炸（排查日志里会打）', () {
      final f = SharedInboxFile.tryParse(<Object?, Object?>{
        'path': '/x/a.jpg',
        'name': 'a.jpg',
        'sizeBytes': 1,
        'mimeType': 'image/jpeg',
      })!;
      expect(f.toString(), contains('a.jpg'));
    });
  });
}

/// 诚实计数（287 P2）：分享里几个、收到几个、丢了哪几个、为什么。
void _honestCounts() {
  group('SkippedShare', () {
    test('解析与文案', () {
      final s = SkippedShare.tryParse(<String, Object?>{
        'name': 'big.mov',
        'reason': 'tooLarge',
      })!;
      expect(s.displayName, 'big.mov');
      expect(s.reasonLabel, '超过单文件大小上限');
    });

    test('没有名字给占位；坏结构不采信', () {
      expect(
        SkippedShare.tryParse(<String, Object?>{'reason': 'unreadable'})!
            .displayName,
        '未命名文件',
      );
      expect(SkippedShare.tryParse(<String, Object?>{'name': 'x'}), isNull);
      expect(SkippedShare.tryParse('nope'), isNull);
    });

    test('不认识的原因也给一句能看的话（不暴露代号）', () {
      expect(shareSkipReasonLabel('weird'), '没有收到');
      expect(shareSkipReasonLabel('tooMany'), '超过单次数量上限');
      expect(shareSkipReasonLabel('unsupported'), '类型不支持');
      expect(shareSkipReasonLabel('unreadable'), '读不出来');
    });
  });

  group('ShareInboxBatch.parse', () {
    Object? file(String name) => <String, Object?>{
          'path': '/data/cache/shared_inbox/$name',
          'name': name,
          'sizeBytes': 10,
          'mimeType': 'image/jpeg',
        };

    test('新形状：files/total/skipped 都认', () {
      final batch = ShareInboxBatch.parse(<String, Object?>{
        'files': <Object?>[file('a.jpg')],
        'total': 3,
        'received': 1,
        'skipped': <Object?>[
          <String, Object?>{'name': 'b.mov', 'reason': 'tooLarge'},
        ],
      });
      expect(batch.files, hasLength(1));
      expect(batch.total, 3);
      expect(batch.received, 1);
      expect(batch.skipped.single.displayName, 'b.mov');
      expect(batch.hasLosses, isTrue);
    });

    test('旧形状（裸列表）：当成 total == received、没有丢失', () {
      final batch = ShareInboxBatch.parse(<Object?>[file('a.jpg'), file('b.jpg')]);
      expect(batch.received, 2);
      expect(batch.total, 2);
      expect(batch.skipped, isEmpty);
      expect(batch.hasLosses, isFalse);
    });

    test('计数不自相矛盾：total 小于"收到 + 跳过"时按后者抬上来', () {
      final batch = ShareInboxBatch.parse(<String, Object?>{
        'files': <Object?>[file('a.jpg')],
        'total': 0,
        'skipped': <Object?>[
          <String, Object?>{'name': 'b.mov', 'reason': 'tooLarge'},
        ],
      });
      expect(batch.total, 2);
    });

    test('结构完全不对 → 空包（不抛）', () {
      expect(ShareInboxBatch.parse(null).isEmpty, isTrue);
      expect(ShareInboxBatch.parse('nope').isEmpty, isTrue);
      expect(ShareInboxBatch.parse(<String, Object?>{}).isEmpty, isTrue);
    });

    test('summaryLabel：没丢就说收到几个；丢了就说清总/收/原因分布', () {
      expect(
        ShareInboxBatch.parse(<Object?>[file('a.jpg')]).summaryLabel,
        '收到 1 个分享文件',
      );
      final lost = ShareInboxBatch.parse(<String, Object?>{
        'files': <Object?>[file('a.jpg')],
        'total': 4,
        'skipped': <Object?>[
          <String, Object?>{'name': 'b.mov', 'reason': 'tooLarge'},
          <String, Object?>{'name': 'c.mov', 'reason': 'tooLarge'},
          <String, Object?>{'name': 'd.png', 'reason': 'tooMany'},
        ],
      });
      expect(lost.summaryLabel, contains('分享 4 个，收到 1 个'));
      expect(lost.summaryLabel, contains('2 个超过单文件大小上限'));
      expect(lost.summaryLabel, contains('1 个超过单次数量上限'));
    });
  });
}
