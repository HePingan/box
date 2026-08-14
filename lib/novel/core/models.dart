enum ReaderThemeMode { warm, paper, dark }

class NovelBook {
  final String id;
  final String title;
  final String author;
  final String intro;
  final String coverUrl;
  final String detailUrl;
  final String category;
  final String status;
  final String wordCount;

  const NovelBook({
    required this.id,
    required this.title,
    required this.author,
    required this.intro,
    required this.coverUrl,
    required this.detailUrl,
    this.category = '',
    this.status = '',
    this.wordCount = '',
  });

  NovelBook copyWith({
    String? id,
    String? title,
    String? author,
    String? intro,
    String? coverUrl,
    String? detailUrl,
    String? category,
    String? status,
    String? wordCount,
  }) {
    return NovelBook(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      intro: intro ?? this.intro,
      coverUrl: coverUrl ?? this.coverUrl,
      detailUrl: detailUrl ?? this.detailUrl,
      category: category ?? this.category,
      status: status ?? this.status,
      wordCount: wordCount ?? this.wordCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NovelBook &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          author == other.author &&
          intro == other.intro &&
          coverUrl == other.coverUrl &&
          detailUrl == other.detailUrl &&
          category == other.category &&
          status == other.status &&
          wordCount == other.wordCount;

  @override
  int get hashCode => Object.hash(id, title, author, intro, coverUrl, detailUrl, category, status, wordCount);

  @override
  String toString() => 'NovelBook(id: $id, title: $title, author: $author)';

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'intro': intro,
    'coverUrl': coverUrl,
    'detailUrl': detailUrl,
    'category': category,
    'status': status,
    'wordCount': wordCount,
  };

  factory NovelBook.fromJson(Map<String, dynamic> json) {
    return NovelBook(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      author: json['author'] as String? ?? '',
      intro: json['intro'] as String? ?? '',
      coverUrl: json['coverUrl'] as String? ?? '',
      detailUrl: json['detailUrl'] as String? ?? '',
      category: json['category'] as String? ?? '',
      status: json['status'] as String? ?? '',
      wordCount: json['wordCount'] as String? ?? '',
    );
  }
}

class NovelChapter {
  final String title;
  final String url;

  const NovelChapter({required this.title, required this.url});

