import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:box/features/extensions/market/presentation/plugin_submit_page.dart';

void main() {
  test('投稿模板库：每个模板的动作都在投稿页可选范围内', () {
    final allowed = HomePluginActionType.displayOrder
        .map((a) => a.name)
        .toSet();
    for (final template in kSubmitTemplates) {
      expect(
        allowed,
        contains(template.actionCode),
        reason: '${template.key} 的 actionCode 不在下拉里，作者选了也提交不了',
      );
    }
  });

  test('投稿模板库：schema 合法，url 字段 default 必须是 https', () {
    for (final template in kSubmitTemplates) {
      if (template.schema.isEmpty) continue;
      final decoded = jsonDecode(template.schema);
      expect(decoded, isA<Map>(), reason: '${template.key} schema 不是对象');
      for (final entry in (decoded as Map).entries) {
        final field = entry.value as Map;
        expect(field['default'], isA<String>(),
            reason: '${template.key}.${entry.key} 缺 default');
        if (field['type'] == 'url') {
          expect(
            (field['default'] as String).startsWith('https://'),
            isTrue,
            reason: '${template.key}.${entry.key} 的 default 不是 https',
          );
        }
      }
    }
  });

  test('投稿模板库：payload 里的 {{key}} 必须在 schema 里有对应字段', () {
    for (final template in kSubmitTemplates) {
      if (template.schema.isEmpty) continue;
      final schema = jsonDecode(template.schema) as Map;
      final refs = RegExp(r'\{\{([a-zA-Z][a-zA-Z0-9_]*)\}\}')
          .allMatches(template.payload)
          .map((m) => m.group(1))
          .toSet();
      for (final ref in refs) {
        expect(schema.containsKey(ref), isTrue,
            reason: '${template.key} 的 payload 引用了未声明的字段 $ref');
      }
    }
  });
}
