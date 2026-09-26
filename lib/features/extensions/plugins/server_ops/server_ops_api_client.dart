// 服务器运维插件：只读运维 API 的客户端（C2 只读档）。
//
// 它替的是"文件通道什么都做不了"的那半：进程、服务状态、日志 tail、端口监听、
// 目录占用、登录记录 —— WebDAV 拿不到这些，因为 rclone 只讲文件。
//
// 与文件页的关键差别是**身份模型**：文件页用的是"等同整盘读写"的通道口令，
// 这里用的是**设备令牌**（服务端只存哈希、可按 label 撤销、每次调用进审计），
// 所以令牌泄了可以单独撤，不必牵动整条通道。
//
// 口径：
//   * 令牌只从加密存储读、只进请求头，**绝不进日志/绝不进错误文案**（面板会被截屏）；
//   * 一切非 2xx 都翻成中文的 [OpsApiException]（含 401/403/429 的分别处置）；
//   * 解析容错：服务端字段缺了就给默认值，不让一个字段把整页打黑。
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 失败的类别。UI 按类别给不同的引导（401 去填令牌、429 别连点、network 看网络）。
enum OpsApiErrorKind {
  unauthorized,
  forbidden,
  rateLimited,
  notFound,
  badRequest,
  server,
  network,
  timeout,
  decode,
}

class OpsApiException implements Exception {
  const OpsApiException(this.kind, this.message, {this.status});

  final OpsApiErrorKind kind;
  final String message;
  final int? status;

  /// 这台机器的令牌不对 → 界面直接引导"去设置里重填这台的令牌"。
  bool get isAuth => kind == OpsApiErrorKind.unauthorized;

  @override
  String toString() => message;
}

/// 只读 API 客户端。一个实例对应**一台机器**。
class OpsApiClient {
  OpsApiClient({
    required String baseUrl,
    required String token,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  })  : _baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
        _token = token.trim(),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final String _baseUrl;
  final String _token;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  bool get hasToken => _token.isNotEmpty;

  void close() {
    if (_ownsClient) _client.close();
  }

