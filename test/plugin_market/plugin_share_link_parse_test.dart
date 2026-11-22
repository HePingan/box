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

    test('https 落地页地址（App Links 扫码直进时就长这样）', () {
      expect(
        PluginShareLinkChannel.parseShareCode('https://box.hpa888.top/p/7K2M9Q'),
        '7K2M9Q',
      );
      // 带查询参数/尾斜杠也认
      expect(
        PluginShareLinkChannel.parseShareCode('https://box.hpa888.top/p/7K2M9Q?from=qr'),
        '7K2M9Q',
      );
    });

    test('别的域名 /p/ 路径不认（只认自己的域名）', () {
      expect(
        PluginShareLinkChannel.parseShareCode('https://evil.test/p/7K2M9Q'),
        '',
      );
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
    test('buildLink 出的是 https 网址（二维码用），且能解析回码', () {
      const code = '7K2M9Q';
      final link = PluginShareLinkChannel.buildLink(code);
      expect(link, 'https://box.hpa888.top/p/7K2M9Q');
      expect(PluginShareLinkChannel.parseShareCode(link), code);
    });

    test('schemeLink 出的是自建 scheme（落地页按钮用）', () {
      expect(
        PluginShareLinkChannel.schemeLink('7K2M9Q'),
        'boxapp://plugin?c=7K2M9Q',
      );
    });

    test('小写码生成时也被规范', () {
      expect(
        PluginShareLinkChannel.buildLink('7k2m9q'),
        'https://box.hpa888.top/p/7K2M9Q',
      );
    });
  });
}
