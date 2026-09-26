import 'package:box/features/extensions/plugins/server_ops/server_ops_help.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('凭据小抄（用户："我怕忘记了"→ 放进 App 随手能翻）', () {
    test('四栏对应关系与生成命令都在', () {
      for (final must in opsCredentialHelpMustMention) {
        expect(opsCredentialHelpText, contains(must), reason: '漏了：$must');
      }
    });

    test('四个坑都得点出来（这几条真机上全踩过）', () {
      expect(opsCredentialHelpText, contains('只存哈希'),
          reason: '口令丢了不可恢复 —— 不写清就会以为能找回来');
      expect(opsCredentialHelpText, contains('不能重签'));
      expect(opsCredentialHelpText, contains('基础名'),
          reason: 'revoke 用 ro- 前缀会假失败');
      expect(opsCredentialHelpText, contains('进不了终端'),
          reason: '只读凭据的作用域要说清楚');
    });

    test('填错的现象与修法对应得上（照着报错能定位）', () {
      expect(opsCredentialHelpText, contains('用户名或密码不正确'));
      expect(opsCredentialHelpText, contains('还没接只读接口'));
    });

    test('**一个口令/令牌都不许出现**（这页会被截屏）', () {
      // 43 位 base64url（设备令牌/通道口令的长度与字符集）
      final secretLike = RegExp(r'[A-Za-z0-9_-]{40,}');
      final hits = secretLike.allMatches(opsCredentialHelpText)
          .map((m) => m.group(0)!)
          .where((s) => !s.contains('/'))   // 路径里有长串斜杠分段，不算
          .toList();
      expect(hits, isEmpty, reason: '小抄里出现了像凭据的长串：\$hits');
      // 也不许出现常见的凭据字样 + 值的样子
      expect(opsCredentialHelpText.contains('Basic '), isFalse);
    });
  });
}
