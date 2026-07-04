/// 离线缓存书籍信息（含缓存状态）
class OfflineBookInfo {
  const OfflineBookInfo({
    required this.id,
    this.title,
    this.author,
    this.coverUrl,
    this.cachedChapters = 0,
    this.totalChapters = 0,
    this.estimatedBytes = 0,
  });

  final String id;
  final String? title;
  final String? author;
  final String? coverUrl;
  final int cachedChapters;
  final int totalChapters;
  final int estimatedBytes;

  OfflineBookInfo copyWith({
    String? id,
    String? title,
    String? author,
    String? coverUrl,
    int? cachedChapters,
    int? totalChapters,
    int? estimatedBytes,
  }) {
    return OfflineBookInfo(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      coverUrl: coverUrl ?? this.coverUrl,
      cachedChapters: cachedChapters ?? this.cachedChapters,
      totalChapters: totalChapters ?? this.totalChapters,
      estimatedBytes: estimatedBytes ?? this.estimatedBytes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (title != null) 'title': title,
        if (author != null) 'author': author,
        if (coverUrl != null) 'cover': coverUrl,
        'totalChapters': totalChapters,
      };

  factory OfflineBookInfo.fromJson(Map<String, dynamic> json) {
    return OfflineBookInfo(
      id: json['id'] as String,
      title: json['title'] as String?,
      author: json['author'] as String?,
      coverUrl: json['cover'] as String?,
      totalChapters: (json['totalChapters'] as num?)?.toInt() ?? 0,
    );
  }

  /// 从 NovelDetail 创建元数据快照
  factory OfflineBookInfo.fromNovelDetail(dynamic detail) {
    final book = detail is Map
        ? (detail['book'] as Map? ?? {})
        : (detail.book.toJson() as Map);
    final chapters = detail is Map
        ? (detail['chapters'] as List? ?? [])
        : (detail.chapters);
    return OfflineBookInfo(
      id: book['id'] as String? ?? '',
      title: book['title'] as String?,
      author: book['author'] as String?,
      coverUrl: book['coverUrl'] as String? ?? book['cover'] as String?,
      totalChapters: chapters.length,
    );
  }
}
