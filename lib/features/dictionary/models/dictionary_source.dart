/// 词典源抽象接口
library;

import 'dictionary_definition.dart';

/// 词典源 — 定义如何查词
abstract class DictionarySource {
  /// 显示名称（如 "内置词表"、"有道词典"）
  String get name;

  /// 唯一标识
  String get id;

  /// 查词
  Future<DictionaryDefinition> lookup(String word);

  /// 是否可配置（自定义 API 源返回 true）
  bool get isConfigurable => false;
}
