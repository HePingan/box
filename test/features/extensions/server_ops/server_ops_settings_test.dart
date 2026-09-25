// 服务器运维插件：连接设置的用例（构建注入的地址默认值 + 口令只存本机加密存储）。
//
// C1 中期档的口径变了：**口令不再随安装包分发**，只由用户输入并存在加密存储里。
// 所以这里多两件必须守住的事：
//   * 没配过口令时 effectivePassword 必须是空（安装包里不能有任何口令字节）；
//   * 289 及以前放在 SharedPreferences 里的明文口令要做一次性迁移，且明文键要删掉。
import 'package:box/features/extensions/plugins/server_ops/server_ops_secret_store.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeStore implements OpsSecretStore {
  _FakeStore([this.value]);

  String? value;
  int writes = 0;
  int clears = 0;

  @override
  Future<String?> readPassword() async => value;

  @override
  Future<void> writePassword(String password) async {
    value = password;
    writes++;
  }

  @override
  Future<void> clearPassword() async {
    value = null;
    clears++;
  }
}

void main() {
  late _FakeStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = _FakeStore();
    debugSetOpsSecretStore(store);
  });

  tearDown(() => debugSetOpsSecretStore());

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

    test('口令没有任何内置默认值 —— 安装包里不该带服务器口令', () {
      const settings = ServerOpsSettings();
      expect(settings.effectivePassword, isEmpty);
      expect(settings.hasPassword, isFalse, reason: '没配过就是没配过');
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

    test('保存后能读回来（口令走加密存储，不进 SharedPreferences）', () async {
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
      expect(store.value, 'p@ss word', reason: '口令要落到加密存储');

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(ServerOpsSettings.passwordKey),
        isNull,
        reason: '明文键必须保持空 —— 密码不该出现在 SharedPreferences 里',
      );
    });

    test('只写非 null 的项：不传的字段保持原样', () async {
      await const ServerOpsSettings().save(user: 'ops');
      final loaded = await ServerOpsSettings.load();
      expect(loaded.user, 'ops');
      expect(loaded.baseUrl, isNull);
      expect(loaded.password, isNull);
    });

    test('空串 = 清掉这一项（口令清的是加密存储）', () async {
      await const ServerOpsSettings().save(user: 'ops', password: 'pw');
      await const ServerOpsSettings().save(user: '', password: '');
      final loaded = await ServerOpsSettings.load();
      expect(loaded.user, isNull);
      expect(loaded.password, isNull);
      expect(loaded.effectiveUser, ServerOpsSettings.defaultUser);
      expect(store.value, isNull);
      expect(store.clears, greaterThan(0));
    });

    test('没存过就是全都没填（load 不抛异常）', () async {
      final loaded = await ServerOpsSettings.load();
      expect(loaded.baseUrl, isNull);
      expect(loaded.user, isNull);
      expect(loaded.password, isNull);
    });

    test('老版本的明文口令一次性迁移进加密存储，并删掉明文键', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ServerOpsSettings.passwordKey: 'legacy-pw',
        ServerOpsSettings.userKey: 'boxops',
      });

      final loaded = await ServerOpsSettings.load();

      expect(loaded.password, 'legacy-pw', reason: '老用户不该被要求重输');
      expect(store.value, 'legacy-pw', reason: '要搬进加密存储');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(ServerOpsSettings.passwordKey),
        isNull,
        reason: '迁移后明文键必须删掉，否则等于没改',
      );
    });
  });
}
