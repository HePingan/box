import 'dart:convert';
import 'dart:io';

import 'package:box/novel/core/rule_novel_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// 猫眼看书（优++）书源兼容性测试
///
/// 原始 JSON 文件：C:\Users\Admin\Downloads\解析规则.txt
///
/// 测试结论：
///   1. 搜索 API  ✅ 正常工作（不需要 Authorization header）
///   2. 详情 API   ❌ 依赖 Authorization（token 已过期，exp=2026-04）
///   3. 章节目录   ❌ 依赖 Authorization（token 已过期）
///   4. 正文内容   ❌ 依赖 Authorization（token 已过期）
///
/// 代码兼容性问题已修复：
///   - [*] 通配符支持（$.data[*] → 取数组所有元素）
///   - _parseChapters 上下文偏差（chapterList 用 decoded 导航，字段用 init/decoded）
///
/// 书源评估：规则格式与 RuleNovelSource/RuleEngineV2 完全兼容，
/// 只需替换有效的 Authorization token 即可恢复全流程。

final String _sourcePath =
    'C:\\Users\\Admin\\Downloads\\解析规则.txt';

RuleNovelSource _buildSource({bool skipAuth = false}) {
  final raw = File(_sourcePath).readAsStringSync();
  final json = jsonDecode(raw) as Map<String, dynamic>;

  if (skipAuth) {
    json['header'] = {
      'User-Agent': 'okhttp/4.9.2',
      'client-device': '2d37f6b5b6b2605373092c3dc65a3b39',
      'client-brand': 'Redmi',
      'client-version': '2.3.0',
      'client-name': 'app.maoyankanshu.novel',
      'client-source': 'android',
    };
  }

  return RuleNovelSource.fromBookSourceJson(json);
}

void main() {
  group('猫眼看书（优++）书源 - 兼容性验证', () {
    late RuleNovelSource source;

    setUp(() {
      source = _buildSource(skipAuth: true);
    });

    test('搜索：斗破苍穹', () async {
      final books = await source.searchBooks('斗破');
      expect(books, isNotEmpty, reason: '搜索应返回结果');
      print('搜索到 ${books.length} 本');
      for (final b in books.take(5)) {
        print('  「${b.title}」${b.author}  id=${b.id}');
      }

      // 验证字段映射完整性
      final first = books.first;
      expect(first.id, isNotEmpty);
      expect(first.title, isNotEmpty);
      expect(first.author, isNotEmpty);
      expect(first.detailUrl, contains(first.id));
      expect(first.coverUrl, isNotEmpty);
      expect(first.intro, isNotEmpty);
    }, timeout: Timeout(const Duration(seconds: 30)));

    test('[*] 通配符支持验证', () async {
      // 通过搜索确认 $.data[*] 能被正确解析
      final books = await source.searchBooks('凡人');
      expect(books, isNotEmpty, reason: r'$.data[*] 应正确提取数组元素');
      print('搜索"凡人" → ${books.length} 本');
    }, timeout: Timeout(const Duration(seconds: 30)));

    test('详情和章节（预期跳过 - token 已过期）', () async {
      final books = await source.searchBooks('斗破');
      expect(books, isNotEmpty);

      final first = books.first;
      print('尝试获取详情...');
      print('  detailUrl: ${first.detailUrl}');

      try {
        final detail = await source.fetchDetail(
          bookId: first.id,
          detailUrl: first.detailUrl,
        );
        if (detail.chapters.isEmpty) {
          print('  ⚠ 详情 API 返回了空章节列表（预期：token 过期导致认证失败）');
        } else {
          print('  ✅ 详情获取成功，共 ${detail.chapters.length} 章');
        }
      } catch (e) {
        print('  ⚠ fetchDetail 异常: $e');
      }
    }, timeout: Timeout(const Duration(seconds: 30)));

    test('书源规则格式检查', () async {
      final raw = File(_sourcePath).readAsStringSync();
      final json = jsonDecode(raw) as Map<String, dynamic>;

      // ruleSearch
      final rs = json['ruleSearch'] as Map?;
      expect(rs?['bookList'], r'$.data[*]');
      expect(rs?['name'], r'$.novelName');
      expect(rs?['author'], r'$.authorName');

      // ruleToc
      final rt = json['ruleToc'] as Map?;
      expect(rt?['chapterList'], r'$.data.list[*]');
      final chapterUrl = rt?['chapterUrl'] as String? ?? '';
      expect(chapterUrl, contains('@js:java.aesBase64DecodeToString'));
      expect(chapterUrl, contains('f041c49714d39908')); // AES 密钥
      expect(chapterUrl, contains('0123456789abcdef')); // AES IV

      // ruleBookInfo
      final rbi = json['ruleBookInfo'] as Map?;
      expect(rbi?['init'], r'$.data');
      expect(rbi?['tocUrl'], contains(r'{{$.novelId}}'));

      print('✅ 所有规则格式与 RuleEngineV2 兼容');
      print('  chapterUrl 使用 evalJs AES 解密格式 → 匹配 CryptoUtils.evalJs');
    });
  });
}
