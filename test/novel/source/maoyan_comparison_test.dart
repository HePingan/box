@Tags(['network'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

void main() {
  test('比较 broken URL vs correct URL + headers', () async {
    final file = File('assets/data/maoyan_book_source.json');
    final jsonStr = await file.readAsString();
    final bookSource = jsonDecode(jsonStr) as Map<String, dynamic>;
    final comment = '${bookSource['bookSourceComment'] ?? ''}';

    // 解析
    final domainRegex = RegExp(r'\["([a-z]+)",\s*(\d)\]');
    final authRegex = RegExp(r'\["([a-f0-9]+)",\s*"([^"]+)"\]');
    final domains = <(String, int)>[];
    final aesKeys = <String>[];
    final authTokens = <String>[];
    for (final m in domainRegex.allMatches(comment)) {
      domains.add((m.group(1)!, int.parse(m.group(2)!)));
    }
    for (final m in authRegex.allMatches(comment)) {
      aesKeys.add(m.group(1)!);
      var t = m.group(2)!;
      if (!t.toLowerCase().startsWith('bearer')) {
        t = 'Bearer $t';
      } else {
        t = 'Bearer ${t.substring(6)}';
      }
      authTokens.add(t.trim());
    }

    final (domain, uType) = domains.first;
    final clientDevice = md5.convert(utf8.encode(aesKeys[uType])).toString();
    final authToken = authTokens[uType];

    // 解析 header
    final rawHeader = bookSource['header'] as String;
    final hMap = jsonDecode(rawHeader) as Map;
    final headers = <String, String>{};
    for (final e in hMap.entries) {
      headers['${e.key}'] = '${e.value}'.trim();
    }
    headers['User-Agent'] = 'okhttp/4.9.2';
    headers['client-device'] = clientDevice;
    headers['Authorization'] = authToken;

    // 搜索 URL
    const kw = '大奉打更人';
    final searchPath = '/search?keyword=${Uri.encodeComponent(kw)}&page=1';
    final baseUrl = 'http://api.$domain.com$searchPath';

    // 测试 A: broken URL (with extra ? for queryParams) + headers
    final queryParams = 'client-device=${Uri.encodeQueryComponent(clientDevice)}'
        '&Authorization=${Uri.encodeQueryComponent(authToken)}';
    final brokenUrl = '$baseUrl?$queryParams';
    print('=== 测试 A: Broken URL + Headers ===');
    print('URL: $brokenUrl');
    try {
      final resp = await http.Client()
          .get(Uri.parse(brokenUrl), headers: headers)
          .timeout(const Duration(seconds: 15));
      print('HTTP ${resp.statusCode} (${resp.body.length} bytes)');
      final json = jsonDecode(resp.body);
      print('code: ${json['code']}');
      if (json['data'] is List) {
        print('data length: ${(json['data'] as List).length}');
      } else if (json['data'] is Map) {
        print('data keys: ${(json['data'] as Map).keys}');
      }
    } catch (e) {
      print('ERROR: $e');
    }

    // 测试 B: correct URL (no extra query params) + headers
    print('\n=== 测试 B: Clean URL + Headers ===');
    print('URL: $baseUrl');
    try {
      final resp = await http.Client()
          .get(Uri.parse(baseUrl), headers: headers)
          .timeout(const Duration(seconds: 15));
      print('HTTP ${resp.statusCode} (${resp.body.length} bytes)');
      final json = jsonDecode(resp.body);
      print('code: ${json['code']}');
      if (json['data'] is List) {
        print('data length: ${(json['data'] as List).length}');
      } else if (json['data'] is Map) {
        print('data keys: ${(json['data'] as Map).keys}');
      }
    } catch (e) {
      print('ERROR: $e');
    }

    // 测试 C: detail API
    const detailPath = '/novel/ej8M6z';
    final detailUrl = 'http://api.$domain.com$detailPath';
    print('\n=== 测试 C: Detail API ===');
    print('URL: $detailUrl');
    try {
      final resp = await http.Client()
          .get(Uri.parse(detailUrl), headers: headers)
          .timeout(const Duration(seconds: 15));
      print('HTTP ${resp.statusCode} (${resp.body.length} bytes)');
      final json = jsonDecode(resp.body);
      print('完整响应: $json');
    } catch (e) {
      print('ERROR: $e');
    }

    // 测试 D: Chapter API
    const chapterPath = '/novel/ej8M6z/chapters';
    final chapterUrl = 'http://api.$domain.com$chapterPath';
    print('\n=== 测试 D: Chapter API ===');
    print('URL: $chapterUrl');
    try {
      final resp = await http.Client()
          .get(Uri.parse(chapterUrl), headers: headers)
          .timeout(const Duration(seconds: 15));
      print('HTTP ${resp.statusCode} (${resp.body.length} bytes)');
      if (resp.body.length < 2000) {
        print('响应: ${resp.body}');
      } else {
        print('响应(前500): ${resp.body.substring(0, 500)}...');
      }
      final json = jsonDecode(resp.body);
      print('JSON 键: ${json is Map ? json.keys.join(", ") : "not a map"}');
    } catch (e) {
      print('ERROR: $e');
    }
  });
}
