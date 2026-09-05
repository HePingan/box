import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 阅读界面曾经常驻一个橙色虫子 FloatingActionButton（`ReaderDebugLogButton`），
/// 没有任何 kDebugMode 判断，Release 包里也浮在正文上方遮挡阅读。
///
/// 调试日志已统一到抽屉「更多 → 调试日志」，这个按钮被移除。用源码断言而不是
/// widget test，是因为 `reader_page.dart` 需要一整套小说数据与数据库依赖才能
/// pump 起来，而这里要守的约束很简单：那个类不该回来。
void main() {
  group('阅读器不再常驻调试按钮', () {
    test('reader_page.dart 里没有 ReaderDebugLogButton', () {
      final source = File(
        'lib/novel/pages/reader_page.dart',
      ).readAsStringSync();

      expect(
        source.contains('ReaderDebugLogButton'),
        isFalse,
        reason: '调试按钮不应常驻在阅读界面，日志已统一到抽屉入口',
      );
    });

    test('ReaderDebugLogButton 这个 widget 已从代码库移除', () {
      final source = File(
        'lib/novel/pages/reader/reader_debug_log.dart',
      ).readAsStringSync();

      // 只看类定义与 widget 依赖；文档注释里提到旧名字是有意保留的历史说明。
      expect(source.contains('class ReaderDebugLogButton'), isFalse);
      expect(source.contains('extends StatefulWidget'), isFalse);
      expect(
        source.contains("import 'package:flutter/material.dart'"),
        isFalse,
      );
    });

    test('ReaderDebugLog 不再自己持有 SharedPreferences key', () {
      final source = File(
        'lib/novel/pages/reader/reader_debug_log.dart',
      ).readAsStringSync();

      // 独立的 key 会让日志重新分裂成两套，用户报障时又只能截到一半。
      expect(source.contains("'reader_debug_log'"), isFalse);
      expect(source.contains('shared_preferences'), isFalse);
    });

    test('全代码库没有其他地方引用这个按钮', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.readAsStringSync().contains('ReaderDebugLogButton')) {
          offenders.add(entity.path);
        }
      }

      expect(offenders, isEmpty, reason: '残留引用：$offenders');
    });
  });
}
