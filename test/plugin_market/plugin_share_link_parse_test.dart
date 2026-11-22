// 深链解析：`boxapp://plugin?c=CODE` → CODE。
//
// 这是深链唯一的纯逻辑，也是最容易出问题的地方 —— 用户从聊天里复制的
// 往往不是干净的链接，而是「快来看这个插件 boxapp://plugin?c=7K2M9Q 超好用」
// 这样一整段，或者排版折断成「7K2M 9Q」。解析器必须把这些都认出来，
// 又不能在认不出时把垃圾当码去请求服务端。

import 'package:box/features/extensions/market/data/plugin_share_link_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('深链解析', () {
    test('干净深链', () {
      expect(PluginShareLinkChannel.parseShareCode('boxapp://plugin?c=7K2M9Q'), '7K2M9Q');
    });

    test('小写码也规范成大写', () {
      expect(PluginShareLinkChannel.parseShareCode('boxapp://plugin?c=7k2m9q'), '7K2M9Q');
    });

    test('scheme 大小写不敏感', () {
      expect(
        PluginShareLinkChannel.parseShareCode('BOXAPP://PLUGIN?c=7K2M9Q'),
        '7K2M9Q',
      );
    });

    test('夹在一段话里的深链', () {
      expect(
        PluginShareLinkChannel.parseShareCode(
          '快来看这个插件 boxapp://plugin?c=7K2M9Q 挺好用的',
        ),
        '7K2M9Q',
      );
    });

    test('纯裸码', () {
      expect(PluginShareLinkChannel.parseShareCode('7K2M9Q'), '7K2M9Q');
    });

    test('被排版折断的裸码（中间有空格）', () {
      expect(PluginShareLinkChannel.parseShareCode('7K2M 9Q'), '7K2M9Q');
    });

    test('前后带空白', () {
      expect(PluginShareLinkChannel.parseShareCode('  7K2M9Q  '), '7K2M9Q');
    });

    test('空串与 null 返回空', () {
      expect(PluginShareLinkChannel.parseShareCode(''), '');
      expect(PluginShareLinkChannel.parseShareCode(null), '');
      expect(PluginShareLinkChannel.parseShareCode('   '), '');
    });

    test('别的 scheme 不认（避免把外站链接当码）', () {
      expect(PluginShareLinkChannel.parseShareCode('https://evil.test/?c=7K2M9Q'), '');
      expect(PluginShareLinkChannel.parseShareCode('boxapp://other?c=7K2M9Q'), '');
    });

    test('常见中文句子不会被当成码', () {
      expect(PluginShareLinkChannel.parseShareCode('这是一个插件分享'), '');
    });

    test('超长字符串不当码', () {
      expect(PluginShareLinkChannel.parseShareCode('A' * 40), '');
    });

    test('带标点的不当码', () {
      expect(PluginShareLinkChannel.parseShareCode('7K2M9Q!'), '');
      expect(PluginShareLinkChannel.parseShareCode('7K2M-9Q'), '');
    });
  });

  group('深链生成', () {
    test('buildLink 与 parseShareCode 互为逆运算', () {
      const code = '7K2M9Q';
      final link = PluginShareLinkChannel.buildLink(code);
      expect(link, 'boxapp://plugin?c=7K2M9Q');
      expect(PluginShareLinkChannel.parseShareCode(link), code);
    });

    test('小写码生成时也被规范', () {
      expect(
        PluginShareLinkChannel.buildLink('7k2m9q'),
        'boxapp://plugin?c=7K2M9Q',
      );
    });
  });
}
