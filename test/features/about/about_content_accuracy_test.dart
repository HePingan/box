import 'dart:io';

import 'package:box/features/about/data/about_content.dart';
import 'package:flutter_test/flutter_test.dart';

/// 关于页文案必须与真实代码一致。
///
/// 起因是真实翻车：初稿里写了「投屏」和「音量键下双击停止播放」两条功能，
/// 回读代码发现前者项目里根本没有实现、后者是答题悬浮窗的交互而不是播放器的。
/// 关于页是用户查功能和查操作路径的地方，写错等于骗人 —— 用户会照着找不存在
/// 的按钮，然后当成 bug 报上来。
///
/// 这些是**源码断言**而非行为测试：文案与功能不一致是内容问题，只有拿真实源码
/// 对照才能防住它。以后要在文案里写新功能，得先让功能真的存在。
void main() {
  String readLib(String path) => File('lib/$path').readAsStringSync();

  group('文案里提到的功能必须真实存在', () {
    test('不得出现项目里没有实现的功能词', () {
      final allText = [
        ...AboutContent.introduction.expand(
          (s) => [s.title, ...s.paragraphs, ...s.bullets],
        ),
        ...AboutContent.usageDocs.expand(
          (s) => [s.title, ...s.paragraphs, ...s.bullets],
        ),
        ...AboutContent.tutorials.expand((t) => [t.title, t.description]),
      ].join('\n');

      // 「投屏」曾被误写进介绍。lib/ 里没有任何投屏实现，
      // 加回来之前必须先真的做出这个功能。
      expect(
        allText.contains('投屏'),
        isFalse,
        reason: 'lib/ 里没有投屏实现，文案不能写；真要写请先实现功能',
      );

      // 音量键在项目里只用于小说阅读器翻页，不是播放器停止。
      expect(
        allText.contains('音量键下双击'),
        isFalse,
        reason: '音量键在本项目里是小说阅读器翻页，不是播放器停止播放',
      );
    });

    test('倍速与选集是真实存在的播放器能力', () {
      expect(
        readLib('video/widgets/player/custom_video_controls.dart')
            .contains('倍速'),
        isTrue,
        reason: '文案写了倍速，播放器里必须真有',
      );
      expect(
        readLib('video/pages/video_detail_page.dart').contains('选集'),
        isTrue,
        reason: '文案写了选集，详情页里必须真有',
      );
    });

    test('音量键翻页是小说阅读器的真实能力', () {
      expect(
        readLib('novel/core/models.dart').contains('音量键翻页'),
        isTrue,
        reason: '文案写了音量键翻页，阅读器设置里必须真有这个开关',
      );
    });
  });

  group('文案里的入口路径必须与真实入口名一致', () {
    test('「备份与恢复」是抽屉里的真实入口名（不是"备份导出"）', () {
      final drawer = readLib('app_drawer.dart');
      expect(drawer.contains("title: '备份与恢复'"), isTrue);

      final mentions = [
        ...AboutContent.usageDocs.expand(
          (s) => [...s.paragraphs, ...s.bullets],
        ),
        ...AboutContent.tutorials.map((t) => t.description),
      ].join('\n');

      expect(
        mentions.contains('备份与恢复'),
        isTrue,
        reason: '文案该用真实入口名，用户才找得到',
      );
      expect(
        mentions.contains('备份导出'),
        isFalse,
        reason: '「备份导出」不是真实入口名，会让用户在侧边栏里找不到',
      );
    });

    test('「书源管理」是真实入口，文案不得写成「内容源管理」', () {
      // 真实页面：lib/novel/pages/source_manager/book_source_manager_page.dart
      expect(
        File('lib/novel/pages/source_manager/book_source_manager_page.dart')
            .existsSync(),
        isTrue,
      );

      final mentions = [
        ...AboutContent.usageDocs.expand(
          (s) => [...s.paragraphs, ...s.bullets],
        ),
        ...AboutContent.tutorials.map((t) => t.description),
      ].join('\n');

      expect(mentions.contains('书源管理'), isTrue);
      expect(
        mentions.contains('内容源管理'),
        isFalse,
        reason: '侧边栏里没有叫「内容源管理」的入口',
      );
    });

    test('「调试日志」入口名与抽屉一致', () {
      expect(readLib('app_drawer.dart').contains("title: '调试日志'"), isTrue);
      final mentions = AboutContent.usageDocs
          .expand((s) => [...s.paragraphs, ...s.bullets])
          .join('\n');
      expect(mentions.contains('调试日志'), isTrue);
      expect(
        mentions.contains('仅看警告与错误'),
        isTrue,
        reason: '这是报障时降噪的关键一步，文档里要写明',
      );
    });
  });

  group('教程条目', () {
    test('没有链接的条目不做成可点的假链接', () {
      for (final t in AboutContent.tutorials) {
        if (!t.hasLink) {
          expect(t.url, anyOf(isNull, isEmpty));
        }
      }
    });

    test('有链接的条目必须是 https', () {
      for (final t in AboutContent.tutorials.where((t) => t.hasLink)) {
        expect(
          t.url!.startsWith('https://'),
          isTrue,
          reason: '明文 http 链接会被中间人改写',
        );
      }
    });

    test('仓库与反馈地址指向真实项目', () {
      expect(AboutContent.repoUrl, 'https://github.com/HePingan/box');
      expect(
        AboutContent.issuesUrl,
        startsWith('https://github.com/HePingan/box'),
      );
      // 抽屉里的反馈地址是同一个，避免两处不一致
      expect(
        readLib('app_drawer.dart').contains('github.com/HePingan/box/issues'),
        isTrue,
      );
    });
  });
}
