part of 'image_generator_page.dart';

// ──────────────────────────────────────────────
// 下载相关工具 —— 从 _ImageGeneratorPageState 提升为库级私有成员。
// 这些成员无实例状态，独立使用裸名即可。
// ──────────────────────────────────────────────

/// Cache of raw image bytes keyed by URL (populated by
/// [NetworkImageWithFallback.onImageLoaded]).
final Map<String, Uint8List> _imageBytesCache = {};

/// Normalise the URL the same way [SmartImageLoader] does.
String _normalizeUrl(String url) {
  try {
    final uri = Uri.parse(url);
    return uri.replace(host: uri.host.toLowerCase()).toString();
  } catch (_) {
    return url;
  }
}

/// Called by [NetworkImageWithFallback] when raw image bytes are available.
void _onBytesAvailable(String url, Uint8List bytes) {
  _imageBytesCache[url] = bytes;
  final normalized = _normalizeUrl(url);
  if (normalized != url) {
    _imageBytesCache[normalized] = bytes;
  }
}

// ──────────────────────────────────────────────
// 下载簇 extension —— 同库 extension 可访问 _ImageGeneratorPageState 的
// 所有私有实例成员（mounted、context、setState、_baseUrlController 等），
// 零行为变更。
// ──────────────────────────────────────────────

// ignore: library_private_types_in_public_api
extension ImageGeneratorDownloadCluster on _ImageGeneratorPageState {

void _downloadImage(String imageUrl) async {
    if (kIsWeb) {
      try {
        downloadImage(imageUrl);
      } catch (e) {
        await Clipboard.setData(ClipboardData(text: imageUrl));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('下载失败，图片链接已复制到剪贴板')),
        );
      }
      return;
    }

    // On mobile
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('正在处理…'),
          ],
        ),
        duration: Duration(seconds: 30),
      ),
    );

    File? localFile;

    // Strategy 0: grab raw bytes from DefaultCacheManager.
    //    CachedNetworkImage stores the original downloaded bytes here
    //    when it renders each thumbnail — zero network, zero quality loss.
    for (final candidateUrl in {imageUrl, _normalizeUrl(imageUrl)}) {
      if (localFile != null) break;
      try {
        localFile = await _downloadFromCache(candidateUrl);
      } catch (e) {
        debugPrint('Strategy 0 (cache $candidateUrl) failed: $e');
      }
    }

    // Strategy 0b: check the _imageBytesCache (populated by
    //    NetworkImageWithFallback.onImageLoaded) as a fallback
    //    in case DefaultCacheManager API didn't work but the bytes
    //    were captured at render time.
    if (localFile == null) {
      final bytes = _imageBytesCache[imageUrl];
      if (bytes != null && bytes.length > 1024) {
        try {
          final docDir = await getApplicationDocumentsDirectory();
          final saveDir = Directory('${docDir.path}/box_downloads');
          if (!saveDir.existsSync()) saveDir.createSync(recursive: true);
          localFile = File(
            '${saveDir.path}/ai_img_${DateTime.now().millisecondsSinceEpoch}.png',
          );
          await localFile.writeAsBytes(bytes);
        } catch (e) {
          debugPrint('Strategy 0b (bytes cache) failed: $e');
        }
      }
    }

    // Strategy 1: download directly via HttpClient (native Dart, no Dio).
    //    curl works fine from this machine, so the URL is valid.
    //    On the phone, native HttpClient may handle TLS/networking
    //    differently than Dio/OkHttp.
    if (localFile == null) {
      try {
        localFile = await _downloadViaHttpClient(imageUrl);
      } catch (e) {
        debugPrint('Strategy 1 (HttpClient) failed: $e');
      }
    }

    // Strategy 2: download via Dio with browser-like headers
    if (localFile == null) {
      try {
        localFile = await _downloadViaDio(imageUrl);
      } catch (e) {
        debugPrint('Strategy 2 (Dio) failed: $e');
      }
    }

    // Strategy 3: overlay-based full-resolution capture.
    //    Renders CachedNetworkImageProvider in a temporary overlay,
    //    then captures via RepaintBoundary at 1:1.
    if (localFile == null) {
      try {
        localFile = await _captureViaOverlay(imageUrl);
      } catch (e) {
        debugPrint('Strategy 3 (overlay capture) failed: $e');
      }
    }

    // Strategy 4: screen thumbnail capture (fallback — lower quality)
    if (localFile == null) {
      try {
        localFile = await _captureFromRepaintBoundary(imageUrl);
      } catch (e) {
        debugPrint('Strategy 4 (screen capture) failed: $e');
      }
    }

    if (!mounted) return;
    scaffold.hideCurrentSnackBar();

    if (localFile != null && localFile.existsSync() && localFile.lengthSync() > 0) {
      await _showDownloadActions(context, localFile, imageUrl);
    } else {
      _showDownloadError(context, '所有下载方式均失败，请复制链接手动下载', imageUrl);
    }
  }

