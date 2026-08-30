import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 识图模型（MobileNetV3-Small tflite）整链路移除的回归锁。
///
/// 移除依据：`QuizPluginEntry.captureImageRegionEmbedding` 全仓零调用方，
/// 即 embedding 从来没有被生产过——模型接线完整但永不触发。去歧义实际
/// 依赖的是 `imageRegionHash`（dHash，Kotlin 侧纯算法实现，不需要模型）。
///
/// 这些断言防止「模型或其原生依赖被无意重新引入」：一旦有人再加
/// tensorflow-lite 依赖或把 .tflite 塞回 assets，APK 会重新胖 8MB。
void main() {
  final projectRoot = Directory.current.path;

  group('识图模型资产与原生依赖已移除', () {
    test('assets 下不存在 .tflite 模型文件', () {
      final androidAssets = Directory('$projectRoot/android/app/src/main/assets');
      final tfliteFiles = <String>[];
      if (androidAssets.existsSync()) {
        for (final entity in androidAssets.listSync(recursive: true)) {
          if (entity is File && entity.path.endsWith('.tflite')) {
            tfliteFiles.add(entity.path);
          }
        }
      }
      expect(
        tfliteFiles,
        isEmpty,
        reason: '模型文件应已删除，发现残留：$tfliteFiles',
      );
    });

    test('Gradle 不再依赖 tensorflow-lite', () {
      final gradle = File('$projectRoot/android/app/build.gradle.kts');
      expect(gradle.existsSync(), isTrue);
      final content = gradle.readAsStringSync();
      expect(
        content.contains('tensorflow'),
        isFalse,
        reason: 'tensorflow-lite 依赖应已移除（会带入 3.8MB libtensorflowlite_jni.so）',
      );
    });

    test('Kotlin 侧 QuizImageEmbedder 已删除且无引用', () {
      final embedder = File(
        '$projectRoot/android/app/src/main/kotlin/top/hpa888/box/QuizImageEmbedder.kt',
      );
      expect(
        embedder.existsSync(),
        isFalse,
        reason: 'QuizImageEmbedder.kt 应已删除',
      );

      final mainActivity = File(
        '$projectRoot/android/app/src/main/kotlin/top/hpa888/box/MainActivity.kt',
      );
      expect(mainActivity.existsSync(), isTrue);
      final content = mainActivity.readAsStringSync();
      expect(
        content.contains('QuizImageEmbedder'),
        isFalse,
        reason: 'MainActivity 不应再引用 QuizImageEmbedder',
      );
      expect(
        content.contains('embedQuizImage'),
        isFalse,
        reason: 'embedQuizImage channel handler 应已移除',
      );
    });

    test('Dart 侧 embedding 死链路已移除', () {
      final entry = File(
        '$projectRoot/lib/features/quiz_plugin/presentation/quiz_plugin_entry.dart',
      );
      expect(entry.existsSync(), isTrue);
      final content = entry.readAsStringSync();
      expect(
        content.contains('embedQuizImage'),
        isFalse,
        reason: 'Dart 侧 embedQuizImage 桥接应已移除',
      );
      expect(
        content.contains('captureImageRegionEmbedding'),
        isFalse,
        reason: '零调用方的 captureImageRegionEmbedding 应已移除',
      );
    });

    test('imageRegionHash 去歧义链路必须保留（不是模型链路）', () {
      final entry = File(
        '$projectRoot/lib/features/quiz_plugin/presentation/quiz_plugin_entry.dart',
      );
      final content = entry.readAsStringSync();
      expect(
        content.contains('captureImageRegionHashCached'),
        isTrue,
        reason: 'dHash 链路是现役去歧义手段，必须保留',
      );
    });
  });
}