  /// 发一次动作请求。这是唯一的出口 —— 别的都走它，好让错误翻译只有一份。
  Future<Map<String, dynamic>> call(
    String action, {
    Map<String, String>? query,
  }) async {
    if (_baseUrl.isEmpty) {
      throw const OpsApiException(
        OpsApiErrorKind.badRequest,
        '这台机器还没填只读接口地址（设置 → 服务器 → 只读接口）',
      );
    }
    if (_token.isEmpty) {
      throw const OpsApiException(
        OpsApiErrorKind.unauthorized,
        '这台机器还没填设备令牌（设置 → 服务器 → 设备令牌）',
      );
    }
    final uri = Uri.parse('$_baseUrl/$action').replace(
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
    http.Response res;
    try {
      res = await _client.get(
        uri,
        headers: {
          'Authorization': 'Bearer $_token',
          'Accept': 'application/json',
        },
      ).timeout(timeout);
    } on TimeoutException {
      throw OpsApiException(
        OpsApiErrorKind.timeout,
        '请求超时（${timeout.inSeconds} 秒）：这台机器可能正忙，稍后再试',
      );
    } catch (e) {
      // 不要把 e 直接拼进去：某些 IO 异常的文本里会带完整 URL（不含令牌，但没必要）
      throw const OpsApiException(
        OpsApiErrorKind.network,
        '连不上这台机器的只读接口（网络或地址不对）',
      );
    }
    return _decode(res, action);
  }

  /// 发一次**写动作**（POST + JSON）。写动作要令牌带 write 作用域，
  /// 没带的话服务端回 403 并说明怎么重签 —— 这条错误原样透传到界面上。
  Future<Map<String, dynamic>> post(
    String action,
    Map<String, Object?> body,
  ) async {
    if (_baseUrl.isEmpty) {
      throw const OpsApiException(
        OpsApiErrorKind.badRequest,
        '这台机器还没填只读接口地址（设置 → 服务器 → 只读接口）',
      );
    }
    if (_token.isEmpty) {
      throw const OpsApiException(
        OpsApiErrorKind.unauthorized,
        '这台机器还没填设备令牌（设置 → 服务器 → 设备令牌）',
      );
    }
    final uri = Uri.parse('$_baseUrl/$action');
    http.Response res;
    try {
      res = await _client
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $_token',
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw OpsApiException(
        OpsApiErrorKind.timeout,
        '请求超时（${timeout.inSeconds} 秒）：这一步可能还在跑，稍后刷新看结果',
      );
    } catch (_) {
      throw const OpsApiException(
        OpsApiErrorKind.network,
        '连不上这台机器的只读接口（网络或地址不对）',
      );
    }
    return _decode(res, action);
  }

  Map<String, dynamic> _decode(http.Response res, String action) {
    Map<String, dynamic> body = const {};
    final text = res.body;
    if (text.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {
        body = const {};
      }
    }
    final serverMessage = (body['error'] as String?)?.trim();
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (body.isEmpty && text.trim().isNotEmpty) {
        throw const OpsApiException(
          OpsApiErrorKind.decode,
          '这台机器的只读接口返回了看不懂的内容（版本不匹配？）',
        );
      }
      return body;
    }
    switch (res.statusCode) {
      case 400:
        throw OpsApiException(OpsApiErrorKind.badRequest,
            serverMessage ?? '请求参数不对', status: 400);
      case 401:
        throw const OpsApiException(
          OpsApiErrorKind.unauthorized,
          '设备令牌无效或已被撤销 —— 口令与令牌不是一回事：'
          '口令给文件/终端用，令牌给这台机器的只读接口用，两台机器的都不同',
          status: 401,
        );
      case 403:
        throw OpsApiException(OpsApiErrorKind.forbidden,
            serverMessage ?? '这台机器的令牌权限不够（这一步要 admin 令牌）', status: 403);
      case 404:
        throw OpsApiException(OpsApiErrorKind.notFound,
            serverMessage ?? '接口地址不对（404）', status: 404);
      case 429:
        throw const OpsApiException(OpsApiErrorKind.rateLimited,
            '请求太频繁，等十几秒再来（服务端限流）', status: 429);
      default:
        throw OpsApiException(OpsApiErrorKind.server,
            serverMessage ?? '服务端出错（${res.statusCode}）', status: res.statusCode);
    }
  }

  // ── 动作封装 ────────────────────────────────────────────────────

  Future<OpsOverview> overview() async =>
      OpsOverview.fromJson(await call('overview'));

  Future<List<OpsProcess>> processes({String sort = 'cpu', int limit = 20}) async {
    final d = await call('processes', query: {'sort': sort, 'limit': '$limit'});
    return _listOf(d['processes'], OpsProcess.fromJson);
  }

  Future<List<OpsServiceUnit>> services({String? filter, int limit = 200}) async {
    final d = await call('services', query: {
      if (filter != null && filter.trim().isNotEmpty) 'q': filter.trim(),
      'limit': '$limit',
    });
    return _listOf(d['units'], OpsServiceUnit.fromJson);
  }

  Future<OpsServiceDetail> service(String unit, {int lines = 20}) async =>
      OpsServiceDetail.fromJson(
          await call('service', query: {'unit': unit, 'lines': '$lines'}));

  Future<OpsLogTail> logs(String path, {int lines = 100}) async =>
      OpsLogTail.fromJson(
          await call('logs', query: {'path': path, 'lines': '$lines'}));

  /// 文件/终端通道的**凭据使用情况**（最近 N 天）。
  ///
  /// 这是"旧通道口令什么时候能退休"的依据：谁还在用它、最近什么时候、从哪个 IP。
  /// 服务端只回入口与方法，**不回 URI、不回任何哈希**；看不到通道日志的机器
  /// （日志在边缘机写）会回 available=false。
  Future<OpsChannelUsage> channel({int days = 7}) async =>
      OpsChannelUsage.fromJson(await call('channel', query: {'days': '$days'}));

  /// 有哪些日志文件可读（名字/大小/最后修改，最近的排前面）。
  ///
  /// `logs` 是按路径读尾部，得先知道路径；以前这一步只能靠人在终端里 ls。
  Future<List<OpsLogFile>> logFiles({int limit = 60, String? root}) async {
    final d = await call('logfiles', query: {
      'limit': '$limit',
      if (root != null && root.isNotEmpty) 'root': root,
    });
    return _listOf(d['list'], OpsLogFile.fromJson);
  }

