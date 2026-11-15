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
/// - `res/mipmap-*/ic_calculator.png`（真机 app_icon 拟合出的矢量，按 48dp 各密度重渲染）←→ manifest 里的 `@mipmap/ic_calculator`
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

  // 「设置 → 应用管理」里的名字与图标读的是 ApplicationInfo.label/icon，与启用的
  // launcher 别名无关，运行时也改不了。用户在应用管理里搜「极」能搜到「极客匣」，
  // 就是这一层没改。所以 application 静态写「计算器」+ 计算器图标，桌面那枚真身
  // 靠 MainActivity 自己覆写回「极客匣」+ 盒子图标 —— 三层各写各的，是有意的。
  group('AndroidManifest：应用管理里的名字（application 层）', () {
    test('application 的 label/icon 是计算器，不是极客匣', () {
      final app = RegExp(
        '<application\\s[^>]*>',
        dotAll: true,
      ).firstMatch(manifestXml());
      expect(app, isNotNull, reason: 'manifest 里没有 <application> 标签');
      final block = app!.group(0)!;
      expect(
        block,
        contains('android:label="计算器"'),
        reason:
            'application 的 label 决定「设置 → 应用管理」里的名字与搜索匹配。'
            '写成「极客匣」的话，在应用管理里搜「极」照样能搜到，'
            'C 档的隐蔽就漏在这一层',
      );
      expect(
        block,
        contains('android:icon="@mipmap/ic_calculator"'),
        reason:
            'application 的 icon 决定应用管理列表/详情里的图标。'
            '留着盒子图标会出现「名字是计算器、图标是极客匣」的矛盾组合',
      );
    });

    test('MainActivity 覆写回「极客匣」+ 盒子图标（关掉伪装时桌面那枚）', () {
      final mainActivity = RegExp(
        '<activity\\s+android:name="\\.MainActivity".*?</activity>',
        dotAll: true,
      ).firstMatch(manifestXml());
      expect(mainActivity, isNotNull, reason: 'MainActivity 声明没了');
      final block = mainActivity!.group(0)!;
      expect(
        block,
        contains('android:label="极客匣"'),
        reason:
            'MainActivity 不覆写 label 就会继承 application 的「计算器」，'
            '关闭伪装后桌面上那枚真身入口会显示成计算器',
      );
      expect(
        block,
        contains('android:icon="@mipmap/ic_launcher"'),
        reason: 'MainActivity 不覆写 icon，关掉伪装后桌面图标会变成计算器',
      );
    });
  });

  group('图标资源', () {
    // 被仿的 vivo 计算器在 APK 里带两张图标：drawable/icon（浅底深符号，只一档 136px）与
    // drawable/app_icon（深底浅符号 + 橙色等号）。真机桌面显示的是 app_icon —— 这条
    // 变体判断是第一位的，脸画错了比糊更致命。
    //
    // 但「只拷字节」有天花板：源 APK 里 app_icon 最大只到 128×128（vivo 是按 32dp 出
    // 的图），而 Android 桌面槽位是 48dp（xxxhdpi 要 192px）。128px 被桌面放大就是
    // 「图标还是糊」的直接原因。所以现在由 tool/gen_disguise_icon.py 从那张 128px
    // 拟合出矢量、按 48dp 各密度重新栅格化，并把自身渲的 96/128px 与源 APK 位图逐像素
    // 比对（当前 平均误差 2.2/255、95% 像素三通道差 ≤24、轮廓逐行一致）来保证
    // 「还是同一张脸」。这里钉死 5 档的哈希与边长。
    const expectedIcon = {
      // density: (sha256 前 16 位, 像素边长) —— 48dp 语义
      'mdpi': ('a1d851b7aae129f2', 48),
      'hdpi': ('e6ab504635715868', 72),
      'xhdpi': ('df9ccb3465bb6fed', 96),
      'xxhdpi': ('cfdea0cb0b8b62bf', 144),
      'xxxhdpi': ('2ae1e5ec78d5cfae', 192),
    };

    test('伪装图标 5 档齐全，哈希与像素尺寸都对得上', () {
      expectedIcon.forEach((density, want) {
        final (wantHash, wantPx) = want;
        final file = File('${resDir.path}/mipmap-$density/ic_calculator.png');
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'mipmap-$density/ic_calculator.png 缺失。'
              'mdpi…xxxhdpi 五档都要有，缺了对应密度的桌面会去放大邻居、'
              '或者干脆显示成透明方块',
        );
        final bytes = file.readAsBytesSync();
        final digest = sha256.convert(bytes).toString().substring(0, 16);
        expect(
          digest,
          wantHash,
          reason:
              'mipmap-$density/ic_calculator.png 不是生成器产出的那张'
              '（期望 $wantHash，实际 $digest）。要换图标请用 '
              'tool/gen_disguise_icon.py --apk <vivo 计算器.apk> 重新生成，'
              '不要手绘、也不要换用 drawable/icon 那张浅色图',
        );
        // PNG 头里的宽高：0x10 起 8 字节（宽 4、高 4，大端）
        final px = ByteData.sublistView(bytes, 16, 20).getUint32(0);
        expect(px, wantPx, reason: 'mipmap-$density 的像素边长应为 $wantPx，实际 $px');
      });
    });

    test('xxxhdpi 必须是 192px（48dp），退回 128px 就会糊', () {
      final bytes = File(
        '${resDir.path}/mipmap-xxxhdpi/ic_calculator.png',
      ).readAsBytesSync();
      final px = ByteData.sublistView(bytes, 16, 20).getUint32(0);
      expect(
        px,
        greaterThanOrEqualTo(192),
        reason:
            '源 APK 里 app_icon 最大只有 128px（32dp），直接拷字节会让桌面自己放大到 '
            '192px 以上、边缘和笔画全糊 —— 这就是「伪装计算器图标还是很糊」的成因。'
            'xxxhdpi 请用生成器按 48dp 渲 192px',
      );
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
