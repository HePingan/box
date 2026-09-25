// 本目录筛选的纯逻辑（287 D1）：名称 + 类型 + 大小 + 时间，全在本地判定。
//
// 两条定死的规矩：① 结构化条件（类型/大小/时间）**只作用于文件，目录一律保留**
// （否则筛"图片"时连目录都看不见，往下走的路就堵死了）；
// ② 大小/时间未知的条目不放进任何具体档位 —— "不知道"不当"是"。
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:flutter_test/flutter_test.dart';

RemoteStorageEntry _file(
  String name, {
  int? size,
  DateTime? modifiedAt,
}) =>
    RemoteStorageEntry(
      name: name,
      path: name,
      isDirectory: false,
      size: size,
      modifiedAt: modifiedAt,
    );

RemoteStorageEntry _dir(String name) => RemoteStorageEntry(
      name: name,
      path: name,
      isDirectory: true,
    );

void main() {
  final now = DateTime(2026, 9, 25, 12, 0);

  group('条件本身', () {
    test('isIdle / hasStructured / activeCount / 摘要', () {
      expect(const RemoteEntryFilter().isIdle, isTrue);
      expect(const RemoteEntryFilter().activeCount, 0);

      const onlyName = RemoteEntryFilter(query: ' 报告 ');
      expect(onlyName.isIdle, isFalse);
      expect(onlyName.hasStructured, isFalse, reason: '名称不算结构化条件');
      expect(onlyName.activeCount, 1);

      const structured = RemoteEntryFilter(
        kind: RemoteEntryKindFilter.image,
        size: RemoteEntrySizeFilter.under1m,
        time: RemoteEntryTimeFilter.today,
      );
      expect(structured.activeCount, 3);
      expect(structured.structuredLabel, '图片 · 小于 1 MB · 今天');

      expect(
        structured.copyWith(time: RemoteEntryTimeFilter.all).structuredLabel,
        '图片 · 小于 1 MB',
      );
    });

    test('大小档位左闭右开、相邻不重叠', () {
      const mb = 1024 * 1024;
      expect(RemoteEntrySizeFilter.under1m.matches(mb - 1), isTrue);
      expect(RemoteEntrySizeFilter.under1m.matches(mb), isFalse);
      expect(RemoteEntrySizeFilter.from1to10m.matches(mb), isTrue);
      expect(RemoteEntrySizeFilter.from1to10m.matches(10 * mb), isFalse);
      expect(RemoteEntrySizeFilter.from10to100m.matches(10 * mb), isTrue);
      expect(RemoteEntrySizeFilter.from10to100m.matches(100 * mb), isFalse);
      expect(RemoteEntrySizeFilter.over100m.matches(100 * mb), isTrue);
      expect(RemoteEntrySizeFilter.all.matches(null), isTrue);
      expect(RemoteEntrySizeFilter.under1m.matches(null), isFalse,
          reason: '大小未知不放进具体档位');
    });

    test('时间档位按本机时区的当天起点算', () {
      final todayStart = DateTime(2026, 9, 25, 12, 0);
      expect(RemoteEntryTimeFilter.today.matches(todayStart, now), isTrue);
      expect(
        RemoteEntryTimeFilter.today.matches(DateTime(2026, 9, 24, 23, 59), now),
        isFalse,
      );
      expect(
        RemoteEntryTimeFilter.last7days.matches(now.subtract(const Duration(days: 6)), now),
        isTrue,
      );
      expect(
        RemoteEntryTimeFilter.last7days.matches(now.subtract(const Duration(days: 8)), now),
        isFalse,
      );
      expect(RemoteEntryTimeFilter.last30days.matches(null, now), isFalse,
          reason: '改时间未知不放进具体档位');
    });
  });

  group('筛选结果', () {
    test('没筛就原样返回（连列表都不重建）', () {
      final entries = <RemoteStorageEntry>[_file('a.jpg'), _dir('相册')];
      expect(
        identical(
          filterRemoteEntriesAdvanced(entries, const RemoteEntryFilter()),
          entries,
        ),
        isTrue,
      );
    });

    test('类型：只留对应文件，目录仍在', () {
      final entries = <RemoteStorageEntry>[
        _file('照片.JPG'),
        _file('视频.mp4'),
        _file('歌.mp3'),
        _file('笔记.txt'),
        _file('报告.pdf'),
        _file('包.zip'),
        _dir('相册'),
      ];
      List<String> namesOf(RemoteEntryKindFilter kind) => filterRemoteEntriesAdvanced(
            entries,
            RemoteEntryFilter(kind: kind),
          ).map((e) => e.name).toList();

      expect(namesOf(RemoteEntryKindFilter.image), <String>['照片.JPG', '相册'],
          reason: '大小写不敏感，且目录必须留下（否则没法往下走）');
      expect(namesOf(RemoteEntryKindFilter.video), <String>['视频.mp4', '相册']);
      expect(namesOf(RemoteEntryKindFilter.audio), <String>['歌.mp3', '相册']);
      expect(namesOf(RemoteEntryKindFilter.text), <String>['笔记.txt', '相册'],
          reason: '文本档只含真·文本；pdf 归"其它"（分类沿用既有 remoteEntryKind）');
      expect(
        namesOf(RemoteEntryKindFilter.other),
        <String>['报告.pdf', '包.zip', '相册'],
        reason: 'pdf/doc 这类归"其它"——界面标签写的是"文本"，不冒充"文档"',
      );
      expect(namesOf(RemoteEntryKindFilter.all).length, 7);
    });

    test('大小 + 名称是"与"关系，目录仍不受大小限制', () {
      final entries = <RemoteStorageEntry>[
        _file('大图.png', size: 200 * 1024 * 1024),
        _file('小图.png', size: 100),
        _file('大视频.mp4', size: 200 * 1024 * 1024),
        _dir('相册'),
      ];
      final got = filterRemoteEntriesAdvanced(
        entries,
        const RemoteEntryFilter(
          query: 'png',
          size: RemoteEntrySizeFilter.over100m,
        ),
      );
      expect(got.map((e) => e.name), <String>['大图.png'],
          reason: '名称 + 大小都要满足；目录名字不含 png 所以这次也不出现');
    });

    test('时间：今天 / 最近 7 天', () {
      final entries = <RemoteStorageEntry>[
        _file('今天.jpg', modifiedAt: now.subtract(const Duration(hours: 2))),
        _file('上周.jpg', modifiedAt: now.subtract(const Duration(days: 3))),
        _file('上古.jpg', modifiedAt: now.subtract(const Duration(days: 90))),
        _file('没时间.jpg'),
      ];
      expect(
        filterRemoteEntriesAdvanced(
          entries,
          const RemoteEntryFilter(time: RemoteEntryTimeFilter.today),
          now: now,
        ).map((e) => e.name),
        <String>['今天.jpg'],
      );
      expect(
        filterRemoteEntriesAdvanced(
          entries,
          const RemoteEntryFilter(time: RemoteEntryTimeFilter.last7days),
          now: now,
        ).map((e) => e.name),
        <String>['今天.jpg', '上周.jpg'],
      );
    });

    test('旧函数与新的"只有名称"等价（向后兼容）', () {
      final entries = <RemoteStorageEntry>[
        _file('报告 2024.pdf'),
        _file('报告 2025.pdf'),
        _dir('报告目录'),
        _file('其它.txt'),
      ];
      final oldWay = filterRemoteEntries(entries, '报告 2024');
      final newWay = filterRemoteEntriesAdvanced(
        entries,
        const RemoteEntryFilter(query: '报告 2024'),
      );
      expect(newWay.map((e) => e.name), oldWay.map((e) => e.name));
      expect(newWay.map((e) => e.name), <String>['报告 2024.pdf']);
    });
  });
}