  Future<List<OpsPort>> ports() async {
    final d = await call('ports');
    return _listOf(d['listeners'], OpsPort.fromJson);
  }

  Future<List<OpsDiskRow>> diskUsage(String path) async {
    final d = await call('diskusage', query: {'path': path});
    return _listOf(d['rows'], OpsDiskRow.fromJson);
  }

  Future<OpsSessions> sessions() async =>
      OpsSessions.fromJson(await call('sessions'));

  Future<List<OpsAuditEntry>> audit({int limit = 50}) async {
    final d = await call('audit', query: {'limit': '$limit'});
    return _listOf(d['items'], OpsAuditEntry.fromJson);
  }

  // ── 能力与写动作（写档）────────────────────────────────────────

  /// 这把令牌能干什么（写按钮显不显示、能不能停某个服务都看它）。
  Future<OpsCapabilities> capabilities() async =>
      OpsCapabilities.fromJson(await call('capabilities'));

  Future<Map<String, dynamic>> serviceOp(String unit, String op) =>
      post('service', {'unit': unit, 'op': op});

  Future<Map<String, dynamic>> mkdir(String path) =>
      post('mkdir', {'path': path});

  Future<Map<String, dynamic>> chmod(String path, String mode,
          {bool recursive = false}) =>
      post('chmod', {'path': path, 'mode': mode, 'recursive': recursive});

  Future<Map<String, dynamic>> chown(String path,
          {String owner = '', String group = '', bool recursive = false}) =>
      post('chown', {
        'path': path,
        'owner': owner,
        'group': group,
        'recursive': recursive,
      });

  /// 解压（zip / tar / tar.gz / tgz / tar.bz2 / tar.xz / gz）。
  /// [dest] 留空 = 解到压缩包所在目录。
  Future<Map<String, dynamic>> extract(String path, {String dest = ''}) =>
      post('extract', {'path': path, 'dest': dest});

  /// 打包（服务器上压，手机不用把目录下下来再传回去）。
  ///
  /// 服务端有两条硬护栏：同名包已存在 → 409（不覆盖）；包落在它自己的输入目录里 → 400。
  Future<Map<String, dynamic>> compress(
    String path, {
    String format = 'tar.gz',
    String dest = '',
    String name = '',
  }) =>
      post('compress', {
        'path': path,
        'format': format,
        'dest': dest,
        'name': name,
      });

  /// 清理（journal / tmp / apt）。`dry: true` 只问「能清多少」，不动手。
  ///
  /// 清多狠由服务端定死（journal 只清到 200M、/tmp 只删 7 天前的普通文件）——
  /// 参数从手机传不进去，免得"在手机上按错一个数"把生产机的日志清光。
  Future<Map<String, dynamic>> cleanup(String what, {bool dry = false}) =>
      post('cleanup', {'what': what, 'dry': dry ? '1' : '0'});
}

/// 这把令牌的能力（服务端 `/capabilities`）。
class OpsCapabilities {
  const OpsCapabilities({
    required this.hostname,
    required this.admin,
    required this.write,
    required this.writeActions,
    required this.selfDestructiveUnits,
    required this.protectedPaths,
  });

  final String hostname;

  /// 能不能读服务端审计。
  final bool admin;

  /// 能不能做写动作（服务启停/建目录/改权限/解压）。
  final bool write;

  final List<String> writeActions;

  /// 停/禁用就会被服务端拒绝的单元（ssh、本服务、隧道、网络…）。
  final List<String> selfDestructiveUnits;

  /// 写动作一律拒绝的路径前缀。
  final List<String> protectedPaths;

  /// 这个服务能不能被停/禁用；不能时返回理由（界面直接显示，不要让用户点了才知道）。
  String? stopBlockedReason(String unit) {
    if (!write) return '这把令牌没有写权限';
    if (selfDestructiveUnits.contains(unit)) {
      return '这个服务是「能让你再连上来」的那一层，服务端会拒绝停它';
    }
    return null;
  }

