// P0-3 回归测试：两份逐行复制的 _canonicalizeJsonValue 必须产出同一结果。
//
// 已修复的真实缺陷：_canonicalizeJsonValue 在
//   lib/plugin_market/models/plugin_market_signature_verifier.dart:7
//   lib/update/update_security.dart:63
// 两份**逐行复制**的实现（仅循环变量名 e / entry 不同）。两边都是安全签名
// 场景（插件市场 sha256、更新清单签名）：一旦某一边改了归一化规则（例如
// 换了排序、改了数字键处理），另一边没跟上，就会产出「同一个 JSON 在两处
// 算出不同 hash」的静默分叉 —— 签名校验哪边挂了都很致命且极难定位。
//
// 修法：公共实现抽到 lib/utils/json_canonical.dart，两侧保留原公开 API
// （pluginMarketCanonicalJson / updateManifestCanonicalJson）作薄包装，
// 现有调用点与测试不动。本测试锁「两公开 API 输出完全相等」。
import 'dart:io';

import 'package:box/plugin_market/models/plugin_market_signature_verifier.dart';
import 'package:box/update/update_security.dart';
import 'package:flutter_test/flutter_test.dart';

/// 剥掉行注释，避免注释里出现定义就被误判成已合并。
String _strip(String path) {
  return File(path)
      .readAsLinesSync()
      .map((line) {
        final idx = line.indexOf('//');
        return idx >= 0 ? line.substring(0, idx) : line;
      })
      .join('\n');
}

const kSharedFile = 'lib/utils/json_canonical.dart';
const kVerifier = 'lib/plugin_market/models/plugin_market_signature_verifier.dart';
const kUpdateSecurity = 'lib/update/update_security.dart';

void main() {
  group('P0-3 单一实现', () {
    test('必须存在 lib/utils/json_canonical.dart 作为唯一实现', () {
      expect(
        File(kSharedFile).existsSync(),
        isTrue,
        reason: 'canonicalize 的公共实现应放在 lib/utils/json_canonical.dart',
      );
    });

    test('两份业务文件不得再各自定义 _canonicalizeJsonValue', () {
      for (final f in [kVerifier, kUpdateSecurity]) {
        expect(
          _strip(f),
          isNot(matches(RegExp(r'_canonicalizeJsonValue\s*\('))),
          reason: 'P0-3：$f 仍保留私有副本，签名归一化规则会分叉',
        );
      }
    });

    test('两侧公开 API 均须 import 公共实现', () {
      for (final f in [kVerifier, kUpdateSecurity]) {
        expect(
          _strip(f),
          contains("utils/json_canonical.dart';"),
          reason: '$f 必须改为引用公共实现',
        );
      }
    });
  });

  group('P0-3 行为等价（防合并改错语义）', () {
    /// 覆盖签名归一化真正在乎的边界：数字键 Map、null 值、空容器嵌套、
    /// 非 String key、混合类型 List。
    final samples = <dynamic>[
      {'b': 1, 'a': 2, 'C': 3},
      {'10': 'x', '2': 'y', '1': 'z'},
      const {'only': null},
      {'nested': {'z': [1, 2, {'y': 'v', 'x': 'w'}], 'a': []}},
      <dynamic>[3, 'a', null, {'k': 'v'}, <dynamic>[]],
      const {},
      const <dynamic>[],
      'plain string',
      42,
      null,
    ];

    for (var i = 0; i < samples.length; i++) {
      test('样本 $i 两侧 canonical 输出必须完全相等', () {
        expect(
          pluginMarketCanonicalJson(samples[i]),
          updateManifestCanonicalJson(samples[i]),
          reason: 'P0-3：同一个 JSON 在两处算出不同结果 = 签名校验会静默分叉',
        );
      });
    }

    test('Map 键必须按 String 字典序输出（签名规则不能变）', () {
      expect(
        pluginMarketCanonicalJson({'b': 1, 'a': 2}),
        '{"a":2,"b":1}',
        reason: '合并不得顺手改排序规则，否则历史签名全部失效',
      );
    });
  });
}
