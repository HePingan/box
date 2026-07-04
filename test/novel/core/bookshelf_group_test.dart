import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:box/novel/core/bookshelf_group.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BookshelfGroupManager.instance.clearCache();
  });

  group('BookshelfGroup', () {
    test('should create with defaults', () {
      final group = BookshelfGroup(id: 'test', name: '测试');
      expect(group.id, 'test');
      expect(group.name, '测试');
      expect(group.icon, '📚');
      expect(group.sortOrder, 0);
    });

    test('should serialize and deserialize', () {
      final group = BookshelfGroup(
        id: 'reading',
        name: '在读',
        icon: '📖',
        sortOrder: 1,
      );
      final json = group.toJson();
      final restored = BookshelfGroup.fromJson(json);
      expect(restored.id, group.id);
      expect(restored.name, group.name);
      expect(restored.icon, group.icon);
      expect(restored.sortOrder, group.sortOrder);
    });

    test('copyWith should preserve unchanged fields', () {
      final group = BookshelfGroup(id: 'a', name: 'A', icon: '📖', sortOrder: 1);
      final copied = group.copyWith(name: 'B');
      expect(copied.id, 'a');
      expect(copied.name, 'B');
      expect(copied.icon, '📖');
      expect(copied.sortOrder, 1);
    });

    test('equality should be based on id', () {
      final a = BookshelfGroup(id: 'x', name: 'X');
      final b = BookshelfGroup(id: 'x', name: 'Y');
      final c = BookshelfGroup(id: 'z', name: 'X');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('BookshelfGroupManager', () {
    test('should return default groups initially', () async {
      final manager = BookshelfGroupManager.instance;
      // Clear and re-init
      manager.clearCache();
      final groups = await manager.getGroups();
      expect(groups.length, 3);
      expect(groups.any((g) => g.name == '在读'), isTrue);
      expect(groups.any((g) => g.name == '已读'), isTrue);
      expect(groups.any((g) => g.name == '想读'), isTrue);
    });

    test('should add and list groups', () async {
      final manager = BookshelfGroupManager.instance;
      manager.clearCache();
      // Start fresh, add a group
      await manager.addGroup(
        const BookshelfGroup(id: 'fav', name: '收藏', icon: '❤️', sortOrder: 10),
      );
      final groups = await manager.getGroups();
      expect(groups.length, 4);
      expect(groups.any((g) => g.id == 'fav'), isTrue);
      // Our added group should be in there
      final fav = groups.firstWhere((g) => g.id == 'fav');
      expect(fav.name, '收藏');
    });

    test('should remove a group', () async {
      final manager = BookshelfGroupManager.instance;
      manager.clearCache();
      await manager.removeGroup('reading');
      final groups = await manager.getGroups();
      expect(groups.any((g) => g.id == 'reading'), isFalse);
      // 3 defaults - 1 = 2
      expect(groups.length, 2);
    });

    test('should manage book membership', () async {
      final manager = BookshelfGroupManager.instance;
      manager.clearCache();
      await manager.addBookToGroup('reading', 'book_1');
      await manager.addBookToGroup('reading', 'book_2');
      await manager.addBookToGroup('finished', 'book_1');

      var ids = await manager.getBookIdsInGroup('reading');
      expect(ids, containsAll(['book_1', 'book_2']));

      ids = await manager.getBookIdsInGroup('finished');
      expect(ids, ['book_1']);

      var groupIds = await manager.getGroupIdsForBook('book_1');
      expect(groupIds, containsAll(['reading', 'finished']));

      // Remove from one group
      await manager.removeBookFromGroup('reading', 'book_1');
      ids = await manager.getBookIdsInGroup('reading');
      expect(ids, ['book_2']);

      // Remove from all
      await manager.removeBookFromAllGroups('book_2');
      ids = await manager.getBookIdsInGroup('reading');
      expect(ids, isEmpty);
    });

    test('should update group', () async {
      final manager = BookshelfGroupManager.instance;
      manager.clearCache();
      await manager.updateGroup(
        const BookshelfGroup(id: 'reading', name: '正在读', icon: '📖', sortOrder: 1),
      );
      final groups = await manager.getGroups();
      final reading = groups.firstWhere((g) => g.id == 'reading');
      expect(reading.name, '正在读');
      // Should still have 3 groups
      expect(groups.length, 3);
    });
  });
}
