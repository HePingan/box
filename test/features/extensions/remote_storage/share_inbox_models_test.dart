// 分享文件模型（286 P3）：跨进程传来的结构一律不采信，逐条校验。
import 'package:box/features/extensions/plugins/remote_storage/domain/share_inbox_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
