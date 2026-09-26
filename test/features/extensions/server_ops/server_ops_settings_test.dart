// 服务器运维插件：连接设置的用例（B1 多服务器模型）。
//
// 必须守住的事：
//   * 开箱即用**两台**（hpa888 / tencent175），地址与用户名来自 dart-define，两台各有默认值；
//   * 口令**不进模型、不进 SharedPreferences**：按服务器分键存本机加密存储
//     （`serverOps.dav.password.<id>`）；
//   * 289/290 的单服务器老配置要**一次性迁移**成一台 hpa888，并把它已存的口令搬到
//     `serverOps.dav.password.hpa888` 后删掉老键 —— 老用户升级后不该被要求重输口令；
//   * 删掉一台服务器时，它的口令键要一起清掉（不要留没人认领的口令）。
import 'package:box/features/extensions/plugins/server_ops/server_ops_secret_store.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 内存版加密存储：按服务器 id 一个键，另有单服务器时代的老键。
class _FakeStore implements OpsSecretStore {
  _FakeStore([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;
  String? legacy;

  int writes = 0;
  int clears = 0;

  @override
  Future<String?> readPassword(String serverId) async => values[serverId];

  @override
  Future<void> writePassword(String serverId, String password) async {
    values[serverId] = password;
    writes++;
  }

  @override
  Future<void> clearPassword(String serverId) async {
    values.remove(serverId);
    clears++;
  }

  /// 令牌表（与 [values] 分开：撤销令牌不该动口令）。
  final Map<String, String> tokens = <String, String>{};

  @override
  Future<String?> readApiToken(String serverId) async => tokens[serverId];

  @override
  Future<void> writeApiToken(String serverId, String token) async {
    tokens[serverId] = token;
  }

  @override
  Future<void> clearApiToken(String serverId) async {
    tokens.remove(serverId);
  }

  @override
  Future<String?> readLegacyPassword() async => legacy;

  @override
  Future<void> clearLegacyPassword() async {
    legacy = null;
  }
}

const ServerOpsServer _a = ServerOpsServer(
  id: 'a',
  label: 'A 机',
  baseUrl: 'https://a.test/dav',
  user: 'ua',
);
const ServerOpsServer _b = ServerOpsServer(
  id: 'b',
  label: 'B 机',
  baseUrl: 'https://b.test/dav',
  user: 'ub',
);

void main() {
  late _FakeStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = _FakeStore();
    debugSetOpsSecretStore(store);
  });

  tearDown(() => debugSetOpsSecretStore());

  group('构建注入的默认值', () {
    test('没保存过任何配置时，就是开箱即用的两台', () {
      const settings = ServerOpsSettings();
      expect(settings.effectiveServers, hasLength(2));
      expect(
        settings.effectiveServers.map((s) => s.id),
        ['hpa888', 'tencent175'],
      );
      expect(settings.currentServer.id, ServerOpsSettings.builtInHpa888Id);
    });

    test('内置两台的地址 / 用户名 / 终端地址 / 快照 id 都对得上', () {
      const primary = ServerOpsSettings.builtInHpa888;
      expect(primary.id, 'hpa888');
      expect(primary.label, '阿里云 · 主服务端');
      expect(primary.effectiveBaseUrl, 'https://box.hpa888.top/dav');
      expect(primary.effectiveUser, 'boxops');
      expect(primary.effectiveTerminalUrl, 'https://box.hpa888.top/term/');
      expect(primary.snapshotId, 'hpa888');

      const secondary = ServerOpsSettings.builtInTencent175;
      expect(secondary.id, 'tencent175');
      expect(secondary.label, '腾讯云 · 构建/监控机');
      expect(secondary.effectiveBaseUrl, 'https://box.hpa888.top/dav175');
      expect(secondary.effectiveUser, 'boxops');
      expect(secondary.effectiveTerminalUrl, 'https://box.hpa888.top/term175/');
      expect(secondary.snapshotId, 'tencent175');
    });

    test('默认值就是构建脚本注入的那几个常量（改一处不会两处不一致）', () {
      expect(ServerOpsSettings.defaultBaseUrl, 'https://box.hpa888.top/dav');
      expect(ServerOpsSettings.defaultUser, 'boxops');
      expect(
        ServerOpsSettings.defaultTerminalUrl,
        'https://box.hpa888.top/term/',
      );
      expect(
        ServerOpsSettings.defaultBaseUrl175,
        'https://box.hpa888.top/dav175',
      );
      expect(ServerOpsSettings.defaultUser175, 'boxops');
      expect(
        ServerOpsSettings.defaultTerminalUrl175,
        'https://box.hpa888.top/term175/',
      );
    });

    test('口令没有任何内置默认值 —— 安装包里不该带服务器口令', () {
      const settings = ServerOpsSettings();
      expect(settings.effectivePassword, isEmpty);
      expect(settings.hasPassword, isFalse, reason: '没配过就是没配过');
      expect(settings.hasPasswordFor('hpa888'), isFalse);
    });
  });