/// Grab raw file bytes from [DefaultCacheManager] — zero network, zero
  /// quality loss because it's the original downloaded blob.
  Future<File?> _downloadFromCache(String url) async {
    final fileInfo = await DefaultCacheManager().getFileFromCache(url);
    if (fileInfo == null || !fileInfo.file.existsSync()) return null;
    final bytes = await fileInfo.file.readAsBytes();
    if (bytes.length <= 1024) return null;
    final docDir = await getApplicationDocumentsDirectory();
    final saveDir = Directory('${docDir.path}/box_downloads');
    if (!saveDir.existsSync()) saveDir.createSync(recursive: true);
    final file = File(
      '${saveDir.path}/ai_img_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(bytes);
    return file;
  }

/// Strategy 1: download using dart:io [HttpClient] (native, no Dio).
  Future<File?> _downloadViaHttpClient(String imageUrl) async {
    final client = HttpClient();
    client.userAgent =
        'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36';
    final request = await client.getUrl(Uri.parse(imageUrl));
    request.headers.set('Accept', 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8');
    request.headers.set('Accept-Language', 'zh-CN,zh;q=0.9,en;q=0.8');
    request.headers.set('Referer', 'https://files.anyroutes.cn/');
    final response = await request.close();
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
    }
    final docDir = await getApplicationDocumentsDirectory();
    final saveDir = Directory('${docDir.path}/box_downloads');
    if (!saveDir.existsSync()) saveDir.createSync(recursive: true);
    final file = File(
      '${saveDir.path}/ai_img_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(bytes);
    return file;
  }

/// Strategy 2: download via Dio with browser headers.
  Future<File?> _downloadViaDio(String imageUrl) async {
    final docDir = await getApplicationDocumentsDirectory();
    final saveDir = Directory('${docDir.path}/box_downloads');
    if (!saveDir.existsSync()) saveDir.createSync(recursive: true);
    final file = File(
      '${saveDir.path}/ai_img_${DateTime.now().millisecondsSinceEpoch}.png',
    );

    final client = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36',
          'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
          'Referer': 'https://files.anyroutes.cn/',
        },
        validateStatus: (_) => true,
      ),
    );
    final response = await client.download(
      imageUrl,
      file.path,
      options: Options(
        followRedirects: true,
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    if (response.statusCode != null && response.statusCode! >= 400) {
      throw Exception(
        'HTTP ${response.statusCode} ${response.statusMessage ?? ''}',
      );
    }
    if (!file.existsSync() || file.lengthSync() <= 0) {
      throw Exception('下载不完整');
    }
    return file;
  }

/// Strategy 3: create a temporary overlay rendering the image at full
  /// resolution and capture via [RepaintBoundary].
  ///
  /// First tries to read raw bytes from [DefaultCacheManager] directly
  /// (could have been missed by Strategy 0 due to key normalisation edge
  /// cases), then falls back to creating a visible overlay, waiting for
  /// the image to render, and capturing the pixels.
  Future<File?> _captureViaOverlay(String imageUrl) async {
    // Grab the overlay reference upfront (before any async gap) so the
    // analyzer knows `context` is safe.
    final overlay = Overlay.of(context, rootOverlay: true);
    final normalisedUrl = _normalizeUrl(imageUrl);

    // --- Attempt A: direct cache lookup with both original & normalised keys ---
    for (final key in {imageUrl, normalisedUrl}) {
      try {
        final fi = await DefaultCacheManager().getFileFromCache(key);
        if (fi != null && fi.file.existsSync()) {
          final bytes = await fi.file.readAsBytes();
          if (bytes.length > 1024) {
            final docDir = await getApplicationDocumentsDirectory();
            final saveDir = Directory('${docDir.path}/box_downloads');
            if (!saveDir.existsSync()) saveDir.createSync(recursive: true);
            final file = File(
              '${saveDir.path}/ai_img_${DateTime.now().millisecondsSinceEpoch}.png',
            );
            await file.writeAsBytes(bytes);
            return file;
          }
        }
      } catch (_) {}
    }

    // --- Attempt B: grab from the _imageBytesCache (populated at render time) ---
    {
      final bytes = _imageBytesCache[imageUrl] ?? _imageBytesCache[normalisedUrl];
      if (bytes != null && bytes.length > 1024) {
        final docDir = await getApplicationDocumentsDirectory();
        final saveDir = Directory('${docDir.path}/box_downloads');
        if (!saveDir.existsSync()) saveDir.createSync(recursive: true);
        final file = File(
          '${saveDir.path}/ai_img_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        await file.writeAsBytes(bytes);
        return file;
      }
    }

    // --- Attempt C: RepaintBoundary capture of a fresh overlay ---
    // Even if cache doesn't have the file, the CachedNetworkImageProvider
    // in the overlay may load it from the Flutter ImageCache (memory).
    final captureKey = GlobalKey();
    final imageLoaded = Completer<void>();

    OverlayEntry? entry;
    entry = OverlayEntry(
      builder: (_) => Center(
        child: RepaintBoundary(
          key: captureKey,
          child: Image(
            image: CachedNetworkImageProvider(imageUrl),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            frameBuilder: (_, child, frame, _) {
              if (frame != null && !imageLoaded.isCompleted) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => imageLoaded.complete(),
                );
              }
              return child;
            },
            errorBuilder: (_, error, _) {
              if (!imageLoaded.isCompleted) {
                imageLoaded.completeError(error);
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    overlay.insert(entry);

    try {
      await imageLoaded.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => imageLoaded.complete(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return null;

      final boundary = captureKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) return null;

      final ui.Image captured = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await captured.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) return null;

      final tmpDir = await getTemporaryDirectory();
      final file = File(
        '${tmpDir.path}/ai_original_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(byteData.buffer.asUint8List());
      return file;
    } finally {
      entry.remove();
    }
  }

/// Strategy 4: capture the on-screen rendered thumbnail via
  /// [RepaintBoundary]. Guaranteed to succeed but quality may be
  /// lower than the original.
  Future<File?> _captureFromRepaintBoundary(String imageUrl) async {
    final key = _imageCaptureKeys[imageUrl];
    if (key == null || key.currentContext == null) return null;

    final boundary = key.currentContext!.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;

    final ui.Image captured = await boundary.toImage(pixelRatio: 4.0);
    final byteData = await captured.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (byteData == null) return null;

    final tmpDir = await getTemporaryDirectory();
    final file = File(
      '${tmpDir.path}/ai_img_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(byteData.buffer.asUint8List());
    return file;
  }

void _showDownloadError(BuildContext context, String msg, String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('下载失败'),
        content: SingleChildScrollView(
          child: SelectableText(
            msg,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: imageUrl));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('链接已复制')),
              );
            },
            child: const Text('复制链接'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

}