  static OpsCapabilities fromJson(Map<String, dynamic> json) => OpsCapabilities(
        hostname: _s(json['hostname']),
        admin: json['admin'] == true,
        write: json['write'] == true,
        writeActions: _stringList(json['writeActions']),
        selfDestructiveUnits: _stringList(json['selfDestructiveUnits']),
        protectedPaths: _stringList(json['protectedPaths']),
      );
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return [for (final item in raw) _s(item)];
}

List<T> _listOf<T>(Object? raw, T Function(Map<String, dynamic>) build) {
  if (raw is! List) return <T>[];
  final out = <T>[];
  for (final item in raw) {
    if (item is Map<String, dynamic>) {
      out.add(build(item));
    } else if (item is Map) {
      out.add(build(item.cast<String, dynamic>()));
    }
  }
  return out;
}

String _s(Object? v) => v == null ? '' : '$v';
int _i(Object? v) => v is num ? v.toInt() : int.tryParse(_s(v)) ?? 0;
double _d(Object? v) => v is num ? v.toDouble() : double.tryParse(_s(v)) ?? 0;

// ── 模型（字段缺失一律给默认值：服务端加字段不该把旧包打黑）──

class OpsOverview {
  const OpsOverview({
    required this.hostname,
    required this.osPretty,
    required this.kernel,
    required this.uptimeSeconds,
    required this.load1,
    required this.load5,
    required this.load15,
    required this.cpuModel,
    required this.cores,
    required this.memTotal,
    required this.memUsed,
    required this.swapTotal,
    required this.swapUsed,
    required this.disks,
  });

  final String hostname;
  final String osPretty;
  final String kernel;
  final int uptimeSeconds;
  final double load1;
  final double load5;
  final double load15;
  final String cpuModel;
  final int cores;
  final int memTotal;
  final int memUsed;
  final int swapTotal;
  final int swapUsed;
  final List<OpsDisk> disks;

  double get memUsedPercent => memTotal <= 0 ? 0 : memUsed * 100.0 / memTotal;
  double get swapUsedPercent => swapTotal <= 0 ? 0 : swapUsed * 100.0 / swapTotal;
  double get loadPerCore => cores <= 0 ? load1 : load1 / cores;

  static OpsOverview fromJson(Map<String, dynamic> j) {
    final os = (j['os'] as Map?)?.cast<String, dynamic>() ?? const {};
    final load = (j['load'] as Map?)?.cast<String, dynamic>() ?? const {};
    final cpu = (j['cpu'] as Map?)?.cast<String, dynamic>() ?? const {};
    final mem = (j['memory'] as Map?)?.cast<String, dynamic>() ?? const {};
    return OpsOverview(
      hostname: _s(j['hostname']),
      osPretty: _s(os['pretty']),
      kernel: _s(os['kernel']),
      uptimeSeconds: _i(j['uptimeSeconds']),
      load1: _d(load['load1']),
      load5: _d(load['load5']),
      load15: _d(load['load15']),
      cpuModel: _s(cpu['model']),
      cores: _i(cpu['cores']),
      memTotal: _i(mem['memTotal']),
      memUsed: _i(mem['memUsed']),
      swapTotal: _i(mem['swapTotal']),
      swapUsed: _i(mem['swapUsed']),
      disks: _listOf(j['disks'], OpsDisk.fromJson),
    );
  }
}

class OpsDisk {
  const OpsDisk({
    required this.mount,
    required this.size,
    required this.used,
    required this.avail,
    required this.usePercent,
  });

  final String mount;
  final String size;
  final String used;
  final String avail;
  final String usePercent;

  static OpsDisk fromJson(Map<String, dynamic> j) => OpsDisk(
        mount: _s(j['mount']),
        size: _s(j['size']),
        used: _s(j['used']),
        avail: _s(j['avail']),
        usePercent: _s(j['usePercent']),
      );
}

class OpsProcess {
  const OpsProcess({
    required this.pid,
    required this.user,
    required this.cpuPercent,
    required this.memPercent,
    required this.rssKb,
    required this.elapsed,
    required this.name,
    required this.args,
  });

  final int pid;
  final String user;
  final double cpuPercent;
  final double memPercent;
  final int rssKb;
  final String elapsed;
  final String name;
  final String args;

