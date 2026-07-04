/// 全文搜索结果模型
class ChapterSearchResult {
  final int chapterIndex;
  final String chapterTitle;
  final int matchCount;
  final String? snippet;
  final bool isTitleMatch;
  final bool isCurrent;
  final int? matchPosition;

  const ChapterSearchResult({
    required this.chapterIndex,
    required this.chapterTitle,
    required this.matchCount,
    this.snippet,
    this.isTitleMatch = false,
    this.isCurrent = false,
    this.matchPosition,
  });
}
