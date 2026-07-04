/// 词典管理器 — 管理多个词典源
library;

import 'models/dictionary_definition.dart';
import 'models/dictionary_source.dart';
import 'sources/built_in_source.dart';

/// 词典管理器
class DictionaryManager {
  final List<DictionarySource> _sources;
  DictionarySource? _activeSource;

  /// 简单内存缓存：word → DictionaryDefinition
  final Map<String, DictionaryDefinition> _cache = {};

  DictionaryManager({
    List<DictionarySource>? sources,
    DictionarySource? activeSource,
  })  : _sources = sources ?? [BuiltInDictionarySource()],
        _activeSource = activeSource;

  /// 所有注册的词典源
  List<DictionarySource> get sources => List.unmodifiable(_sources);

  /// 当前活跃的词典源
  DictionarySource get activeSource =>
      _activeSource ?? _sources.first;

  /// 切换活跃词典源
  void setActiveSource(String id) {
    _cache.clear(); // 切换源时清除缓存
    final found = _sources.cast<DictionarySource?>().firstWhere(
          (s) => s!.id == id,
          orElse: () => null,
        );
    if (found != null) {
      _activeSource = found;
    }
  }

  /// 注册新词典源
  void register(DictionarySource source) {
    _sources.removeWhere((s) => s.id == source.id);
    _sources.add(source);
    if (_activeSource == null) {
      _activeSource = source;
    }
  }

  /// 移除词典源
  void unregister(String id) {
    if (id == 'built_in') return; // 不可移除内置
    _sources.removeWhere((s) => s.id == id);
    _cache.removeWhere((_, v) => v.source == id);
    if (_activeSource?.id == id) {
      _activeSource = _sources.isNotEmpty ? _sources.first : null;
    }
  }

  /// 查词（使用当前活跃源，带缓存）
  Future<DictionaryDefinition> lookup(String word) async {
    final trimmed = word.trim();
    if (trimmed.isEmpty) {
      return DictionaryDefinition(word: '', source: '');
    }
    // 缓存命中
    final cached = _cache[trimmed];
    if (cached != null) return cached;
    // 查源
    final result = await activeSource.lookup(trimmed);
    // 缓存非空结果
    if (!result.isEmpty) {
      _cache[trimmed] = result;
    }
    return result;
  }

  /// 清空缓存
  void clearCache() => _cache.clear();
}
