/// JSON 归一化（canonicalization）的**唯一实现**。
///
/// 为什么抽公共文件：签名/校验场景必须对「同一份 JSON」算出同一个
/// hash。此前 `_canonicalizeJsonValue` 是两个业务文件各自私有复制的
/// 两份实现，逐行相同但循环变量名都不同——随随便便改一处就会让
/// 「同一个 JSON 在两处算出不同 canonical」静默分叉，签名校验在哪边
/// 挂掉都极难定位。
///
/// 这里只做纯搬迁，**不改变任何语义**：
/// - Map 的键统一 toString 后按字典序升序；
/// - List 递归处理，用 growable:false；
/// - 其余值原样返回（数字不会转字符串，避免破坏既有哈希）。
///
/// 行为等价由 test/plugin_market/json_canonical_single_source_test.dart
/// 锁定（两侧公开 API 输出必须完全相等）。
library;

import 'dart:convert';

/// 递归归一化 JSON 值，使 jsonEncode 的结果与插入顺序无关。
dynamic canonicalizeJsonValue(dynamic value) {
  if (value is Map) {
    final entries = <MapEntry<String, dynamic>>[];
    value.forEach((key, val) {
      entries.add(MapEntry(key.toString(), val));
    });
    entries.sort((a, b) => a.key.compareTo(b.key));

    final result = <String, dynamic>{};
    for (final entry in entries) {
      result[entry.key] = canonicalizeJsonValue(entry.value);
    }
    return result;
  }

  if (value is List) {
    return value.map(canonicalizeJsonValue).toList(growable: false);
  }

  return value;
}

/// 归一化序列化：一定能得到稳定的字符串（键有序）。
String canonicalJsonEncode(dynamic value) {
  return jsonEncode(canonicalizeJsonValue(value));
}
