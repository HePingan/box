import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A locally persisted question image plus the two fingerprints used by the
/// question-bank identity and visual disambiguation pipelines.
class QuizQuestionImage {
  const QuizQuestionImage({
    required this.path,
    required this.sha256,
    required this.perceptualHash,
  });

  final String path;
  final String sha256;
  final String perceptualHash;

  /// Manually uploaded images contain only the question illustration, so their
  /// dHash is also valid for image-region disambiguation.
  String get regionHash => perceptualHash;
}

/// Handles image selection without retaining an external gallery/download path.
/// The selected bytes are copied into the app documents directory so existing
/// questions remain usable after the picker/cache provider is cleaned up.
class QuizQuestionImageStore {
  QuizQuestionImageStore._();

  static Future<QuizQuestionImage?> pickAndPersist() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    final picked = result?.files.isNotEmpty == true
        ? result!.files.first
        : null;
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) return null;
    return persistBytes(bytes, extension: picked.extension);
  }

  static Future<QuizQuestionImage> persistBytes(
    Uint8List bytes, {
    String? extension,
  }) async {
    if (bytes.isEmpty) throw ArgumentError.value(bytes, 'bytes', '图片不能为空');
    final digest = sha256.convert(bytes).toString();
    final dHash = await computeDHash(bytes);
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'quiz_question_images'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final ext = _safeExtension(extension);
    final file = File(p.join(dir.path, '$digest.$ext'));
    if (!await file.exists()) await file.writeAsBytes(bytes, flush: true);
    return QuizQuestionImage(
      path: file.path,
      sha256: digest,
      perceptualHash: dHash,
    );
  }

  /// 64-bit dHash, encoded as the same 16 lowercase hex digits returned by the
  /// Android screenshot path. This lets gallery-uploaded reference images and
  /// live screen captures participate in one comparison algorithm.
  static Future<String> computeDHash(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 9,
      targetHeight: 8,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw const FormatException('无法读取图片像素');
      final pixels = data.buffer.asUint8List();
      var value = 0;
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          final left = _luminance(pixels, y * 9 + x);
          final right = _luminance(pixels, y * 9 + x + 1);
          value = (value << 1) | (left > right ? 1 : 0);
        }
      }
      return value.toRadixString(16).padLeft(16, '0');
    } finally {
      image.dispose();
      codec.dispose();
    }
  }

  static int _luminance(Uint8List pixels, int pixelIndex) {
    final offset = pixelIndex * 4;
    return (pixels[offset] * 299 +
            pixels[offset + 1] * 587 +
            pixels[offset + 2] * 114) ~/
        1000;
  }

  static String _safeExtension(String? raw) {
    final ext = (raw ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return switch (ext) {
      'jpg' || 'jpeg' || 'png' || 'webp' || 'gif' => ext,
      _ => 'png',
    };
  }
}
