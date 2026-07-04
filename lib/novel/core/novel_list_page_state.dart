/// 小说列表页加载状态枚举。
///
/// 替代 NovelListPage 中的多个 bool 标志位（_bootstrapping, _loading,
/// _loadingMore, _searchMode），使状态转换更清晰、可枚举。
enum NovelListPageState {
  /// 正在初始化书源（bootstrap）。
  bootstrapping,

  /// 初始加载搜索结果/探索列表。
  loading,

  /// 加载更多（下拉刷新后的下一页）。
  loadingMore,

  /// 搜索模式（用户输入了关键词）。
  searchMode,

  /// 空闲（数据已加载完毕）。
  idle,
}
