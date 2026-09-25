// 服务器运维插件：连接设置的用例（构建注入默认值 + 本地覆盖）。
import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('构建注入的默认值', () {
    test('没填任何东西时，地址 / 用户名 / 终端地址都走默认值', () {
      const settings = ServerOpsSettings();
      expect(settings.effectiveBaseUrl, 'https://box.hpa888.top/dav');
      expect(settings.effectiveUser, 'boxops');
      expect(settings.effectiveTerminalUrl, 'https://box.hpa888.top/term/');
      expect(settings.usedBuildDefaults, isTrue);
    });

    test('默认值就是 dart-define 的那几个常量（改一处不会两处不一致）', () {
      expect(ServerOpsSettings.defaultBaseUrl, 'https://box.hpa888.top/dav');
      expect(ServerOpsSettings.defaultUser, 'boxops');
      expect(
        ServerOpsSettings.defaultTerminalUrl,
        'https://box.hpa888.top/term/',
      );
    });
  });

  group('用户覆盖', () {
    test('用户填过的以用户的为准', () {
      const settings = ServerOpsSettings(
        baseUrl: 'https://example.com/dav',
        user: 'someone',
        password: 'pw',
        terminalUrl: 'https://example.com/term/',
      );
      expect(settings.effectiveBaseUrl, 'https://example.com/dav');
      expect(settings.effectiveUser, 'someone');
      expect(settings.effectivePassword, 'pw');
      expect(settings.effectiveTerminalUrl, 'https://example.com/term/');
      expect(settings.hasPassword, isTrue);
      expect(settings.passwordFromBuild, isFalse);
    });

    test('空串 / 空白等于没填，回到构建默认', () {
      const settings = ServerOpsSettings(baseUrl: '  ', user: '');
      expect(settings.effectiveBaseUrl, ServerOpsSettings.defaultBaseUrl);
      expect(settings.effectiveUser, ServerOpsSettings.defaultUser);
    });

    test('口令只 trim 判断是否为空，不改变内容（尾随空格可能是口令的一部分）', () {
      const settings = ServerOpsSettings(password: ' pw ');
      expect(settings.effectivePassword, 'pw');
    });
  });

  group('本地持久化', () {
    test('键都带 serverOps.dav. 前缀（与远端存储插件的账户键分开）', () {
      expect(ServerOpsSettings.baseUrlKey, startsWith('serverOps.dav.'));
      expect(ServerOpsSettings.userKey, startsWith('serverOps.dav.'));
      expect(ServerOpsSettings.passwordKey, startsWith('serverOps.dav.'));
      expect(ServerOpsSettings.terminalUrlKey, startsWith('serverOps.dav.'));
    });

    test('保存后能读回来', () async {
      await const ServerOpsSettings().save(
        baseUrl: 'https://x.test/dav',
        user: 'ops',
        password: 'p@ss word',
        terminalUrl: 'https://x.test/term/',
      );

      final loaded = await ServerOpsSettings.load();
      expect(loaded.baseUrl, 'https://x.test/dav');
      expect(loaded.user, 'ops');
      expect(loaded.password, 'p@ss word', reason: '口令不该被 trim');
      expect(loaded.terminalUrl, 'https://x.test/term/');
    });

    test('只写非 null 的项：不传的字段保持原样', () async {
      await const ServerOpsSettings().save(user: 'ops');
      final loaded = await ServerOpsSettings.load();
      expect(loaded.user, 'ops');
      expect(loaded.baseUrl, isNull);
      expect(loaded.password, isNull);
    });

    test('空串 = 清掉这一项，回到构建默认', () async {
      await const ServerOpsSettings().save(user: 'ops', password: 'pw');
      await const ServerOpsSettings().save(user: '', password: '');
      final loaded = await ServerOpsSettings.load();
      expect(loaded.user, isNull);
      expect(loaded.password, isNull);
      expect(loaded.effectiveUser, ServerOpsSettings.defaultUser);
    });

    test('没存过就是全都没填（load 不抛异常）', () async {
      final loaded = await ServerOpsSettings.load();
      expect(loaded.baseUrl, isNull);
      expect(loaded.user, isNull);
      expect(loaded.password, isNull);
    });
  });
}
