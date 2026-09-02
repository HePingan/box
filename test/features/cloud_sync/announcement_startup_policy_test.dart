import 'package:box/features/cloud_sync/data/announcement_service.dart';
import 'package:box/features/cloud_sync/domain/announcement_startup_policy.dart';
import 'package:box/features/cloud_sync/domain/cloud_sync_models.dart';
import 'package:flutter_test/flutter_test.dart';

AnnouncementEntry entry(
  String id, {
  String level = 'info',
  bool pinned = false,
  DateTime? at,
}) {
  return AnnouncementEntry(
    id: id,
    title: 't-$id',
    body: 'b-$id',
    level: level,
    publishedAt: at ?? DateTime(2026, 1, 1),
    pinned: pinned,
    linkUrl: '',
  );
}

void main() {
  group('启动是否该拉公告', () {
    test('从未拉过 → 拉', () {
      expect(
        AnnouncementStartupPolicy.shouldFetch(
          lastFetchedAt: null,
          now: DateTime(2026, 1, 1),
        ),
        isTrue,
      );
    });

    test('距上次不足最小间隔 → 跳过，避免每次冷启动都打网络', () {
      final last = DateTime(2026, 1, 1, 12, 0);
      expect(
        AnnouncementStartupPolicy.shouldFetch(
          lastFetchedAt: last,
          now: last.add(const Duration(hours: 5, minutes: 59)),
        ),
        isFalse,
      );
    });

    test('恰好等于最小间隔 → 拉（边界含等号）', () {
      final last = DateTime(2026, 1, 1, 12, 0);
      expect(
        AnnouncementStartupPolicy.shouldFetch(
          lastFetchedAt: last,
          now: last.add(AnnouncementStartupPolicy.minFetchInterval),
        ),
        isTrue,
      );
    });

    test('超过最小间隔 → 拉', () {
      final last = DateTime(2026, 1, 1, 12, 0);
      expect(
        AnnouncementStartupPolicy.shouldFetch(
          lastFetchedAt: last,
          now: last.add(const Duration(hours: 6, minutes: 1)),
        ),
        isTrue,
      );
    });

    test('本地时钟回拨导致 now 早于上次 → 也要拉，不能永久卡死', () {
      final last = DateTime(2026, 6, 1, 12, 0);
      expect(
        AnnouncementStartupPolicy.shouldFetch(
          lastFetchedAt: last,
          now: DateTime(2026, 1, 1),
        ),
        isTrue,
      );
    });
  });

  group('未读红点', () {
    test('有未读 → 亮，且计数只算未读', () {
      final state = AnnouncementState(
        items: [entry('a'), entry('b'), entry('c')],
        readIds: {'a'},
        fetchedAt: DateTime(2026, 1, 1),
        fromCache: true,
      );
      expect(AnnouncementStartupPolicy.unreadCount(state), 2);
      expect(AnnouncementStartupPolicy.hasUnread(state), isTrue);
    });

    test('全部已读 → 不亮', () {
      final state = AnnouncementState(
        items: [entry('a'), entry('b')],
        readIds: {'a', 'b'},
        fetchedAt: DateTime(2026, 1, 1),
        fromCache: true,
      );
      expect(AnnouncementStartupPolicy.unreadCount(state), 0);
      expect(AnnouncementStartupPolicy.hasUnread(state), isFalse);
    });

    test('空列表 → 不亮', () {
      const state = AnnouncementState(
        items: [],
        readIds: {},
        fetchedAt: null,
        fromCache: true,
      );
      expect(AnnouncementStartupPolicy.hasUnread(state), isFalse);
    });

    test('id 为空的脏数据不计入未读，否则红点永远消不掉', () {
      // 空 id 的已读状态存不住（markRead 存空串无意义），若计入未读，
      // 用户点开也标不掉，红点会永久亮着。
      final state = AnnouncementState(
        items: [entry('a'), entry('')],
        readIds: {'a'},
        fetchedAt: DateTime(2026, 1, 1),
        fromCache: true,
      );
      expect(AnnouncementStartupPolicy.unreadCount(state), 0);
      expect(AnnouncementStartupPolicy.hasUnread(state), isFalse);
    });

    test('已读集合里有已下线的 id → 不影响未读计数', () {
      final state = AnnouncementState(
        items: [entry('a')],
        readIds: {'a', '已下线的旧公告'},
        fetchedAt: DateTime(2026, 1, 1),
        fromCache: true,
      );
      expect(AnnouncementStartupPolicy.unreadCount(state), 0);
    });
  });

  group('该弹哪一条', () {
    test('只弹 warning，info/notice 不打扰', () {
      final state = AnnouncementState(
        items: [entry('i', level: 'info'), entry('n', level: 'notice')],
        readIds: const {},
        fetchedAt: DateTime(2026, 1, 1),
        fromCache: false,
      );
      expect(AnnouncementStartupPolicy.popupCandidate(state), isNull);
    });

    test('未读 warning → 弹', () {
      final state = AnnouncementState(
        items: [entry('i', level: 'info'), entry('w', level: 'warning')],
        readIds: const {},
        fetchedAt: DateTime(2026, 1, 1),
        fromCache: false,
      );
      expect(AnnouncementStartupPolicy.popupCandidate(state)?.id, 'w');
    });

    test('warning 已读 → 不再弹', () {
      final state = AnnouncementState(
        items: [entry('w', level: 'warning')],
        readIds: const {'w'},
        fetchedAt: DateTime(2026, 1, 1),
        fromCache: false,
      );
      expect(AnnouncementStartupPolicy.popupCandidate(state), isNull);
    });

    test('多条未读 warning → 优先 pinned', () {
      final state = AnnouncementState(
        items: [
          entry('w1', level: 'warning', at: DateTime(2026, 5, 1)),
          entry('w2', level: 'warning', pinned: true, at: DateTime(2026, 1, 1)),
        ],
        readIds: const {},
        fetchedAt: DateTime(2026, 1, 1),
        fromCache: false,
      );
      expect(AnnouncementStartupPolicy.popupCandidate(state)?.id, 'w2');
    });

    test('都没 pinned → 取最新发布的那条', () {
      final state = AnnouncementState(
        items: [
          entry('old', level: 'warning', at: DateTime(2026, 1, 1)),
          entry('new', level: 'warning', at: DateTime(2026, 5, 1)),
        ],
        readIds: const {},
        fetchedAt: DateTime(2026, 1, 1),
        fromCache: false,
      );
      expect(AnnouncementStartupPolicy.popupCandidate(state)?.id, 'new');
    });

    test('id 为空的脏数据不参与弹窗，否则 markRead 存不住会反复弹', () {
      final state = AnnouncementState(
        items: [entry('', level: 'warning')],
        readIds: const {},
        fetchedAt: DateTime(2026, 1, 1),
        fromCache: false,
      );
      expect(AnnouncementStartupPolicy.popupCandidate(state), isNull);
    });
  });
}
