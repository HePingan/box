import 'models.dart';

abstract class NovelSource {
  Future<List<NovelBook>> searchBooks(String keyword, {int page = 1});

  Future<List<NovelBook>> fetchByPath(String path);

  Future<NovelDetail> fetchDetail({
    required String bookId,
    String? detailUrl,
  });

  Future<ChapterContent> fetchChapter({
    required NovelDetail detail,
    required int chapterIndex,
  });
}