@Tags(['network'])
library;

// 直接测试 _request 逻辑
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

void main() {
  test('测试 _percentEncodePath 和 URL 构建', () async {
    const kw = '大奉打更人';
    final searchPath = '/search?keyword=${Uri.encodeComponent(kw)}&page=1';
    print('searchPath: $searchPath');

    // 模拟 _request 流程中的 URL 构建
    const host = 'http://api.longchunbajiao.com';
    final fullUrl = '$host$searchPath';
    print('fullUrl: $fullUrl');

    // 模拟 queryParams 追加
    const clientDevice = '14e9fb2c5ffe7d51e8d7fe33b19c12ca';
    const auth = 'Bearer eyJxxx';
    final queryParams = 'client-device=${Uri.encodeQueryComponent(clientDevice)}'
        '&Authorization=${Uri.encodeQueryComponent(auth)}';
    
    // 当前代码的行为 - 用 ?
    final brokenUrl = '$fullUrl?$queryParams';
    print('\n❌ 当前代码（错误）: $brokenUrl');
    final brokenUri = Uri.tryParse(brokenUrl);
    print('  解析结果: $brokenUri');
    
    // 正确行为 - 用 &
    final correctUrl = '$fullUrl&$queryParams';
    print('\n✅ 正确行为: $correctUrl');
    final correctUri = Uri.tryParse(correctUrl);
    print('  解析结果: $correctUri');

    // 测试无 query 的 URL
    const detailPath = '/novel/ej8M6z';
    const detailUrl = '$host$detailPath';
    final detailWithParams = '$detailUrl?$queryParams';
    print('\n详情 URL（加 query）：$detailWithParams');
    final detailUri = Uri.tryParse(detailWithParams);
    print('  解析结果: $detailUri');
  });

  test('直接测试搜索 API 的 headers', () async {
    final comment = (await File('assets/data/maoyan_book_source.json').readAsString());
    final bookSource = jsonDecode(comment) as Map<String, dynamic>;
    
    // 提取认证信息
    final domainRegex = RegExp(r'\["([a-z]+)",\s*(\d)\]');
    final authRegex = RegExp(r'\["([a-f0-9]+)",\s*"([^"]+)"\]');
    final domains = <(String, int)>[];
    final aesKeys = <String>[];
    final authTokens = <String>[];

    for (final m in domainRegex.allMatches('${bookSource['bookSourceComment']}')) {
      domains.add((m.group(1)!, int.parse(m.group(2)!)));
    }
    for (final m in authRegex.allMatches('${bookSource['bookSourceComment']}')) {
      aesKeys.add(m.group(1)!);
      var t = m.group(2)!;
      if (!t.toLowerCase().startsWith('bearer')) {
        t = 'Bearer $t';
      } else {
        t = 'Bearer ${t.substring(6)}';
      }
      authTokens.add(t.trim());
    }

    print('domains: ${domains.length}, aesKeys: ${aesKeys.length}, authTokens: ${authTokens.length}');
    
    final (domain, uType) = domains.first;
    final clientDevice = md5.convert(utf8.encode(aesKeys[uType])).toString();
    final authToken = authTokens[uType];
    print('domain=$domain, uType=$uType');
    print('client-device=$clientDevice');

    // 解析 header JSON
    final rawHeader = bookSource['header'] as String;
    final hMap = jsonDecode(rawHeader) as Map;
    final headers = <String, String>{
      'User-Agent': 'okhttp/4.9.2',
    };
    for (final e in hMap.entries) {
      headers['${e.key}'] = '${e.value}'.trim();
    }
    headers['client-device'] = clientDevice;
    headers['Authorization'] = authToken;
    print('\n最终请求头:');
    headers.forEach((k, v) => print('  $k: $v'));

    // 测试搜索
    const kw = '大奉打更人';
    final searchPath = '/search?keyword=${Uri.encodeComponent(kw)}&page=1';
    final url = 'http://api.$domain.com$searchPath';
    print('\n请求 URL: $url');
    
    try {
      final resp = await http.Client()
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));
      print('HTTP ${resp.statusCode} (${resp.body.length} bytes)');
      final snippet = resp.body.length > 300 ? '${resp.body.substring(0, 300)}...' : resp.body;
      print('Body: $snippet');
      
      final json = jsonDecode(resp.body);
      print('code: ${json['code']}');
      print('msg: ${json['msg']}');
      print('data type: ${json['data'].runtimeType}');
      if (json['data'] is List) {
        print('data length: ${(json['data'] as List).length}');
      }
    } catch (e) {
      print('ERROR: $e');
    }
  });
}