  static OpsProcess fromJson(Map<String, dynamic> j) => OpsProcess(
        pid: _i(j['pid']),
        user: _s(j['user']),
        cpuPercent: _d(j['cpuPercent']),
        memPercent: _d(j['memPercent']),
        rssKb: _i(j['rssKb']),
        elapsed: _s(j['elapsed']),
        name: _s(j['name']),
        args: _s(j['args']),
      );
}

class OpsServiceUnit {
  const OpsServiceUnit({
    required this.unit,
    required this.active,
    required this.sub,
    required this.enabled,
    required this.description,
  });

  final String unit;
  final String active;
  final String sub;
  final String enabled;
  final String description;

  bool get isFailed => active == 'failed';

  static OpsServiceUnit fromJson(Map<String, dynamic> j) => OpsServiceUnit(
        unit: _s(j['unit']),
        active: _s(j['active']),
        sub: _s(j['sub']),
        enabled: _s(j['enabled']),
        description: _s(j['description']),
      );
}

class OpsServiceDetail {
  const OpsServiceDetail({
    required this.unit,
    required this.activeState,
    required this.subState,
    required this.unitFileState,
    required this.mainPid,
    required this.memoryBytes,
    required this.restarts,
    required this.since,
    required this.journal,
  });

  final String unit;
  final String activeState;
  final String subState;
  final String unitFileState;
  final String mainPid;
  final int? memoryBytes;
  final String restarts;
  final String since;
  final String journal;

  static OpsServiceDetail fromJson(Map<String, dynamic> j) => OpsServiceDetail(
        unit: _s(j['unit']),
        activeState: _s(j['activeState']),
        subState: _s(j['subState']),
        unitFileState: _s(j['unitFileState']),
        mainPid: _s(j['mainPid']),
        memoryBytes: j['memoryBytes'] is num ? (j['memoryBytes'] as num).toInt() : null,
        restarts: _s(j['restarts']),
        since: _s(j['since']),
        journal: _s(j['journal']),
      );
}

/// 通道凭据使用情况（见 [OpsApiClient.channel]）。
class OpsChannelUsage {
  const OpsChannelUsage({
    required this.available,
    required this.reason,
    required this.hint,
    required this.ownerHost,
    required this.windowDays,
    required this.users,
    required this.unused,
  });

  final bool available;
  final String reason;
  final String hint;
  final String ownerHost;
  final int windowDays;
  final List<OpsChannelUser> users;

  /// htpasswd 里有、但窗口内一次都没用过的凭据（发出去忘了收，或刚签还没填进 App）。
  final List<String> unused;

  static OpsChannelUsage fromJson(Map<String, dynamic> j) => OpsChannelUsage(
        available: j['available'] == true,
        reason: _s(j['reason']),
        hint: _s(j['hint']),
        ownerHost: _s(j['ownerHost']),
        windowDays: _i(j['windowDays']),
        users: _listOf(j['users'], OpsChannelUser.fromJson),
        unused: (j['unused'] is List)
            ? [for (final x in j['unused'] as List) '$x']
            : const <String>[],
      );
}

class OpsChannelUser {
  const OpsChannelUser({
    required this.user,
    required this.readOnly,
    required this.stillValid,
    required this.count,
    required this.lastSeen,
    required this.lastIp,
    required this.entries,
    required this.methods,
    required this.denied,
  });

  final String user;
  final bool readOnly;

  /// 这个用户名现在还在不在 htpasswd 里（不在 = 已撤销，出现即说明有人在用旧凭据）。
  final bool stillValid;
  final int count;
  final String lastSeen;
  final String lastIp;
  final Map<String, int> entries;
  final Map<String, int> methods;
  final int denied;

  static OpsChannelUser fromJson(Map<String, dynamic> j) => OpsChannelUser(
        user: _s(j['user']),
        readOnly: j['readOnly'] == true,
        stillValid: j['stillValid'] == true,
        count: _i(j['count']),
        lastSeen: _s(j['lastSeen']),
        lastIp: _s(j['lastIp']),
        entries: _countMap(j['entries']),
        methods: _countMap(j['methods']),
        denied: _i(j['denied']),
      );
}

