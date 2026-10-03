import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 扩展页那排「快捷入口」撤掉后的结构护栏（2026-10-03）。
///
/// 撤销的理由不是"不好看"，是三条入口都不提供独有能力、还带两个永远为 0 的数字：
/// - 「片源」的计数是 `_videoSourceCount = 0;` 硬写死的；
/// - 「书源」的计数读 `book_source_storage_key` / `plugin_config_key`，
///   而真书源库的 key 是 `BookSourceManager.storageKey = 'novel_book_sources_v1'`
///   —— 读的 key 从来不存在，所以永远是 0；
/// - 「诊断」是拿一条临时造的假书源（`bookSourceName: '诊断模式'`、空 url）
///   去开 `BookSourceDiagnosticPage`，等于诊断一条不存在的书源。
///
/// 这类东西不会让任何行为用例变红（它们只是"显示错了"），只能钉源码结构。
void main() {
  final source = File(
    'lib/features/extensions/presentation/plugin_tab.dart',
  ).readAsStringSync();

  test('扩展页不再挂「快捷入口」三连（书源/片源/诊断）', () {
    expect(source.contains('_buildManagementGrid'), isFalse);
    expect(source.contains('ExtensionQuickChip'), isFalse);
    expect(source.contains("title: '快捷入口'"), isFalse);
  });

  test('扩展页不再有写死/读错 key 的源计数', () {
    expect(source.contains('_videoSourceCount'), isFalse);
    expect(source.contains('_bookSourceCount'), isFalse);
    // 真 key 在 book_source_manager.dart；这里只保证不再出现那两个幽灵 key。
    expect(source.contains('book_source_storage_key'), isFalse);
    expect(source.contains('plugin_config_key'), isFalse);
  });

  test('扩展页不再把书源诊断页当「应用自检」的入口', () {
    expect(source.contains('BookSourceDiagnosticPage'), isFalse);
  });

  test('书源数的唯一真相仍在 BookSourceManager.storageKey', () {
    final manager = File(
      'lib/novel/pages/source_manager/book_source_manager.dart',
    ).readAsStringSync();
    expect(manager.contains("storageKey = 'novel_book_sources_v1'"), isTrue);
  });
}
