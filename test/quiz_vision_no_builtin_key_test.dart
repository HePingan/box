// 护栏：客户端零内置 API 密钥（quiz-vision 方案 A 第二轮）。
//
// 背景：内置 key 曾烧死在 APK 里（`sk-…`），渠道一吊销就是全体用户读屏失效、
// 只能发版救（v270 事故）。本轮把内置 key 彻底删除：未登录也走服务端代理
// （匿名设备令牌）。本护栏用 dart:io 扫 lib/ 源码（不联网、不读构建产物），
// 防止以后有人图省事再把密钥写回来 —— 命中即红灯。
//
// 配套的**正向用例（控制组）**在 quiz_vision_endpoint_resolution_test.dart ①：
// 用户手填 key 仍然照旧直连。零内置密钥 ≠ 禁用用户自己的 key。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 真 key 的形态：`sk-` 后跟一长串字母数字。
/// 设置页里的占位提示（`sk-...` / `sk-…`）不是密钥，不该被误伤。
final RegExp _secretLikeKey = RegExp(r'sk-[A-Za-z0-9]{12,}');

const String _removedConstant = 'defaultVisionApiKey';

List<File> _libDartFiles() {
  final root = Directory('lib');
  expect(root.existsSync(), isTrue, reason: 'flutter test 的工作目录应为包根');
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
}

/// 命中行（`相对路径:行号: 内容`）。
List<String> _hitsInLib(RegExp pattern) {
  final hits = <String>[];
  for (final file in _libDartFiles()) {
    var lineNo = 0;
    for (final line in file.readAsLinesSync()) {
      lineNo++;
      if (pattern.hasMatch(line)) {
        hits.add('${file.path}:$lineNo: ${line.trim()}');
      }
    }
  }
  return hits;
}

void main() {
  test('护栏本身有效：真 key 形态必须被命中，设置页占位提示不误伤', () {
    expect(
      _secretLikeKey.hasMatch("const k = 'sk-1234567890abcdef';"),
      isTrue,
      reason: '闸门抓不到真密钥就等于没有闸门',
    );
    expect(_secretLikeKey.hasMatch("hintText: 'sk-...'"), isFalse);
    expect(_secretLikeKey.hasMatch("hintText: 'sk-…（仅本次使用，不保存）'"), isFalse);
  });

  test('lib/ 不再出现 sk- 形式的密钥字面量', () {
    final hits = _hitsInLib(_secretLikeKey);
    expect(
      hits,
      isEmpty,
      reason: '客户端不得再内置任何 sk- 密钥；命中：${hits.join(' | ')}',
    );
  });

  test('内置密钥常量 $_removedConstant 已从 lib/ 移除', () {
    final hits = _hitsInLib(RegExp(_removedConstant));
    expect(
      hits,
      isEmpty,
      reason: '内置密钥常量必须彻底删除（不是改名藏起来）；命中：${hits.join(' | ')}',
    );
  });
}
