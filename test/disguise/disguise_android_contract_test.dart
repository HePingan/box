import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「伪装成计算器」的**契约测试**：Dart 侧看不见的东西全部靠这里守。
///
/// 这些都是 Android 侧的资源与声明，编译期不报错、运行起来才炸，而且炸的方式
/// 很像"没反应"：图标没变、桌上出现两个图标、通知里露出真应用的字样。
///
/// 对应关系：
/// - `android/app/src/main/AndroidManifest.xml` 的 activity-alias ←→ `DisguiseController`
/// - `res/mipmap-*/ic_calculator.png`（真机 app_icon 的原样字节）←→ manifest 里的 `@mipmap/ic_calculator`
/// - 原生通知的 `setContentTitle` ←→ `DisguiseNotifications`
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  final resDir = Directory('android/app/src/main/res');
  final kotlinDir = Directory('android/app/src/main/kotlin/top/hpa888/box');

  String manifestXml() {
    expect(manifest.existsSync(), isTrue, reason: 'AndroidManifest.xml 不见了');
    return manifest.readAsStringSync();
  }

  String readRes(String relative) {
    final file = File('${resDir.path}/$relative');
    expect(file.existsSync(), isTrue, reason: '$relative 不存在');
    return file.readAsStringSync();
  }

  /// 取出 activity-alias 那一整块。
  String aliasBlock(String xml) {
    final match = RegExp(
      '<activity-alias[^>]*android:name="\\.CalculatorAlias".*?</activity-alias>',
      dotAll: true,
    ).firstMatch(xml);
    expect(
      match,
      isNotNull,
      reason:
          'manifest 里没有 .CalculatorAlias —— 伪装切换的落点没了，'
          'DisguiseController 会把 setComponentEnabledSetting 打在空处',
    );
    return match!.group(0)!;
  }

  group('AndroidManifest：双 launcher 入口', () {
    test('存在 .CalculatorAlias，指向 MainActivity 且默认关闭', () {
      final block = aliasBlock(manifestXml());
      expect(block, contains('android:targetActivity=".MainActivity"'));
      expect(
        block,
        contains('android:enabled="false"'),
        reason: '别名默认必须是关的：新装用户看到的应该是「极客匣」',
      );
      expect(
        block,
        contains('android.intent.category.LAUNCHER'),
        reason: '别名没有 LAUNCHER 类别就不会出现在桌面，伪装等于没做',
      );
    });

    test('别名用的是伪装图标与「计算器」这个名字', () {
      final block = aliasBlock(manifestXml());
      expect(block, contains('android:icon="@mipmap/ic_calculator"'));
      expect(
        block,
        contains('android:label="计算器"'),
        reason: '被仿的 vivo 计算器在中文环境下的 app_name 就是「计算器」',
      );
    });

    test('别名声明了 APP_CALCULATOR（系统级「计算器」入口要落到别名上）', () {
      final block = aliasBlock(manifestXml());
      expect(
        block,
        contains('android.intent.category.APP_CALCULATOR'),
        reason:
            '被仿的 vivo 计算器主入口声明了 APP_CALCULATOR，语音“打开计算器”、'
            '系统快捷方式、跨应用 picker 全靠这个类别找应用；别名漏了它，'
            '这些入口就会指回「极客匣」真身，属于只在特定操作下才暴露的破绽',
      );
    });

    test('别名不复制真身的分享 filter（否则分享面板会露出「计算器」）', () {
      final block = aliasBlock(manifestXml());
      expect(block, isNot(contains('android.intent.action.SEND')));
      expect(block, isNot(contains('android.intent.action.SEND_MULTIPLE')));
    });

    test('真身的 LAUNCHER 入口仍然存在（关掉伪装要能回来）', () {
      final xml = manifestXml();
      final mainActivity = RegExp(
        '<activity\\s+android:name="\\.MainActivity".*?</activity>',
        dotAll: true,
      ).firstMatch(xml);
      expect(mainActivity, isNotNull, reason: 'MainActivity 声明没了');
      expect(
        mainActivity!.group(0)!,
        contains('android.intent.category.LAUNCHER'),
        reason: 'MainActivity 丢了 LAUNCHER，关闭伪装后桌面上就没有入口了',
      );
    });
  });

  group('图标资源', () {
    // 被仿的 vivo 计算器在 APK 里带两张图标：drawable/icon（浅底深符号）与
    // drawable/app_icon（深底浅符号 + 橙色等号）。真机桌面显示的是 app_icon，
    // 所以 mipmap 里必须是 app_icon 的原样字节（sha256 前 16 位钉死），
    // 而不是任何「照着重画」的产物 —— 重画再准也会画错那张脸。
    const expectedIcon = {
      // density: (sha256 前 16 位, 像素边长)
      'hdpi': ('b1d3bac8753f5fca', 32),
      'xhdpi': ('60d6c81847e8b846', 64),
      'xxhdpi': ('54c9756b1b92513f', 96),
      'xxxhdpi': ('3dfe400043bf84ed', 128),
    };

    test('图标就是真机那 4 张 PNG（哈希与像素尺寸都对得上）', () {
      expectedIcon.forEach((density, want) {
        final (wantHash, wantPx) = want;
        final file = File('${resDir.path}/mipmap-$density/ic_calculator.png');
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'mipmap-$density/ic_calculator.png 缺失。'
              '真机只需这 4 档（无 mdpi），缺了桌面会显示成透明方块',
        );
        final bytes = file.readAsBytesSync();
        final digest = sha256.convert(bytes).toString().substring(0, 16);
        expect(
          digest,
          wantHash,
          reason:
              'mipmap-$density/ic_calculator.png 的内容不是源 APK 里'
              'drawable/app_icon 的原样字节（期望 $wantHash，实际 $digest）。'
              '要换图标请用 tool/gen_disguise_icon.py 从源 APK 重新抽取，'
              '不要手绘或换用 drawable/icon 那张浅色图',
        );
        // PNG 头里的宽高：0x10 起 8 字节（宽 4、高 4，大端）
        final px = ByteData.sublistView(bytes, 16, 20).getUint32(0);
        expect(px, wantPx, reason: 'mipmap-$density 的像素边长应为 $wantPx，实际 $px');
      });
    });

    test('不提供自适应图标（真机没有，给了会被裁切放大）', () {
      for (final path in [
        'mipmap-anydpi-v26/ic_calculator.xml',
        'drawable/ic_calculator_foreground.xml',
        'drawable/ic_calculator_background.xml',
        'drawable-v26/ic_calculator_background.xml',
      ]) {
        expect(
          File('${resDir.path}/$path').existsSync(),
          isFalse,
          reason:
              '$path 不该存在。被仿的应用没有自适应图标，桌面走位图路径；'
              '我们给 anydpi-v26 会让桌面把 108dp 裁到可见 72dp 再套蒙版，'
              '相当于把图标放大约 1.5 倍并切边，这就是「变形」的来源',
        );
      }
    });

    test('旧的 ic_calculator_* 取色已清除（避免有人照着老方案加回来）', () {
      final colors = readRes('values/colors.xml');
      expect(
        RegExp(r'<color\s+name="ic_calculator').hasMatch(colors),
        isFalse,
        reason:
            '图标颜色已全部烘进 mipmap PNG，colors.xml 里不该再有 '
            'ic_calculator_* 取色；有的话说明有人正在恢复那套矢量/自适应方案',
      );
    });
  });

  group('原生侧接线', () {
    test('MainActivity 注册了伪装通道', () {
      final source = File(
        '${kotlinDir.path}/MainActivity.kt',
      ).readAsStringSync();
      expect(
        source,
        contains('DisguiseController.attach('),
        reason: '没有注册通道，Dart 侧所有切换图标/遮缩略图的调用都是空转',
      );
    });

    test('切换组件时带 DONT_KILL_APP（否则点一下开关就闪退）', () {
      final source = File(
        '${kotlinDir.path}/DisguiseController.kt',
      ).readAsStringSync();
      final calls = RegExp(
        'setComponentEnabledSetting\\(',
      ).allMatches(source).length;
      // 只数**实参位置**上的那次（带尾逗号），KDoc 里提到的 [PackageManager.DONT_KILL_APP]
      // 不该被算进覆盖率里 —— 否则"注释写得越多测试越绿"。
      final safe = RegExp('DONT_KILL_APP,').allMatches(source).length;
      expect(calls, greaterThanOrEqualTo(4), reason: '真身与别名各两处切换');
      expect(
        safe,
        calls,
        reason:
            '每一处 setComponentEnabledSetting 都必须带 DONT_KILL_APP，'
            '少一处系统就会为了组件变更杀掉本进程',
      );
    });

    test('所有原生通知的标题都过 DisguiseNotifications', () {
      final sources = kotlinDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.kt'))
          .map((f) => f.readAsStringSync())
          .toList();
      final rawTitles = sources
          .expand((s) => RegExp('setContentTitle\\(').allMatches(s))
          .length;
      final masked = sources
          .expand(
            (s) => RegExp('DisguiseNotifications\\.title\\(').allMatches(s),
          )
          .length;
      expect(rawTitles, greaterThan(0));
      expect(
        masked,
        rawTitles,
        reason:
            '有 $rawTitles 处 setContentTitle，但只有 $masked 处经过伪装 —— '
            '剩下的会在通知栏里直接写着业务名词',
      );
    });
  });
}
