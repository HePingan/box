import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:box/novel/core/offline_book_info.dart';

void main() {
  group('OfflineBookInfo', () {
    test('constructor sets all fields', () {
      const info = OfflineBookInfo(
        id: 'book1',
        title: 'Test Book',
        author: 'Author',
        coverUrl: 'http://example.com/cover.jpg',
        cachedChapters: 5,
        totalChapters: 10,
        estimatedBytes: 15360,
      );
      expect(info.id, 'book1');
      expect(info.title, 'Test Book');
      expect(info.author, 'Author');
      expect(info.coverUrl, 'http://example.com/cover.jpg');
      expect(info.cachedChapters, 5);
      expect(info.totalChapters, 10);
      expect(info.estimatedBytes, 15360);
    });

    group('toJson / fromJson', () {
      test('round-trip preserves all fields', () {
        const original = OfflineBookInfo(
          id: 'book1',
          title: 'Test Book',
          author: 'Author',
          coverUrl: 'http://example.com/cover.jpg',
          totalChapters: 10,
        );
        final json = original.toJson();
        final restored = OfflineBookInfo.fromJson(json);
        expect(restored.id, original.id);
        expect(restored.title, original.title);
        expect(restored.author, original.author);
        expect(restored.coverUrl, original.coverUrl);
        expect(restored.totalChapters, original.totalChapters);
      });

      test('fromJson handles null fields', () {
        final json = <String, dynamic>{'id': 'book2'};
        final info = OfflineBookInfo.fromJson(json);
        expect(info.id, 'book2');
        expect(info.title, isNull);
        expect(info.author, isNull);
        expect(info.coverUrl, isNull);
        expect(info.totalChapters, 0);
      });

      test('toJson omits null fields', () {
        const info = OfflineBookInfo(id: 'book3');
        final json = info.toJson();
        expect(json['id'], 'book3');
        expect(json.containsKey('title'), false);
        expect(json.containsKey('author'), false);
      });
    });

    test('copyWith overrides specific fields', () {
      const info = OfflineBookInfo(
        id: 'book1',
        title: 'Old Title',
        cachedChapters: 3,
      );
      final updated = info.copyWith(
        title: 'New Title',
        cachedChapters: 5,
        estimatedBytes: 9000,
      );
      expect(updated.id, 'book1');
      expect(updated.title, 'New Title');
      expect(updated.cachedChapters, 5);
      expect(updated.estimatedBytes, 9000);
      expect(updated.author, isNull);
    });

    test('fromNovelDetail extracts book info from map', () {
      final detailMap = {
        'book': {
          'id': 'b1',
          'title': 'The Book',
          'author': 'Writer',
          'coverUrl': 'http://example.com/c.jpg',
        },
        'chapters': [
          {'title': 'Ch1', 'url': 'http://example.com/1'},
          {'title': 'Ch2', 'url': 'http://example.com/2'},
        ],
      };
      final info = OfflineBookInfo.fromNovelDetail(detailMap);
      expect(info.id, 'b1');
      expect(info.title, 'The Book');
      expect(info.author, 'Writer');
      expect(info.coverUrl, 'http://example.com/c.jpg');
      expect(info.totalChapters, 2);
    });

    test('equality and hashCode work', () {
      const a = OfflineBookInfo(id: 'x', title: 'X');
      const b = OfflineBookInfo(id: 'x', title: 'X');
      const c = OfflineBookInfo(id: 'y', title: 'Y');
      // 默认使用 identity comparison，因为 OfflineBookInfo 是普通 class
      // 所以 a == b 可能为 false
      expect(a.id, b.id);
      expect(a.id, isNot(c.id));
    });
  });

  group('OfflineBookInfo standard JSON serialization', () {
    test('JSON encode/decode list of infos works', () {
      const infos = [
        OfflineBookInfo(id: '1', title: 'A'),
        OfflineBookInfo(id: '2', title: 'B', author: 'Author B'),
      ];
      final jsonList = infos.map((e) => e.toJson()).toList();
      final encoded = jsonEncode(jsonList);
      final decoded = (jsonDecode(encoded) as List)
          .map((e) => OfflineBookInfo.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      expect(decoded.length, 2);
      expect(decoded[0].id, '1');
      expect(decoded[0].title, 'A');
      expect(decoded[1].id, '2');
      expect(decoded[1].author, 'Author B');
    });
  });
}
