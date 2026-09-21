/// 阅读进度状态
class ComicReaderState {
  const ComicReaderState({
    required this.comicBookId,
    required this.currentPageIndex,
    required this.totalPages,
    required this.isScrollMode,
    required this.lastReadAt,
  });

  final String comicBookId;
  final int currentPageIndex;
  final int totalPages;
  final bool isScrollMode;
  final int lastReadAt;

  Map<String, dynamic> toJson() => {
        'comicBookId': comicBookId,
        'currentPageIndex': currentPageIndex,
        'totalPages': totalPages,
        'isScrollMode': isScrollMode,
        'lastReadAt': lastReadAt,
      };

  factory ComicReaderState.fromJson(Map<String, dynamic> json) =>
      ComicReaderState(
        comicBookId: json['comicBookId'] as String,
        currentPageIndex: json['currentPageIndex'] as int,
        totalPages: json['totalPages'] as int,
        isScrollMode: json['isScrollMode'] as bool,
        lastReadAt: json['lastReadAt'] as int,
      );
}