/// 服务端回的 {"入口名": 次数} 这类小计数表。
Map<String, int> _countMap(Object? raw) {
  if (raw is! Map) return const <String, int>{};
  final out = <String, int>{};
  raw.forEach((k, v) => out['$k'] = _i(v));
  return out;
}

class OpsLogFile {
  const OpsLogFile({
    required this.path,
    required this.name,
    required this.root,
    required this.size,
    required this.mtime,
  });

  final String path;
  final String name;
  final String root;
  final int size;

  /// 服务端给的是本地时间字符串（"2026-09-26 09:41:03"），直接显示，不做时区换算。
  final String mtime;

  static OpsLogFile fromJson(Map<String, dynamic> j) => OpsLogFile(
        path: _s(j['path']),
        name: _s(j['name']),
        root: _s(j['root']),
        size: _i(j['size']),
        mtime: _s(j['mtime']),
      );
}

class OpsLogTail {
  const OpsLogTail({
    required this.path,
    required this.lines,
    required this.truncated,
    required this.content,
  });

  final String path;
  final int lines;
  final bool truncated;
  final String content;

  static OpsLogTail fromJson(Map<String, dynamic> j) => OpsLogTail(
        path: _s(j['path']),
        lines: _i(j['lines']),
        truncated: j['truncated'] == true,
        content: _s(j['content']),
      );
}

class OpsPort {
  const OpsPort({
    required this.proto,
    required this.state,
    required this.local,
    required this.process,
  });

  final String proto;
  final String state;
  final String local;
  final String process;

  static OpsPort fromJson(Map<String, dynamic> j) => OpsPort(
        proto: _s(j['proto']),
        state: _s(j['state']),
        local: _s(j['local']),
        process: _s(j['process']),
      );
}

class OpsDiskRow {
  const OpsDiskRow({required this.size, required this.path});

  final String size;
  final String path;

  static OpsDiskRow fromJson(Map<String, dynamic> j) =>
      OpsDiskRow(size: _s(j['size']), path: _s(j['path']));
}

class OpsSessions {
  const OpsSessions({required this.logins, required this.failedLogins});

  final List<Map<String, dynamic>> logins;
  final List<Map<String, dynamic>> failedLogins;

  static OpsSessions fromJson(Map<String, dynamic> j) => OpsSessions(
        logins: _rawList(j['logins']),
        failedLogins: _rawList(j['failedLogins']),
      );
}

List<Map<String, dynamic>> _rawList(Object? raw) {
  if (raw is! List) return const [];
  final out = <Map<String, dynamic>>[];
  for (final item in raw) {
    if (item is Map<String, dynamic>) {
      out.add(item);
    } else if (item is Map) {
      out.add(item.cast<String, dynamic>());
    }
  }
  return out;
}

class OpsAuditEntry {
  const OpsAuditEntry({
    required this.at,
    required this.action,
    required this.tokenLabel,
    required this.ip,
    required this.status,
    required this.ms,
    required this.note,
  });

  final String at;
  final String action;
  final String tokenLabel;
  final String ip;
  final int status;
  final int ms;
  final String note;

  bool get isOk => status >= 200 && status < 300;

  static OpsAuditEntry fromJson(Map<String, dynamic> j) => OpsAuditEntry(
        at: _s(j['at']),
        action: _s(j['action']),
        tokenLabel: _s(j['token']),
        ip: _s(j['ip']),
        status: _i(j['status']),
        ms: _i(j['ms']),
        note: _s(j['note']),
      );
}

// ── 展示用格式化（放这儿是为了能单测）────────────────────────────

/// 字节 → 人能读的大小（1.5 GB / 512 MB / 12 KB）。
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// 秒 → 「3 天 4 小时」这种口语时长（最细到分钟）。
String formatUptime(int seconds) {
  if (seconds <= 0) return '刚起';
  final days = seconds ~/ 86400;
  final hours = (seconds % 86400) ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final parts = <String>[];
  if (days > 0) parts.add('$days 天');
  if (hours > 0) parts.add('$hours 小时');
  if (parts.isEmpty || (minutes > 0 && days == 0)) parts.add('$minutes 分钟');
  return parts.join(' ');
}