  NovelChapter copyWith({String? title, String? url}) {
    return NovelChapter(
      title: title ?? this.title,
      url: url ?? this.url,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NovelChapter &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          url == other.url;

  @override
  int get hashCode => Object.hash(title, url);

  @override
  String toString() => 'NovelChapter(title: $title, url: $url)';

  Map<String, dynamic> toJson() => {'title': title, 'url': url};

  factory NovelChapter.fromJson(Map<String, dynamic> json) {
    return NovelChapter(
      title: json['title'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );
  }
}

class NovelDetail {
  final NovelBook book;
  final List<NovelChapter> chapters;

  const NovelDetail({required this.book, required this.chapters});

  NovelDetail copyWith({NovelBook? book, List<NovelChapter>? chapters}) {
    return NovelDetail(
      book: book ?? this.book,
      chapters: chapters ?? this.chapters,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NovelDetail) return false;
    final o = other;
    if (book != o.book) return false;
    if (chapters.length != o.chapters.length) return false;
    for (var i = 0; i < chapters.length; i++) {
      if (chapters[i] != o.chapters[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(book, Object.hashAll(chapters));

  @override
  String toString() => 'NovelDetail(book: $book, chapters: ${chapters.length})';

  Map<String, dynamic> toJson() => {
    'book': book.toJson(),
    'chapters': chapters.map((e) => e.toJson()).toList(),
  };

  factory NovelDetail.fromJson(Map<String, dynamic> json) {
    final rawChapters = (json['chapters'] as List<dynamic>? ?? <dynamic>[]);
    return NovelDetail(
      book: NovelBook.fromJson(Map<String, dynamic>.from(json['book'] as Map)),
      chapters: rawChapters
          .map(
            (e) => NovelChapter.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
    );
  }
}

class ChapterContent {
  final String title;
  final String content;
  final int chapterIndex;
  final String sourceUrl;
  final bool fromCache;

  const ChapterContent({
    required this.title,
    required this.content,
    required this.chapterIndex,
    required this.sourceUrl,
    this.fromCache = false,
  });

  ChapterContent copyWith({
    String? title,
    String? content,
    int? chapterIndex,
    String? sourceUrl,
    bool? fromCache,
  }) {
    return ChapterContent(
      title: title ?? this.title,
      content: content ?? this.content,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      fromCache: fromCache ?? this.fromCache,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChapterContent &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          content == other.content &&
          chapterIndex == other.chapterIndex &&
          sourceUrl == other.sourceUrl &&
          fromCache == other.fromCache;

  @override
  int get hashCode => Object.hash(title, content, chapterIndex, sourceUrl, fromCache);

  @override
  String toString() => 'ChapterContent(title: $title, chapterIndex: $chapterIndex, fromCache: $fromCache)';

  Map<String, dynamic> toJson() => {
    'title': title,
    'content': content,
    'chapterIndex': chapterIndex,
    'sourceUrl': sourceUrl,
    'fromCache': fromCache,
  };

  factory ChapterContent.fromJson(
    Map<String, dynamic> json, {
    bool fromCache = false,
  }) {
    return ChapterContent(
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      chapterIndex: json['chapterIndex'] as int? ?? 0,
      sourceUrl: json['sourceUrl'] as String? ?? '',
      fromCache: fromCache,
    );
  }
}

class ReadingProgress {
  final String bookId;
  final int chapterIndex;
  final String chapterTitle;
  final double scrollOffset;
  final int updatedAt;

  /// 分页模式专用：当前页在原文中的字符偏移（0-based）。
  /// 
  /// 优先级高于 scrollOffset 的页索引编码。存在时直接定位到原文位置，
  /// 不受字号、行高、屏幕尺寸变化影响。为 null 时降级到旧的页索引逻辑。
  final int? charOffset;

  const ReadingProgress({
    required this.bookId,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.scrollOffset,
    required this.updatedAt,
    this.charOffset,
  });

  ReadingProgress copyWith({
    String? bookId,
    int? chapterIndex,
    String? chapterTitle,
    double? scrollOffset,
    int? updatedAt,
    Object? charOffset = _unset,
  }) {
    return ReadingProgress(
      bookId: bookId ?? this.bookId,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      scrollOffset: scrollOffset ?? this.scrollOffset,
      updatedAt: updatedAt ?? this.updatedAt,
      charOffset: charOffset == _unset ? this.charOffset : charOffset as int?,
    );
  }

  static const Object _unset = Object();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReadingProgress &&
          runtimeType == other.runtimeType &&
          bookId == other.bookId &&
          chapterIndex == other.chapterIndex &&
          chapterTitle == other.chapterTitle &&
          scrollOffset == other.scrollOffset &&
          updatedAt == other.updatedAt &&
          charOffset == other.charOffset;

  @override
  int get hashCode => Object.hash(bookId, chapterIndex, chapterTitle, scrollOffset, updatedAt, charOffset);

  @override
  String toString() =>
      'ReadingProgress(bookId: $bookId, chapterIndex: $chapterIndex, chapterTitle: $chapterTitle, scrollOffset: $scrollOffset, charOffset: $charOffset)';

  Map<String, dynamic> toJson() => {
    'bookId': bookId,
    'chapterIndex': chapterIndex,
    'chapterTitle': chapterTitle,
    'scrollOffset': scrollOffset,
    'updatedAt': updatedAt,
    if (charOffset != null) 'charOffset': charOffset,
  };

  factory ReadingProgress.fromJson(Map<String, dynamic> json) {
    return ReadingProgress(
      bookId: json['bookId'] as String? ?? '',
      chapterIndex: json['chapterIndex'] as int? ?? 0,
      chapterTitle: json['chapterTitle'] as String? ?? '',
      scrollOffset: (json['scrollOffset'] as num?)?.toDouble() ?? 0,
      updatedAt: json['updatedAt'] as int? ?? 0,
      charOffset: json['charOffset'] as int?,
    );
  }
}

class ReaderSettings {
  final double fontSize;
  final double lineHeight;
  final ReaderThemeMode themeMode;
  final double brightness;
  final bool keepScreenOn;
  final bool enableHaptic;

  /// 音量键翻页。开启后阅读页拦截音量键，
  /// 退出阅读页时必须解除拦截，否则全 App 调不了音量。
  final bool volumeKeyNav;
  final double letterSpacing;
  final String? fontFamily;

  /// 滚动模式预加载阈值（剩余多少像素时触发下一章加载，默认 2000）
  final double prefetchAheadPx;

  const ReaderSettings({
    this.fontSize = 18,
    this.lineHeight = 1.8,
    this.themeMode = ReaderThemeMode.warm,
    this.brightness = 1.0,
    this.keepScreenOn = false,
    this.enableHaptic = true,
    this.volumeKeyNav = false,
    this.letterSpacing = 0.0,
    this.fontFamily,
    this.prefetchAheadPx = 2000.0,
  });

  /// 用于区分"未传 fontFamily"与"显式传 null（回到系统默认字体）"。
  /// 普通的 `fontFamily ?? this.fontFamily` 无法表达后者，
  /// 会导致字体切到衬线/等宽后再也选不回系统默认。
  static const Object _unset = Object();

  ReaderSettings copyWith({
    double? fontSize,
    double? lineHeight,
    ReaderThemeMode? themeMode,
    double? brightness,
    bool? keepScreenOn,
    bool? enableHaptic,
    bool? volumeKeyNav,
    double? letterSpacing,
    Object? fontFamily = _unset,
    double? prefetchAheadPx,
  }) {
    return ReaderSettings(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      themeMode: themeMode ?? this.themeMode,
      brightness: brightness ?? this.brightness,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      enableHaptic: enableHaptic ?? this.enableHaptic,
      volumeKeyNav: volumeKeyNav ?? this.volumeKeyNav,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      fontFamily: identical(fontFamily, _unset)
          ? this.fontFamily
          : fontFamily as String?,
      prefetchAheadPx: prefetchAheadPx ?? this.prefetchAheadPx,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReaderSettings &&
          runtimeType == other.runtimeType &&
          fontSize == other.fontSize &&
          lineHeight == other.lineHeight &&
          themeMode == other.themeMode &&
          brightness == other.brightness &&
          keepScreenOn == other.keepScreenOn &&
          enableHaptic == other.enableHaptic &&
          volumeKeyNav == other.volumeKeyNav &&
          letterSpacing == other.letterSpacing &&
          fontFamily == other.fontFamily &&
          prefetchAheadPx == other.prefetchAheadPx;

  @override
  int get hashCode =>
      fontSize.hashCode ^
      lineHeight.hashCode ^
      themeMode.hashCode ^
      brightness.hashCode ^
      keepScreenOn.hashCode ^
      enableHaptic.hashCode ^
      volumeKeyNav.hashCode ^
      letterSpacing.hashCode ^
      fontFamily.hashCode ^
      prefetchAheadPx.hashCode;

  @override
  String toString() =>
      'ReaderSettings(fontSize: $fontSize, lineHeight: $lineHeight, '
      'themeMode: $themeMode, brightness: $brightness, '
      'keepScreenOn: $keepScreenOn, enableHaptic: $enableHaptic, '
      'volumeKeyNav: $volumeKeyNav, '
      'letterSpacing: $letterSpacing, fontFamily: $fontFamily, '
      'prefetchAheadPx: $prefetchAheadPx)';

  Map<String, dynamic> toJson() => {
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'themeMode': themeMode.name,
        'brightness': brightness,
        'keepScreenOn': keepScreenOn,
        'enableHaptic': enableHaptic,
        'volumeKeyNav': volumeKeyNav,
        'letterSpacing': letterSpacing,
        'fontFamily': fontFamily,
        'prefetchAheadPx': prefetchAheadPx,
      };

  factory ReaderSettings.fromJson(Map<String, dynamic> json) {
    final modeName = json['themeMode'] as String? ?? ReaderThemeMode.warm.name;
    final mode = ReaderThemeMode.values.firstWhere(
      (e) => e.name == modeName,
      orElse: () => ReaderThemeMode.warm,
    );

    return ReaderSettings(
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18,
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.8,
      themeMode: mode,
      brightness: (json['brightness'] as num?)?.toDouble() ?? 1.0,
      keepScreenOn: json['keepScreenOn'] as bool? ?? false,
      enableHaptic: json['enableHaptic'] as bool? ?? true,
      volumeKeyNav: json['volumeKeyNav'] as bool? ?? false,
      letterSpacing: (json['letterSpacing'] as num?)?.toDouble() ?? 0.0,
      fontFamily: json['fontFamily'] as String?,
      prefetchAheadPx:
          (json['prefetchAheadPx'] as num?)?.toDouble() ?? 2000.0,
    );
  }
}