  group('一台服务器的生效值', () {
    test('用户填过的以用户的为准', () {
      const server = ServerOpsServer(
        id: 'x',
        label: 'X',
        baseUrl: 'https://example.com/dav',
        user: 'someone',
        terminalUrl: 'https://example.com/term/',
      );
      expect(server.effectiveBaseUrl, 'https://example.com/dav');
      expect(server.effectiveUser, 'someone');
      expect(server.effectiveTerminalUrl, 'https://example.com/term/');
      expect(server.usedBuildDefaults, isFalse);
    });

    test('内置的两台：空串回到**各自**的构建默认（不是主服务端那一套）', () {
      const hpa = ServerOpsServer(id: 'hpa888', label: '主服务端');
      expect(hpa.effectiveBaseUrl, ServerOpsSettings.defaultBaseUrl);
      expect(hpa.effectiveUser, ServerOpsSettings.defaultUser);
      expect(hpa.effectiveTerminalUrl, ServerOpsSettings.defaultTerminalUrl);

      const t175 = ServerOpsServer(id: 'tencent175', label: '构建机');
      expect(t175.effectiveBaseUrl, ServerOpsSettings.defaultBaseUrl175);
      expect(t175.effectiveUser, ServerOpsSettings.defaultUser175);
      expect(t175.effectiveTerminalUrl, ServerOpsSettings.defaultTerminalUrl175);
    });

    test('回归：175 没填终端地址时**不得**落到主服务端的 /term/（真机上就是这么 401 的）', () {
      // 真机现场（2026-09-26）：用户自己加的 175（id 不在内置名单里）终端地址留空，
      // 旧口径兜到 https://box.hpa888.top/term/（主服务端），拿 175 的凭据打它必然 401 ——
      // 而报错文案说的是"口令不对"，方向就查偏了。
      const mine = ServerOpsServer(
        id: 'my-175',
        label: '腾讯云 · 构建/监控机',
        baseUrl: 'https://box.hpa888.top/dav175',
      );
      expect(mine.effectiveTerminalUrl, 'https://box.hpa888.top/term175/');
      expect(mine.effectiveTerminalUrl, isNot(ServerOpsSettings.defaultTerminalUrl));
    });

    test('用户自己加的机器：地址/用户名没填就是空串，不静默借主服务端的', () {
      const mine = ServerOpsServer(id: 'srv-x', label: 'X');
      expect(mine.effectiveBaseUrl, isEmpty);
      expect(mine.effectiveUser, isEmpty);
      expect(mine.effectiveTerminalUrl, isEmpty);
    });

    test('推不出 /termX/ 就不猜（别的路径形状一律留空）', () {
      const mine = ServerOpsServer(
        id: 'srv-y',
        label: 'Y',
        baseUrl: 'https://example.com/remote.php/dav/files/me',
      );
      expect(mine.effectiveTerminalUrl, isEmpty);
    });

    test('snapshotId 留空就用 id（用户自己加的机器没有快照行）', () {
      const server = ServerOpsServer(id: 'srv1', label: 'X');
      expect(server.effectiveSnapshotId, 'srv1');
      expect(server.copyWith(snapshotId: 'hpa888').effectiveSnapshotId, 'hpa888');
    });

    test('口令只 trim 判断是否为空，不改变内容（尾随空格可能是口令的一部分）', () {
      const settings = ServerOpsSettings(
        servers: [_a],
        selectedServerId: 'a',
        passwords: {'a': ' pw '},
      );
      expect(settings.effectivePassword, 'pw');
      expect(settings.passwordFor('a'), ' pw ', reason: '存的那份不 trim');
    });
  });

