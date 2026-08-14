import '../../core/models.dart';
import '../../core/novel_repository.dart';
import '../../novel_module.dart';

class ReaderProgressService {
  const ReaderProgressService({this.repository});

  final NovelRepository? repository;

  NovelRepository get _repo => repository ?? NovelModule.repository;

  /// 读取整本书当前保存的进度
  Future<ReadingProgress?> loadProgress(String bookId) async {
    return _repo.getProgress(bookId);
  }

  /// 保存进度
  Future<ReadingProgress> saveProgress(ReadingProgress progress) async {
    await _repo.saveProgress(progress);
    return progress;
  }

  /// 只读取"当前章节是否有对应进度"
  /// 如果保存的是别的章节，则返回 null
  Future<ReadingProgress?> loadCurrentChapterProgress(
    String bookId,
    int chapterIndex,
  ) async {
    final progress = await loadProgress(bookId);
    if (progress != null && progress.chapterIndex == chapterIndex) {
      return progress;
    }
    return null;
  }

  /// 恢复当前章节的偏移量
  /// 返回值语义与旧逻辑一致：
  /// - 分页模式：返回"页偏移编码"
  /// - 连续滚动模式：返回滚动偏移
  Future<double?> restoreOffsetForChapter(
    String bookId,
    int chapterIndex,
  ) async {
    final progress = await loadCurrentChapterProgress(bookId, chapterIndex);
    return progress?.scrollOffset;
  }

  /// 恢复当前章节的字符偏移（排版无关的锚点）。
  ///
  /// 返回 null 表示：没有该章进度，或进度是旧版本（无 charOffset 字段）。
  /// 调用方须降级到 [restoreOffsetForChapter] 的页索引逻辑。
  Future<int?> restoreCharOffsetForChapter(
    String bookId,
    int chapterIndex,
  ) async {
    final progress = await loadCurrentChapterProgress(bookId, chapterIndex);
    return progress?.charOffset;
  }
}
