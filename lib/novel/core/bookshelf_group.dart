import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 书架分组数据模型
class BookshelfGroup {
  final String id;
  final String name;
  final String icon; // emoji 或 Material Icons 名称
  final int sortOrder;

  const BookshelfGroup({
    required this.id,
    required this.name,
    this.icon = '📚',
    this.sortOrder = 0,
  });

  BookshelfGroup copyWith({
    String? id,
    String? name,
    String? icon,
    int? sortOrder,
  }) {
    return BookshelfGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'sortOrder': sortOrder,
      };

  factory BookshelfGroup.fromJson(Map<String, dynamic> json) {
    return BookshelfGroup(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String? ?? '📚',
      sortOrder: json['sortOrder'] as int? ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is BookshelfGroup && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'BookshelfGroup($id: $name)';
}

/// 书架分组管理器
class BookshelfGroupManager {
  BookshelfGroupManager._();

  static final BookshelfGroupManager _instance = BookshelfGroupManager._();
  static BookshelfGroupManager get instance => _instance;

  static const String _groupsKey = 'bookshelf_groups';
  static const String _membersKey = 'bookshelf_group_members';

  SharedPreferences? _prefs;
  List<BookshelfGroup>? _groupsCache;
  Map<String, List<String>>? _membersCache; // groupId -> [bookId]

  Future<SharedPreferences> get _prefsAsync async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ── 分组定义 ──

  Future<List<BookshelfGroup>> getGroups() async {
    if (_groupsCache != null) return _groupsCache!;

    final prefs = await _prefsAsync;
    final str = prefs.getString(_groupsKey);
    if (str == null || str.isEmpty) {
      _groupsCache = _defaultGroups();
      await _saveGroups(_groupsCache!);
      return _groupsCache!;
    }

    try {
      final raw = jsonDecode(str);
      if (raw is! List) {
        _groupsCache = _defaultGroups();
        return _groupsCache!;
      }
      _groupsCache = raw
          .map((e) => BookshelfGroup.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      _groupsCache = _defaultGroups();
    }
    return _groupsCache!;
  }

  Future<void> addGroup(BookshelfGroup group) async {
    final groups = await getGroups();
    groups.add(group);
    await _saveGroups(groups);
  }

  Future<void> updateGroup(BookshelfGroup group) async {
    final groups = await getGroups();
    final idx = groups.indexWhere((g) => g.id == group.id);
    if (idx >= 0) {
      groups[idx] = group;
      await _saveGroups(groups);
    }
  }

  Future<void> removeGroup(String groupId) async {
    final groups = await getGroups();
    groups.removeWhere((g) => g.id == groupId);
    await _saveGroups(groups);
    // 同时清除该分组成员
    final members = await _getMembers();
    members.remove(groupId);
    await _saveMembers(members);
  }

  Future<void> reorderGroups(List<BookshelfGroup> groups) async {
    await _saveGroups(groups);
  }

  // ── 分组成员 ──

  Future<Map<String, List<String>>> _getMembers() async {
    if (_membersCache != null) return _membersCache!;

    final prefs = await _prefsAsync;
    final str = prefs.getString(_membersKey);
    if (str == null || str.isEmpty) {
      _membersCache = {};
      return _membersCache!;
    }

    try {
      final raw = jsonDecode(str);
      if (raw is! Map) {
        _membersCache = {};
        return _membersCache!;
      }
      _membersCache = raw.map((k, v) =>
          MapEntry(k.toString(), List<String>.from(v as List)));
    } catch (_) {
      _membersCache = {};
    }
    return _membersCache!;
  }

  /// 获取全部分组归属映射 (groupId -> [bookId])
  Future<Map<String, List<String>>> getMembers() async {
    return _getMembers();
  }

  /// 获取某个分组中的书籍 ID 列表
  Future<List<String>> getBookIdsInGroup(String groupId) async {
    final members = await _getMembers();
    return members[groupId] ?? [];
  }

  /// 获取某本书所在的所有分组 ID
  Future<List<String>> getGroupIdsForBook(String bookId) async {
    final members = await _getMembers();
    final result = <String>[];
    for (final entry in members.entries) {
      if (entry.value.contains(bookId)) {
        result.add(entry.key);
      }
    }
    return result;
  }

  /// 将书籍添加到分组
  Future<void> addBookToGroup(String groupId, String bookId) async {
    final members = await _getMembers();
    members.putIfAbsent(groupId, () => []);
    if (!members[groupId]!.contains(bookId)) {
      members[groupId]!.add(bookId);
      await _saveMembers(members);
    }
  }

  /// 将书籍从分组移除
  Future<void> removeBookFromGroup(String groupId, String bookId) async {
    final members = await _getMembers();
    final list = members[groupId];
    if (list != null) {
      list.remove(bookId);
      if (list.isEmpty) {
        members.remove(groupId);
      }
      await _saveMembers(members);
    }
  }

  /// 将书籍从所有分组移除
  Future<void> removeBookFromAllGroups(String bookId) async {
    final members = await _getMembers();
    bool changed = false;
    for (final entry in members.entries) {
      if (entry.value.remove(bookId)) {
        changed = true;
      }
    }
    if (changed) {
      members.removeWhere((_, v) => v.isEmpty);
      await _saveMembers(members);
    }
  }

  /// 丢弃内存缓存，下次读取重新从 SharedPreferences 载入。
  ///
  /// 恢复备份后必须调用，理由同 [BookshelfManager.invalidateCache]：
  /// 分组成员表也是全量写回的，旧缓存会覆盖掉恢复的分组。
  /// 只清解码结果，不动 `_prefs`（它是全局单例，换掉没意义）。
  void invalidateCache() {
    _groupsCache = null;
    _membersCache = null;
  }

  /// 清空缓存（用于测试或强制重载）
  @visibleForTesting
  void clearCache() {
    _groupsCache = null;
    _membersCache = null;
    _prefs = null;
  }

  List<BookshelfGroup> _defaultGroups() {
    return [
      const BookshelfGroup(id: 'reading', name: '在读', icon: '📖', sortOrder: 1),
      const BookshelfGroup(id: 'finished', name: '已读', icon: '✅', sortOrder: 2),
      const BookshelfGroup(id: 'want_to_read', name: '想读', icon: '⭐', sortOrder: 3),
    ];
  }

  Future<void> _saveGroups(List<BookshelfGroup> groups) async {
    final prefs = await _prefsAsync;
    final json = groups.map((g) => g.toJson()).toList();
    await prefs.setString(_groupsKey, jsonEncode(json));
    _groupsCache = groups;
  }

  Future<void> _saveMembers(Map<String, List<String>> members) async {
    final prefs = await _prefsAsync;
    final json = members.map((k, v) => MapEntry(k, v));
    await prefs.setString(_membersKey, jsonEncode(json));
    _membersCache = members;
  }
}
