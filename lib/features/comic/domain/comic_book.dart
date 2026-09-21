/// 漫画书数据来源
enum ComicSourceType {
  /// 本地文件（CBZ/ZIP）
  file,

  /// 本地文件夹
  folder,
}

/// 漫画书实体
class ComicBook {
  const ComicBook({
    required this.id,
    required this.title,
    this.coverPath,
    required this.sourceType,
    this.filePath,
    this.folderPath,
    this.pageCount,
    this.pages = const [],
    required this.createdAt,
    this.lastReadAt,
    this.currentChapterIndex = 0,
    this.currentPageIndex = 0,
  });

  /// 唯一标识
  final String id;

  /// 书名
  final String title;

  /// 封面路径（本地或网络）
  final String? coverPath;

  /// 来源类型
  final ComicSourceType sourceType;

  /// 文件路径（file 类型）
  final String? filePath;

  /// 文件夹路径（folder 类型）
  final String? folderPath;

  /// 总页数
  final int? pageCount;

  /// 页面列表（file 类型）
  final List<String> pages;

  /// 创建时间
  final int createdAt;

  /// 最后阅读时间
  final int? lastReadAt;

  /// 当前章节索引（单文件多页，此值为 0）
  final int currentChapterIndex;

  /// 当前页索引
  final int currentPageIndex;

  bool get isRead => currentPageIndex > 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'coverPath': coverPath,
        'sourceType': sourceType.name,
        'filePath': filePath,
        'folderPath': folderPath,
        'pageCount': pageCount,
        'pages': pages,
        'createdAt': createdAt,
        'lastReadAt': lastReadAt,
        'currentChapterIndex': currentChapterIndex,
        'currentPageIndex': currentPageIndex,
      };

  factory ComicBook.fromJson(Map<String, dynamic> json) => ComicBook(
        id: json['id'] as String,
        title: json['title'] as String,
        coverPath: json['coverPath'] as String?,
        sourceType: ComicSourceType.values.byName(json['sourceType'] as String),
        filePath: json['filePath'] as String?,
        folderPath: json['folderPath'] as String?,
        pageCount: json['pageCount'] as int?,
        pages: (json['pages'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        createdAt: json['createdAt'] as int,
        lastReadAt: json['lastReadAt'] as int?,
        currentChapterIndex: json['currentChapterIndex'] as int? ?? 0,
        currentPageIndex: json['currentPageIndex'] as int? ?? 0,
      );
}
