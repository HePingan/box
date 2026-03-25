import '../../core/models.dart';
import '../../novel_module.dart';

class ReaderProgressService {
  const ReaderProgressService();

  /// 读取整本书当前保存的进度
  Future<ReadingProgress?> loadProgress(String bookId) async {
    return NovelModule.repository.getProgress(bookId);
  }

  /// 保存进度
  Future<ReadingProgress> saveProgress(ReadingProgress progress) async {
    await NovelModule.repository.saveProgress(progress);
    return progress;
  }

  /// 只读取“当前章节是否有对应进度”
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
  /// - 分页模式：返回“页偏移编码”
  /// - 连续滚动模式：返回滚动偏移
  Future<double?> restoreOffsetForChapter(
    String bookId,
    int chapterIndex,
  ) async {
    final progress = await loadCurrentChapterProgress(bookId, chapterIndex);
    return progress?.scrollOffset;
  }
}