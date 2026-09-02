import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// MainActivity 必须显式声明支持 resize。
///
/// 背景：这是个会被用户拿去小窗看小说的阅读类 App，却一直没声明
/// resizeableActivity。targetSdk=36 时未声明会让部分 ROM
/// （红米 K80 / HyperOS 的 freeform）走自己的兼容缩放路径，
/// 而不是标准 resize 路径，加剧小窗缩放时的 surface 尺寸协商问题。
///
/// 注意这条改动会改变已正常设备（iQOO/OriginOS）的小窗行为，
/// 所以是需要真机验证的那一类，不是纯资源改动。
void main() {
  const manifestPath = 'android/app/src/main/AndroidManifest.xml';

  String readManifest() {
    final f = File(manifestPath);
    expect(f.existsSync(), isTrue, reason: 'AndroidManifest.xml 不存在');
    return f.readAsStringSync();
  }

  /// 取出 MainActivity 那个 <activity> 块。
  String mainActivityBlock(String xml) {
    final m = RegExp(
      r'<activity\b[^>]*android:name="\.MainActivity".*?(?=</activity>)',
      dotAll: true,
    ).firstMatch(xml);
    expect(
      m,
      isNotNull,
      reason: 'MainActivity 的 <activity> 块找不到了，manifest 结构变了',
    );
    return m!.group(0)!;
  }

  group('MainActivity 支持小窗 resize', () {
    test('显式声明 resizeableActivity="true"', () {
      final block = mainActivityBlock(readManifest());
      expect(
        RegExp(r'android:resizeableActivity\s*=\s*"true"').hasMatch(block),
        isTrue,
        reason: '未声明 resizeableActivity="true"，部分 ROM 的小窗会走'
            '兼容缩放路径而非标准 resize',
      );
    });

    test('尺寸类 configChanges 仍然齐全，Activity 不因缩放重建', () {
      // 声明支持 resize 之后，系统会真的按标准路径下发尺寸变化。
      // 这几项若缺失，小窗每次拖拽都会重建 Activity ——
      // 阅读进度和播放状态会丢，比白屏更严重。
      final block = mainActivityBlock(readManifest());
      final m = RegExp(
        r'android:configChanges\s*=\s*"([^"]+)"',
      ).firstMatch(block);
      expect(m, isNotNull, reason: 'configChanges 声明被删了');
      final declared = m!.group(1)!.split('|').map((e) => e.trim()).toSet();

      for (final required in const [
        'screenSize',
        'smallestScreenSize',
        'screenLayout',
        'density',
        'orientation',
      ]) {
        expect(
          declared,
          contains(required),
          reason: 'configChanges 缺 $required —— 小窗缩放会重建 Activity，'
              '丢失阅读进度',
        );
      }
    });
  });
}
