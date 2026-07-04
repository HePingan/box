import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 阅读书签模型
@immutable
class ReaderBookmark {
  final String id;
  final String bookId;
  final int chapterIndex;
  final String chapterTitle;
  final int? pageIndex;
  final DateTime createdAt;

  const ReaderBookmark({
    required this.id,
    required this.bookId,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.createdAt,
    this.pageIndex,
  });

  ReaderBookmark copyWith({
    String? id,
    String? bookId,
    int? chapterIndex,
    String? chapterTitle,
    int? pageIndex,
    DateTime? createdAt,
  }) {
    return ReaderBookmark(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      createdAt: createdAt ?? this.createdAt,
      pageIndex: pageIndex ?? this.pageIndex,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookId': bookId,
        'chapterIndex': chapterIndex,
        'chapterTitle': chapterTitle,
        'createdAt': createdAt.toIso8601String(),
        'pageIndex': pageIndex,
      };

  factory ReaderBookmark.fromJson(Map<String, dynamic> json) {
    return ReaderBookmark(
      id: json['id'] as String,
      bookId: json['bookId'] as String,
      chapterIndex: json['chapterIndex'] as int,
      chapterTitle: json['chapterTitle'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      pageIndex: json['pageIndex'] as int?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReaderBookmark &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          bookId == other.bookId &&
          chapterIndex == other.chapterIndex &&
          createdAt == other.createdAt;

  @override
  int get hashCode =>
      id.hashCode ^ bookId.hashCode ^ chapterIndex.hashCode ^ createdAt.hashCode;

  @override
  String toString() =>
      'ReaderBookmark(id:$id, book:$bookId, ch:$chapterIndex "$chapterTitle")';
}

/// 书签服务接口
abstract class ReaderBookmarkService {
  const ReaderBookmarkService();

  List<ReaderBookmark> loadForBook(String bookId);
  List<ReaderBookmark> loadAll();
  Future<bool> add(ReaderBookmark bookmark);
  Future<void> remove(String bookId, String bookmarkId);
  Future<void> clear(String bookId);
}

/// SharedPreferences 持久化书签服务
class SharedPreferencesReaderBookmarkService extends ReaderBookmarkService {
  static const _kPrefix = 'bookmark_';

  final SharedPreferences _prefs;

  const SharedPreferencesReaderBookmarkService(this._prefs);

  @override
  List<ReaderBookmark> loadForBook(String bookId) {
    final raw = _prefs.getString('$_kPrefix$bookId');
    if (raw == null) return const [];
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => ReaderBookmark.fromJson(e as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (_) {
      return const [];
    }
  }

  @override
  List<ReaderBookmark> loadAll() {
    final all = <ReaderBookmark>[];
    for (final key in _prefs.getKeys()) {
      if (key.startsWith(_kPrefix)) {
        final bookId = key.substring(_kPrefix.length);
        all.addAll(loadForBook(bookId));
      }
    }
    all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return all;
  }

  @override
  Future<bool> add(ReaderBookmark bookmark) async {
    final bookmarks = loadForBook(bookmark.bookId);
    final exists = bookmarks.any(
      (b) => b.chapterIndex == bookmark.chapterIndex &&
          b.pageIndex == bookmark.pageIndex,
    );
    if (exists) return false;

    bookmarks.add(bookmark);
    await _save(bookmark.bookId, bookmarks);
    return true;
  }

  @override
  Future<void> remove(String bookId, String bookmarkId) async {
    final bookmarks = loadForBook(bookId);
    bookmarks.removeWhere((b) => b.id == bookmarkId);
    await _save(bookId, bookmarks);
  }

  @override
  Future<void> clear(String bookId) async {
    await _prefs.remove('$_kPrefix$bookId');
  }

  Future<void> _save(String bookId, List<ReaderBookmark> bookmarks) async {
    final raw = jsonEncode(bookmarks.map((b) => b.toJson()).toList());
    await _prefs.setString('$_kPrefix$bookId', raw);
  }
}

/// 默认空实现（不启用书签功能）
class NoopReaderBookmarkService extends ReaderBookmarkService {
  const NoopReaderBookmarkService();

  @override
  List<ReaderBookmark> loadForBook(String bookId) => const [];

  @override
  List<ReaderBookmark> loadAll() => const [];

  @override
  Future<bool> add(ReaderBookmark bookmark) async => false;

  @override
  Future<void> remove(String bookId, String bookmarkId) async {}

  @override
  Future<void> clear(String bookId) async {}
}
