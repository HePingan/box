import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:box/features/backup/backup_pref_keys.dart';
import 'package:box/features/backup/local_backup_codec.dart';
import 'package:box/features/backup/local_backup_service.dart';

/// 备份覆盖面回归。
///
/// 背景：1.7.0 换了包名，所有人必须卸载重装，备份/恢复是唯一的数据通道。
/// 但备份原来只导 Hive box + 题库(sqflite)，**小说模块的全部数据都在
/// SharedPreferences**，一个都没进备份 —— 用户按提示"备份了"，重装后
/// 书架、书源、阅读进度全空，且备份文件里根本没有这些数据，不可救。
void main() {
  setUpAll(() {
    Hive.init('${Directory.systemTemp.path}/box_backup_prefs_test');
  });

  setUp(() {
    LocalBackupService.exportQuizJson = () async => jsonEncode({'items': []});
    LocalBackupService.importQuizJson = (_) async => 0;
  });

  tearDown(() {
    LocalBackupService.readPrefs = LocalBackupService.defaultReadPrefs;
    LocalBackupService.writePrefs = LocalBackupService.defaultWritePrefs;
  });

  test('备份必须覆盖小说模块的 SharedPreferences 资产', () {
    // 这些是用户资产（自己攒的），不是可重建的缓存。
    const requiredPrefKeys = <String>[
      'user_bookshelf_v1', // 书架
      'bookshelf_groups', // 书架分组
      'bookshelf_group_members',
      'novel_book_sources_v1', // 自己加的书源，丢了要重配
      'novel_current_book_source_id_v1',
      'reader_settings', // 阅读器设置
      'offline_books_meta_v3', // 离线缓存清单
    ];

    final covered = LocalBackupService.debugPrefKeys;
    final missing = requiredPrefKeys
        .where((k) => !covered.contains(k))
        .toList();

    expect(
      missing,
      isEmpty,
      reason: '备份漏了小说模块这些 SharedPreferences 键，重装后用户资产不可恢复：$missing',
    );
  });

  test('阅读进度按前缀整体纳入备份', () {
    // 进度键是 reading_progress:<bookId> 动态生成的，不能靠枚举。
    expect(
      LocalBackupService.debugPrefPrefixes,
      contains('reading_progress'),
      reason: '阅读进度是动态键，必须按前缀备份，否则"继续阅读"全部丢失',
    );
    expect(BackupPrefKeys.covers('reading_progress:book-42'), isTrue);
  });

  test('缓存类键不进备份（避免备份文件膨胀）', () {
    // 章节正文落在文件里，搜索/详情是可重抓的网络缓存。
    expect(BackupPrefKeys.covers('chapter:https://x.com/c/1'), isFalse);
    expect(BackupPrefKeys.covers('search:斗破:1'), isFalse);
    expect(BackupPrefKeys.covers('detail:https://x.com/b/1'), isFalse);
  });

  test('小说资产能完整走完 备份→恢复 往返，且类型不被改写', () async {
    final source = <String, Object>{
      'user_bookshelf_v1': jsonEncode([
        {'id': 'b1', 'title': '书一'},
        {'id': 'b2', 'title': '书二'},
      ]),
      'novel_book_sources_v1': jsonEncode([
        {'id': 's1', 'name': '源一'},
      ]),
      'reading_progress:b1': jsonEncode({'chapter': 12, 'offset': 340}),
      'reading_progress:b2': jsonEncode({'chapter': 3, 'offset': 0}),
      'reader_settings': jsonEncode({'fontSize': 18}),
      // List<String> 类型必须原样写回，用 setString 会让读取侧抛类型错误。
      'offline_cached_books_v2': <String>['b1', 'b2'],
    };

    LocalBackupService.readPrefs = () async => Map<String, Object>.from(source);

    final raw = await LocalBackupService.createBackup();

    // 备份文件里真的带上了这些键。
    final decoded = LocalBackupCodec.decode(raw);
    expect(decoded.prefs.keys, containsAll(source.keys));

    Map<String, Object>? written;
    LocalBackupService.writePrefs = (values) async {
      written = values;
    };
    await LocalBackupService.restoreBackup(raw);

    expect(written, isNotNull);
    expect(written!['user_bookshelf_v1'], source['user_bookshelf_v1']);
    expect(written!['reading_progress:b1'], source['reading_progress:b1']);
    expect(written!['reading_progress:b2'], source['reading_progress:b2']);
    expect(
      written!['offline_cached_books_v2'],
      isA<List<dynamic>>(),
      reason: 'List 类型的键必须保持 List，不能被序列化成 String',
    );
  });

  test('恢复时忽略备份范围外的键（防篡改的备份文件改登录态）', () async {
    LocalBackupService.readPrefs = () async => <String, Object>{};
    final raw = await LocalBackupService.createBackup();
    final tampered = jsonDecode(raw) as Map<String, dynamic>;
    tampered['prefs'] = <String, dynamic>{
      'auth_token': 'attacker-token',
      'user_bookshelf_v1': jsonEncode([]),
    };

    Map<String, Object>? written;
    LocalBackupService.writePrefs = (values) async {
      written = values;
    };
    await LocalBackupService.restoreBackup(jsonEncode(tampered));

    expect(written?.containsKey('auth_token') ?? false, isFalse,
        reason: '备份范围外的键不该被恢复流程写入');
  });

  test('prefs 读取失败时仍能导出视频侧数据，不整体失败', () async {
    LocalBackupService.readPrefs = () async => throw StateError('prefs 不可用');
    // 不该抛：小说数据缺失好过什么都备不出来。
    final raw = await LocalBackupService.createBackup();
    final data = LocalBackupCodec.decode(raw);
    expect(data.prefs, isEmpty);
  });

  test('prefs 写入失败时不影响已恢复的 Hive 数据', () async {
    LocalBackupService.readPrefs = () async => <String, Object>{
      'user_bookshelf_v1': jsonEncode([
        {'id': 'b1'},
      ]),
    };
    final raw = await LocalBackupService.createBackup();
    LocalBackupService.writePrefs = (_) async => throw StateError('写失败');
    // 不该抛，且返回的条数不虚报 prefs 那部分。
    final count = await LocalBackupService.restoreBackup(raw);
    expect(count, 0);
  });

  test('v1 老备份（没有 prefs 段）仍然能恢复', () {
    final v1 = jsonEncode({
      'format': 'box_local_backup',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'quiz': {'items': []},
      'hive': <String, dynamic>{},
    });
    final data = LocalBackupCodec.decode(v1);
    expect(data.prefs, isEmpty);
  });

  test('导出后自检能分类报数，不是只报一个总数', () async {
    LocalBackupService.readPrefs = () async => <String, Object>{
      'user_bookshelf_v1': jsonEncode([
        {'id': 'b1'},
        {'id': 'b2'},
        {'id': 'b3'},
      ]),
      'novel_book_sources_v1': jsonEncode([
        {'id': 's1'},
      ]),
      'reading_progress:b1': jsonEncode({'chapter': 1}),
    };
    final raw = await LocalBackupService.createBackup();
    final summary = LocalBackupService.summarize(raw);

    expect(summary.bookshelf, 3);
    expect(summary.bookSources, 1);
    expect(summary.readingProgress, 1);
    expect(summary.describe(), contains('书架 3'));
    expect(summary.describe(), contains('书源 1'));
  });
}
