class SourceRules {
  final String Function(String keyword) searchPathBuilder;
  final String Function(String bookId) detailPathBuilder;

  final List<String> searchItemSelectors;
  final List<String> searchLinkSelectors;
  final List<String> searchTitleSelectors;
  final List<String> searchAuthorSelectors;
  final List<String> searchIntroSelectors;
  final List<String> searchCoverSelectors;
  final List<String> searchCategorySelectors;
  final List<String> searchStatusSelectors;
  final List<String> searchWordCountSelectors;

  final List<String> detailTitleSelectors;
  final List<String> detailAuthorSelectors;
  final List<String> detailIntroSelectors;
  final List<String> detailCoverSelectors;
  final List<String> detailCategorySelectors;
  final List<String> detailStatusSelectors;
  final List<String> detailWordCountSelectors;

  final List<String> chapterListSelectors;
  final List<String> chapterTitleSelectors;
  final List<String> contentSelectors;

  const SourceRules({
    required this.searchPathBuilder,
    required this.detailPathBuilder,
    required this.searchItemSelectors,
    required this.searchLinkSelectors,
    required this.searchTitleSelectors,
    required this.searchAuthorSelectors,
    required this.searchIntroSelectors,
    required this.searchCoverSelectors,
    required this.searchCategorySelectors,
    required this.searchStatusSelectors,
    required this.searchWordCountSelectors,
    required this.detailTitleSelectors,
    required this.detailAuthorSelectors,
    required this.detailIntroSelectors,
    required this.detailCoverSelectors,
    required this.detailCategorySelectors,
    required this.detailStatusSelectors,
    required this.detailWordCountSelectors,
    required this.chapterListSelectors,
    required this.chapterTitleSelectors,
    required this.contentSelectors,
  });

  factory SourceRules.generic() {
    return SourceRules(
      searchPathBuilder: (keyword) => '/search?key=${Uri.encodeComponent(keyword)}',
      detailPathBuilder: (bookId) => '/book/$bookId',
      searchItemSelectors: const [
        '.book-item',
        '.result-item',
        '.novel-item',
        '.item',
      ],
      searchLinkSelectors: const ['a'],
      searchTitleSelectors: const ['h3', '.title', '.book-title', 'a'],
      searchAuthorSelectors: const ['.author', '.book-author'],
      searchIntroSelectors: const ['.intro', '.desc', '.summary'],
      searchCoverSelectors: const ['img', '.cover img'],
      searchCategorySelectors: const ['.category', '.tag', '.type'],
      searchStatusSelectors: const ['.status', '.state'],
      searchWordCountSelectors: const ['.word-count', '.words', '.count', '.num'],
      detailTitleSelectors: const ['h1', '.book-title', 'title'],
      detailAuthorSelectors: const ['.author', '.book-author'],
      detailIntroSelectors: const ['.intro', '.desc', '.summary'],
      detailCoverSelectors: const ['.cover img', '.book-cover img', 'img'],
      detailCategorySelectors: const ['.category', '.tag', '.type'],
      detailStatusSelectors: const ['.status', '.state'],
      detailWordCountSelectors: const ['.word-count', '.words', '.count', '.num'],
      chapterListSelectors: const [
        '.chapter-list',
        '.catalog',
        '.directory',
        '.chapters',
        '.list',
      ],
      chapterTitleSelectors: const ['h1', '.chapter-title', '.title', 'title'],
      contentSelectors: const [
        '#content',
        '.content',
        '.chapter-content',
        '.read-content',
        '#txt',
        'article',
      ],
    );
  }
}