  group('本地持久化', () {
    test('键都带 serverOps.dav. 前缀（与远端存储插件的账户键分开）', () {
      expect(ServerOpsSettings.serversKey, startsWith('serverOps.dav.'));
      expect(ServerOpsSettings.selectedKey, startsWith('serverOps.dav.'));
      expect(ServerOpsSettings.baseUrlKey, startsWith('serverOps.dav.'));
      expect(ServerOpsSettings.userKey, startsWith('serverOps.dav.'));
      expect(ServerOpsSettings.terminalUrlKey, startsWith('serverOps.dav.'));
      expect(ServerOpsSettings.passwordKey, startsWith('serverOps.dav.'));
    });

    test('口令按服务器分键：serverOps.dav.password.<id>', () {
      expect(
        KeystoreOpsSecretStore.keyFor('hpa888'),
        'serverOps.dav.password.hpa888',
      );
      expect(
        KeystoreOpsSecretStore.keyFor('tencent175'),
        'serverOps.dav.password.tencent175',
      );
      expect(
        KeystoreOpsSecretStore.keyFor('a'),
        isNot(KeystoreOpsSecretStore.keyFor('b')),
        reason: '两台机器不能共用一个口令键',
      );
    });

    test('保存两台 + 当前选择 + 口令后能读回来（口令不进 SharedPreferences）', () async {
      await const ServerOpsSettings().save(
        servers: [_a, _b],
        selectedServerId: 'b',
        passwords: {'a': 'pw-a', 'b': 'pw-b'},
      );

      final loaded = await ServerOpsSettings.load();
      expect(loaded.servers.map((s) => s.id), ['a', 'b']);
      expect(loaded.selectedServerId, 'b');
      expect(loaded.currentServer.label, 'B 机');
      expect(loaded.effectiveBaseUrl, 'https://b.test/dav');
      expect(loaded.passwordFor('a'), 'pw-a');
      expect(loaded.passwordFor('b'), 'pw-b');
      expect(loaded.hasPassword, isTrue);
      expect(store.values['a'], 'pw-a', reason: '要落到分服务器键');
      expect(store.values['b'], 'pw-b');

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(ServerOpsSettings.passwordKey),
        isNull,
        reason: '明文键必须保持空 —— 密码不该出现在 SharedPreferences 里',
      );
      expect(
        prefs.getString(ServerOpsSettings.serversKey),
        isNot(contains('pw-a')),
        reason: '口令也不许混进服务器列表的 JSON',
      );
    });

    test('只传 selectedServerId 时不动列表（切换当前服务器）', () async {
      await const ServerOpsSettings().save(servers: [_a, _b], passwords: {'a': 'pw'});
      final switched =
          await (await ServerOpsSettings.load()).save(selectedServerId: 'b');

      expect(switched.servers.map((s) => s.id), ['a', 'b']);
      expect(switched.effectiveSelectedServerId, 'b');
      final reloaded = await ServerOpsSettings.load();
      expect(reloaded.effectiveSelectedServerId, 'b', reason: '选择要持久化');
    });

    test('选中的 id 不存在时退回第一台（总得有一台能用）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ServerOpsSettings.serversKey:
            '[{"id":"a","label":"A 机"},{"id":"b","label":"B 机"}]',
        ServerOpsSettings.selectedKey: 'gone',
      });
      final loaded = await ServerOpsSettings.load();
      expect(loaded.currentServer.id, 'a');
      expect(loaded.effectiveSelectedServerId, 'a');
    });

    test('没有老数据时不写新键（保持"用户还没保存过"这个状态）', () async {
      final loaded = await ServerOpsSettings.load();
      expect(loaded.servers, isEmpty, reason: '空 = 用开箱即用的两台');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ServerOpsSettings.serversKey), isNull);
      expect(prefs.getString(ServerOpsSettings.selectedKey), isNull);
    });

    test('新增服务器的 id 不撞已有 id', () {
      expect(ServerOpsSettings.nextServerId(const []), 'srv1');
      expect(ServerOpsSettings.nextServerId(const ['srv1']), 'srv2');
      expect(
        ServerOpsSettings.nextServerId(const ['srv1', 'srv3']),
        'srv2',
        reason: '挑最小的空号，不往后堆',
      );
    });

    test('值相等：列表 / 选择 / 口令缓存任一不同就不相等（页签据此判断要不要重建）', () {
      const base = ServerOpsSettings(servers: [_a, _b], selectedServerId: 'a');
      expect(
        base,
        const ServerOpsSettings(servers: [_a, _b], selectedServerId: 'a'),
      );
      expect(
        base,
        isNot(
          const ServerOpsSettings(servers: [_a, _b], selectedServerId: 'b'),
        ),
      );
      expect(base, isNot(const ServerOpsSettings(servers: [_a])));
      expect(
        base,
        isNot(
          const ServerOpsSettings(
            servers: [_a, _b],
            selectedServerId: 'a',
            passwords: {'a': 'pw'},
          ),
        ),
      );
    });

    test('服务器 JSON 往返：字段一个不少，缺 id 的条目直接丢', () {
      final server = _a.copyWith(snapshotId: 'hpa888');
      final round = ServerOpsServer.fromJson(server.toJson());
      expect(round, server);
      expect(ServerOpsServer.fromJson(const {'label': '没有 id'}), isNull);
      expect(ServerOpsServer.fromJson('不是 map'), isNull);
      final noLabel = ServerOpsServer.fromJson(const {'id': 'x'});
      expect(noLabel!.label, 'x', reason: '名字缺了就用 id 顶上，不要空标题');
    });
  });

  group('按服务器分键的口令', () {
    test('只写传进来的那几台，没传的保持原样', () async {
      await const ServerOpsSettings().save(
        servers: [_a, _b],
        passwords: {'a': 'pw-a', 'b': 'pw-b'},
      );
      await (await ServerOpsSettings.load()).save(passwords: {'a': 'pw-a2'});

      expect(store.values['a'], 'pw-a2');
      expect(store.values['b'], 'pw-b', reason: '没传的这台不该被顺手清掉');
    });

    test('空串 = 只清这一台的口令', () async {
      await const ServerOpsSettings().save(
        servers: [_a, _b],
        passwords: {'a': 'pw-a', 'b': 'pw-b'},
      );
      final updated =
          await (await ServerOpsSettings.load()).save(passwords: {'a': ''});

      expect(store.values.containsKey('a'), isFalse);
      expect(store.values['b'], 'pw-b');
      expect(updated.hasPasswordFor('a'), isFalse);
      expect(updated.hasPasswordFor('b'), isTrue);
      expect(store.clears, greaterThan(0));
    });

    test('设备令牌与口令分表：撤销令牌不动口令，改口令不动令牌', () async {
      await const ServerOpsSettings().save(
        servers: [_a, _b],
        passwords: {'a': 'pw-a'},
        apiTokens: {'a': 'tok-a'},
      );
      expect(store.tokens['a'], 'tok-a');
      expect(store.values['a'], 'pw-a');

      // 只清令牌
      final afterClearToken =
          await (await ServerOpsSettings.load()).save(apiTokens: {'a': ''});
      expect(store.tokens.containsKey('a'), isFalse);
      expect(store.values['a'], 'pw-a', reason: '撤销令牌不该动口令');
      expect(afterClearToken.hasApiTokenFor('a'), isFalse);
      expect(afterClearToken.hasPasswordFor('a'), isTrue);

      // 只清口令
      final afterClearPw =
          await (await ServerOpsSettings.load()).save(passwords: {'a': ''});
      expect(store.tokens['a'], isNull, reason: '令牌刚被清掉了，保持清掉');
      expect(store.values.containsKey('a'), isFalse);
      expect(afterClearPw.hasPasswordFor('a'), isFalse);
    });

    test('令牌按服务器分键，且不进 SharedPreferences（令牌是秘密）', () async {
      await const ServerOpsSettings().save(
        servers: [_a, _b],
        apiTokens: {'a': 'tok-a', 'b': 'tok-b'},
      );
      final loaded = await ServerOpsSettings.load();
      expect(loaded.apiTokenFor('a'), 'tok-a');
      expect(loaded.apiTokenFor('b'), 'tok-b');
      expect(loaded.effectiveApiToken, 'tok-a', reason: '当前这台是 a');

      final prefs = await SharedPreferences.getInstance();
      final dump = prefs.getKeys().map((k) => '$k=${prefs.get(k)}').join('\n');
      expect(dump.contains('tok-a'), isFalse, reason: '令牌只能进加密存储');
      expect(dump.contains('tok-b'), isFalse);
      expect(KeystoreOpsSecretStore.apiTokenKeyFor('a'),
          'serverOps.api.token.a');
    });

    test('删掉的服务器，它的令牌键一起清掉', () async {
      await const ServerOpsSettings().save(
        servers: [_a, _b],
        apiTokens: {'a': 'tok-a', 'b': 'tok-b'},
      );
      final updated = await (await ServerOpsSettings.load()).save(servers: [_a]);

      expect(store.tokens.containsKey('b'), isFalse, reason: '不留没人认领的令牌');
      expect(store.tokens['a'], 'tok-a');
      expect(updated.hasApiTokenFor('b'), isFalse);
    });

    test('内置两台各有一套默认只读接口地址；用户自己加的机器没有默认', () {
      expect(ServerOpsSettings.builtInHpa888.effectiveApiUrl,
          'https://box.hpa888.top/opsapi');
      expect(ServerOpsSettings.builtInTencent175.effectiveApiUrl,
          'https://box.hpa888.top/opsapi175');
      expect(
        const ServerOpsServer(id: 'srv1', label: '自建').effectiveApiUrl,
        isEmpty,
        reason: '自建机器没有默认地址：系统页要提示"这台还没接"',
      );
      // 用户填了就以用户的为准。
      expect(
        ServerOpsSettings.builtInTencent175
            .copyWith(apiUrl: 'https://mine.test/opsapi')
            .effectiveApiUrl,
        'https://mine.test/opsapi',
      );
    });

    test('服务器 JSON 往返带上只读接口地址', () {
      final s = _a.copyWith(apiUrl: 'https://x.test/opsapi175');
      final back = ServerOpsServer.fromJson(s.toJson());
      expect(back!.apiUrl, 'https://x.test/opsapi175');
      expect(back, s, reason: '含 apiUrl 的相等性也要对');
    });

    test('删掉的服务器，它的口令键一起清掉', () async {
      await const ServerOpsSettings().save(
        servers: [_a, _b],
        passwords: {'a': 'pw-a', 'b': 'pw-b'},
      );
      final updated = await (await ServerOpsSettings.load()).save(servers: [_a]);

      expect(store.values.containsKey('b'), isFalse, reason: '不留没人认领的口令');
      expect(store.values['a'], 'pw-a');
      expect(updated.servers.map((s) => s.id), ['a']);
      expect(updated.hasPasswordFor('b'), isFalse);
    });
  });

  group('老数据迁移（单服务器 → 多服务器）', () {
    test('老配置 + 加密存储里的老口令：折成一台 hpa888，口令搬到分服务器键', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ServerOpsSettings.baseUrlKey: 'https://old.test/dav',
        ServerOpsSettings.userKey: 'oldops',
        ServerOpsSettings.terminalUrlKey: 'https://old.test/term/',
      });
      store = _FakeStore()..legacy = 'legacy-pw';
      debugSetOpsSecretStore(store);

      final loaded = await ServerOpsSettings.load();

      expect(loaded.effectiveServers, hasLength(1), reason: '老用户只有一台');
      final server = loaded.currentServer;
      expect(server.id, 'hpa888');
      expect(server.label, '阿里云 · 主服务端');
      expect(server.baseUrl, 'https://old.test/dav');
      expect(server.user, 'oldops');
      expect(server.terminalUrl, 'https://old.test/term/');
      expect(server.snapshotId, 'hpa888');
      expect(
        loaded.hasPassword,
        isTrue,
        reason: '老用户升级后不该被要求重输口令',
      );
      expect(
        store.values['hpa888'],
        'legacy-pw',
        reason: '老口令要搬到 serverOps.dav.password.hpa888',
      );
      expect(store.legacy, isNull, reason: '老键必须删掉');
    });

    test('老版本的明文口令（写在 SharedPreferences 里）也要搬家', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ServerOpsSettings.passwordKey: 'plain-pw',
        ServerOpsSettings.userKey: 'boxops',
      });

      final loaded = await ServerOpsSettings.load();

      expect(loaded.effectivePassword, 'plain-pw');
      expect(store.values['hpa888'], 'plain-pw');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(ServerOpsSettings.passwordKey),
        isNull,
        reason: '迁移后明文键必须删掉，否则等于没改',
      );
    });

    test('迁移后四个老键全部清掉，新键写好（下次不再迁移）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ServerOpsSettings.baseUrlKey: 'https://old.test/dav',
        ServerOpsSettings.userKey: 'oldops',
        ServerOpsSettings.terminalUrlKey: 'https://old.test/term/',
        ServerOpsSettings.passwordKey: 'plain-pw',
      });

      await ServerOpsSettings.load();
      var prefs = await SharedPreferences.getInstance();
      for (final key in const [
        ServerOpsSettings.baseUrlKey,
        ServerOpsSettings.userKey,
        ServerOpsSettings.terminalUrlKey,
        ServerOpsSettings.passwordKey,
      ]) {
        expect(prefs.getString(key), isNull, reason: '$key 应该被清掉');
      }
      expect(prefs.getString(ServerOpsSettings.serversKey), contains('hpa888'));
      expect(prefs.getString(ServerOpsSettings.selectedKey), 'hpa888');

      // 再读一次（等价于重启 App）：走新键，结果一样、不再搬迁。
      store.legacy = null;
      final again = await ServerOpsSettings.load();
      expect(again.currentServer.id, 'hpa888');
      expect(again.currentServer.baseUrl, 'https://old.test/dav');
      expect(again.hasPassword, isTrue);

      prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ServerOpsSettings.baseUrlKey), isNull);
    });

    test('只有地址/用户名（没口令）也要迁成一台，且不凭空造口令', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ServerOpsSettings.baseUrlKey: 'https://old.test/dav',
      });

      final loaded = await ServerOpsSettings.load();
      expect(loaded.effectiveServers, hasLength(1));
      expect(loaded.currentServer.baseUrl, 'https://old.test/dav');
      expect(loaded.hasPassword, isFalse);
      expect(store.values, isEmpty);
    });

    test('老键里全是空白 = 等于没配过：不迁移，走开箱即用的两台', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ServerOpsSettings.baseUrlKey: '   ',
        ServerOpsSettings.userKey: '',
      });

      final loaded = await ServerOpsSettings.load();
      expect(loaded.servers, isEmpty, reason: '没有可迁的东西');
      expect(loaded.effectiveServers, hasLength(2));
      expect(loaded.effectiveBaseUrl, ServerOpsSettings.defaultBaseUrl);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ServerOpsSettings.serversKey), isNull);
    });
  });
}
