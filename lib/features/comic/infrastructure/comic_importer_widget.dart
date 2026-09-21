import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'package:box/features/comic/domain/comic_book.dart';
import 'package:box/features/comic/domain/comic_library_store.dart';
import 'package:box/features/comic/infrastructure/comic_importer.dart';

/// 加载框句柄：关闭动作 + 一个与 BuildContext 解耦的提示通道。
class _LoadingHandle {
  const _LoadingHandle({required this.close, required this.toast});

  final VoidCallback close;
  final void Function(String message) toast;
}

/// 本地漫画导入器（CBZ / ZIP / 图片文件夹）。
///
/// 实现要点：
/// - 文件选择返回后必须先查 `context.mounted` 再弹加载框，否则用户在选择器里
///   停留时页面被销毁会炸。
/// - 加载框用捕获到的 [NavigatorState] 关闭，不再用页面 context 二次 pop，
///   避免「加载框已被系统返回键关掉 → 后续 pop 把整页弹走」。
class ComicImporterWidget {
  const ComicImporterWidget._();

  /// 导入 CBZ/ZIP 文件。
  static Future<ComicBook?> importFile(BuildContext context) async {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['cbz', 'zip'],
    );
    if (result == null) return null;

    final filePath = result.path;
    if (filePath == null) return null;
    if (!context.mounted) return null;

    final loading = _showLoading(context);
    try {
      final pages = await ComicImporter.extractPages(filePath);
      final coverPath = await ComicImporter.extractCover(filePath);
      loading.close();

      if (pages.isEmpty) {
        loading.toast('文件中没有找到图片');
        return null;
      }

      return ComicBook(
        id: const Uuid().v4(),
        title: _extractTitle(filePath),
        coverPath: coverPath,
        sourceType: ComicSourceType.file,
        filePath: filePath,
        pages: pages,
        pageCount: pages.length,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      loading.close();
      loading.toast('导入失败: $e');
      return null;
    }
  }

  /// 导入图片文件夹。
  static Future<ComicBook?> importFolder(BuildContext context) async {
    final result = await FilePicker.getDirectoryPath();
    if (result == null) return null;

    final dir = Directory(result);
    if (!dir.existsSync()) return null;
    if (!context.mounted) return null;

    final loading = _showLoading(context);
    try {
      final pages = await ComicImporter.extractPagesFromFolder(result);
      loading.close();

      if (pages.isEmpty) {
        loading.toast('文件夹中没有找到图片');
        return null;
      }

      return ComicBook(
        id: const Uuid().v4(),
        title: _folderTitle(result),
        coverPath: pages.first,
        sourceType: ComicSourceType.folder,
        folderPath: result,
        pages: pages,
        pageCount: pages.length,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      loading.close();
      loading.toast('导入失败: $e');
      return null;
    }
  }

  /// 弹出不可取消的加载框，返回一个幂等的关闭函数。
  ///
  /// 这里同时把 [ScaffoldMessengerState] 捕获进闭包，后续提示不再触碰
  /// [BuildContext]，从根上避免跨 await 使用 context。
  static _LoadingHandle _showLoading(BuildContext context) {
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    var closed = false;

    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );

    return _LoadingHandle(
      close: () {
        if (closed) return;
        closed = true;
        if (navigator.canPop()) navigator.pop();
      },
      toast: (message) => messenger.showSnackBar(
        SnackBar(content: Text(message)),
      ),
    );
  }

  static String _extractTitle(String path) {
    final fileName = _lastSegment(path);
    return fileName
        .replaceAll(RegExp(r'\.(cbz|zip)$', caseSensitive: false), '')
        .replaceAll('_', ' ')
        .trim();
  }

  static String _folderTitle(String path) => _lastSegment(path);

  static String _lastSegment(String path) {
    final parts = path.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty);
    return parts.isEmpty ? '未命名漫画' : parts.last;
  }

  /// 保存漫画到库。
  static Future<void> saveToLibrary(
    ComicBook book,
    ComicLibraryStore store,
  ) async {
    await store.add(book);
  }
}
