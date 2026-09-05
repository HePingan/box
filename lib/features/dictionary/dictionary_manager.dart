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
  }) : _sources = sources ?? [BuiltInDictionarySource()],
       _activeSource = activeSource;

  /// 所有注册的词典源
  List<DictionarySource> get sources => List.unmodifiable(_sources);

  /// 当前活跃的词典源
  DictionarySource get activeSource => _activeSource ?? _sources.first;

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
    final replacingActive = _activeSource?.id == source.id;
    _sources.removeWhere((s) => s.id == source.id);
    _sources.add(source);
    // 覆盖同 id 的源时，活跃指针要跟到新实例上，否则会继续指向已被摘掉的旧对象。
    if (replacingActive) {
      _activeSource = source;
    }
    // 注册同 id 的源意味着实现被替换，旧实例留下的释义必须失效。
    _dropCacheOf(source.id);
    // 注意：这里不做 `_activeSource ??= source`。_activeSource 为 null 时
    // activeSource getter 会回落到 _sources.first，属于「未显式选择」的正常态；
    // 若在此赋值，仅仅新增一个可选源就会把用户在用的源换掉。
  }

  /// 移除词典源
  void unregister(String id) {
    if (id == 'built_in') return; // 不可移除内置
    _sources.removeWhere((s) => s.id == id);
    _dropCacheOf(id);
    if (_activeSource?.id == id) {
      _activeSource = _sources.isNotEmpty ? _sources.first : null;
    }
  }

  /// 清掉某个源 id 产生的缓存。
  ///
  /// DictionaryDefinition.source 存的是源的展示名（name），不是 id，
  /// 所以不能直接拿 id 去比对——那样永远匹配不上，卸载后仍会返回旧源的释义。
  /// 这里先由 id 反查出对应的 name 集合再清理。
  void _dropCacheOf(String id) {
    final names = _sources.where((s) => s.id == id).map((s) => s.name).toSet();
    if (names.isEmpty) {
      // 源已从列表移除、拿不到 name 时，无法精确定位它的条目，
      // 整体清空好过留下陈旧释义（缓存只是加速，重建代价低）。
      _cache.clear();
      return;
    }
    _cache.removeWhere((_, v) => names.contains(v.source));
  }

  /// 查词（使用当前活跃源，带缓存）
  Future<DictionaryDefinition> lookup(String word) async {
    final trimmed = word.trim();
    if (trimmed.isEmpty) {
      return const DictionaryDefinition(word: '', source: '');
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
