import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const _defaultHost = '127.0.0.1';
const _defaultPort = 8788;
const _defaultStatePath = '.var/image_platform_state.json';
const _imageKeywords = [
  'gpt-image',
  'dall-e',
  'image',
  'imagen',
  'flux',
  'stable',
  'sd',
  'midjourney',
];

Future<void> main(List<String> args) async {
  final config = ServerConfig.from(args, Platform.environment);
  final store = StateStore(config.statePath, config.defaultQuota);
  await store.load();
  await store.bootstrapAdmin(config);

  final server = await HttpServer.bind(config.host, config.port);
  stdout.writeln('Box image platform quota server running:');
  stdout.writeln('  http://${config.host}:${config.port}');
  stdout.writeln('Admin base URL: ${config.adminBaseUrl}');
  stdout.writeln('Admin API key configured: ${config.adminApiKey.isNotEmpty}');
  stdout.writeln('State path: ${config.statePath}');
  stdout.writeln('Auth endpoints:');
  stdout.writeln('  POST /api/auth/login');
  stdout.writeln('  GET  /api/auth/me');
  stdout.writeln('  POST /api/auth/logout');
  stdout.writeln('Image endpoints:');
  stdout.writeln('  GET  /api/image/quota');
  stdout.writeln('  GET  /api/image/models');
  stdout.writeln('  POST /api/image/generate');
  stdout.writeln('Admin endpoints:');
  stdout.writeln('  GET  /admin/image/users');
  stdout.writeln('  POST /admin/image/users/<userId>/quota');

  await for (final request in server) {
    final app = PlatformQuotaServer(config, store);
    try {
      await app.handle(request);
    } catch (error, stackTrace) {
      stderr.writeln('Unhandled request error: $error');
      stderr.writeln(stackTrace);
      await jsonResponse(request.response, HttpStatus.internalServerError, {
        'error': {'message': '平台服务异常：$error'},
      });
    }
  }
}

class ServerConfig {
  const ServerConfig({
    required this.host,
    required this.port,
    required this.adminBaseUrl,
    required this.adminApiKey,
    required this.legacyAdminToken,
    required this.bootstrapAdminUsername,
    required this.bootstrapAdminPassword,
    required this.allowedModels,
    required this.defaultQuota,
    required this.statePath,
  });

  factory ServerConfig.from(List<String> args, Map<String, String> env) {
    String argValue(String name, String fallback) {
      for (var i = 0; i < args.length; i++) {
        final arg = args[i];
        if (arg == '--$name' && i + 1 < args.length) return args[i + 1];
        if (arg.startsWith('--$name=')) return arg.substring(name.length + 3);
      }
      return fallback;
    }

    final allowed =
        (env['IMAGE_ALLOWED_MODELS'] ?? '')
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    return ServerConfig(
      host: argValue('host', env['HOST'] ?? _defaultHost),
      port: int.tryParse(argValue('port', env['PORT'] ?? '')) ?? _defaultPort,
      adminBaseUrl: (env['IMAGE_ADMIN_BASE_URL'] ?? 'https://api.openai.com/v1')
          .trim()
          .replaceAll(RegExp(r'/+$'), ''),
      adminApiKey: env['IMAGE_ADMIN_API_KEY'] ?? '',
      legacyAdminToken: env['IMAGE_ADMIN_TOKEN'] ?? '',
      bootstrapAdminUsername: env['BOX_ADMIN_USERNAME'] ?? 'admin',
      bootstrapAdminPassword: env['BOX_ADMIN_PASSWORD'] ?? '',
      allowedModels: allowed,
      defaultQuota: int.tryParse(env['IMAGE_DEFAULT_QUOTA'] ?? '') ?? 20,
      statePath: env['IMAGE_STATE_PATH'] ?? _defaultStatePath,
    );
  }

  final String host;
  final int port;
  final String adminBaseUrl;
  final String adminApiKey;
  final String legacyAdminToken;
  final String bootstrapAdminUsername;
  final String bootstrapAdminPassword;
  final List<String> allowedModels;
  final int defaultQuota;
  final String statePath;
}

class PlatformQuotaServer {
  PlatformQuotaServer(this.config, this.store);

  final ServerConfig config;
  final StateStore store;

  Future<void> handle(HttpRequest request) async {
    cors(request.response);
    final path = request.uri.path;
    stdout.writeln(
      '${DateTime.now().toIso8601String()} ${request.method} $path',
    );

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    if (request.method == 'POST' && path == '/api/auth/login') {
      await login(request);
      return;
    }
    if (request.method == 'GET' && path == '/api/auth/me') {
      await me(request);
      return;
    }
    if (request.method == 'POST' && path == '/api/auth/logout') {
      await logout(request);
      return;
    }
    if (request.method == 'GET' && path == '/api/image/quota') {
      final account = await requireUser(request);
      if (account == null) return;
      await quota(request, account);
      return;
    }
    if (request.method == 'GET' && path == '/api/image/models') {
      final account = await requireUser(request);
      if (account == null) return;
      await models(request);
      return;
    }
    if (request.method == 'POST' && path == '/api/image/generate') {
      final account = await requireUser(request);
      if (account == null) return;
      await generate(request, account);
      return;
    }
    if (request.method == 'GET' && path == '/admin/image/users') {
      if (!await requireAdmin(request)) return;
      await jsonResponse(request.response, HttpStatus.ok, store.toAdminJson());
      return;
    }
    final quotaMatch = RegExp(
      r'^/admin/image/users/([^/]+)/quota$',
    ).firstMatch(path);
    if (request.method == 'POST' && quotaMatch != null) {
      if (!await requireAdmin(request)) return;
      await setQuota(request, Uri.decodeComponent(quotaMatch.group(1)!));
      return;
    }
    await jsonResponse(request.response, HttpStatus.notFound, {
      'error': {'message': '接口不存在：$path'},
    });
  }

  Future<void> login(HttpRequest request) async {
    final body = await readJsonObject(request);
    if (body == null) return;
    final username = body['username']?.toString().trim() ?? '';
    final password = body['password']?.toString() ?? '';
    final account = store.accountByUsername(username);
    if (account == null ||
        account.status != 'normal' ||
        !verifyPassword(password, account.passwordHash)) {
      await jsonResponse(request.response, HttpStatus.unauthorized, {
        'error': {'message': '用户名或密码错误'},
      });
      return;
    }
    account.lastLoginAt = DateTime.now();
    final token = newToken('box_session');
    store.sessions[token] = AuthSession(
      token: token,
      userId: account.id,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );
    await store.save();
    await jsonResponse(request.response, HttpStatus.ok, {
      'token': token,
      'user': account.toPublicJson(),
    });
  }

  Future<void> me(HttpRequest request) async {
    final account = await requireUser(request);
    if (account == null) return;
    await jsonResponse(request.response, HttpStatus.ok, account.toPublicJson());
  }

  Future<void> logout(HttpRequest request) async {
    final token = bearerToken(request);
    if (token != null) {
      store.sessions.remove(token);
      await store.save();
    }
    await jsonResponse(request.response, HttpStatus.ok, {'ok': true});
  }

  Future<void> quota(HttpRequest request, Account account) async {
    final user = store.quota(account.id);
    await jsonResponse(request.response, HttpStatus.ok, user.toQuotaJson());
  }

  Future<void> models(HttpRequest request) async {
    final models = await allowedModels();
    await jsonResponse(request.response, HttpStatus.ok, {'models': models});
  }

  Future<void> generate(HttpRequest request, Account account) async {
    if (config.adminApiKey.trim().isEmpty) {
      await jsonResponse(request.response, HttpStatus.serviceUnavailable, {
        'error': {'message': '平台后端未配置 IMAGE_ADMIN_API_KEY，无法代理真实生图。'},
      });
      return;
    }

    final decoded = await readJsonObject(request);
    if (decoded == null) return;
    final prompt = decoded['prompt']?.toString().trim() ?? '';
    if (prompt.isEmpty) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': 'Prompt 不能为空'},
      });
      return;
    }

    final model = (decoded['model']?.toString().trim().isEmpty ?? true)
        ? 'gpt-image-1'
        : decoded['model'].toString().trim();
    final models = await allowedModels();
    if (models.isNotEmpty && !models.contains(model)) {
      await jsonResponse(request.response, HttpStatus.forbidden, {
        'error': {'message': '模型不在平台白名单中：$model'},
      });
      return;
    }

    final cost = calculateCost(decoded);
    final user = store.quota(account.id);
    if (user.status != 'normal') {
      await jsonResponse(request.response, HttpStatus.forbidden, {
        'error': {'message': '用户额度状态不可用：${user.status}'},
      });
      return;
    }
    if (user.remaining < cost) {
      await jsonResponse(request.response, HttpStatus.tooManyRequests, {
        'error': {'message': '额度不足，本次需要 $cost 点，当前剩余 ${user.remaining} 点。'},
      });
      return;
    }

    final upstream = await postUpstream(decoded);
    if (upstream.statusCode < 200 || upstream.statusCode >= 300) {
      store.addUsage(
        UsageRecord.failed(
          account.id,
          model,
          cost,
          upstream.statusCode,
          upstream.preview,
        ),
      );
      await store.save();
      await jsonText(request.response, upstream.statusCode, upstream.text);
      return;
    }

    user.remaining -= cost;
    user.usedToday += cost;
    store.addUsage(
      UsageRecord.success(account.id, model, cost, upstream.statusCode),
    );
    await store.save();
    await jsonText(request.response, HttpStatus.ok, upstream.text);
  }

  Future<void> setQuota(HttpRequest request, String userId) async {
    final decoded = await readJsonObject(request);
    if (decoded == null) return;
    final user = store.quota(userId);
    user.remaining = asInt(decoded['remaining'], user.remaining);
    user.dailyLimit = asInt(decoded['dailyLimit'], user.dailyLimit);
    user.usedToday = asInt(decoded['usedToday'], user.usedToday);
    user.totalLimit = asNullableInt(decoded['totalLimit']) ?? user.totalLimit;
    user.status = decoded['status']?.toString().trim().isEmpty ?? true
        ? user.status
        : decoded['status'].toString().trim();
    user.message = decoded['message']?.toString() ?? user.message;
    await store.save();
    await jsonResponse(request.response, HttpStatus.ok, user.toQuotaJson());
  }

  Future<Account?> requireUser(HttpRequest request) async {
    final token = bearerToken(request);
    if (token == null || token.isEmpty) {
      await jsonResponse(request.response, HttpStatus.unauthorized, {
        'error': {'message': '请先登录 Box 账号。'},
      });
      return null;
    }
    final session = store.sessions[token];
    if (session == null || session.expiresAt.isBefore(DateTime.now())) {
      if (session != null) {
        store.sessions.remove(token);
        await store.save();
      }
      await jsonResponse(request.response, HttpStatus.unauthorized, {
        'error': {'message': '登录已失效，请重新登录。'},
      });
      return null;
    }
    final account = store.accounts[session.userId];
    if (account == null || account.status != 'normal') {
      await jsonResponse(request.response, HttpStatus.forbidden, {
        'error': {'message': '账号不可用。'},
      });
      return null;
    }
    return account;
  }

  Future<bool> requireAdmin(HttpRequest request) async {
    final account = await accountFromRequest(request);
    if (account != null) {
      if (account.role == AccountRole.admin && account.status == 'normal') {
        return true;
      }
      await jsonResponse(request.response, HttpStatus.forbidden, {
        'error': {'message': '需要管理员账号。'},
      });
      return false;
    }

    final legacyToken = request.headers.value('x-admin-token') ?? '';
    if (config.legacyAdminToken.isNotEmpty &&
        legacyToken == config.legacyAdminToken) {
      return true;
    }

    await jsonResponse(request.response, HttpStatus.unauthorized, {
      'error': {'message': '请使用管理员账号登录后操作。'},
    });
    return false;
  }

  Future<Account?> accountFromRequest(HttpRequest request) async {
    final token = bearerToken(request);
    if (token == null || token.isEmpty) return null;
    final session = store.sessions[token];
    if (session == null || session.expiresAt.isBefore(DateTime.now())) {
      return null;
    }
    return store.accounts[session.userId];
  }

  Future<Map<String, dynamic>?> readJsonObject(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    final decoded = raw.trim().isEmpty ? <String, dynamic>{} : jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '请求体必须是 JSON 对象'},
      });
      return null;
    }
    return decoded;
  }

  Future<List<String>> allowedModels() async {
    if (config.allowedModels.isNotEmpty) return config.allowedModels;
    if (config.adminApiKey.trim().isEmpty) return ['gpt-image-1', 'dall-e-3'];
    final upstream = await getUpstreamModels();
    if (upstream.statusCode < 200 || upstream.statusCode >= 300) {
      throw HttpException(
        '上游模型接口失败：${upstream.statusCode} ${upstream.preview}',
      );
    }
    final decoded = jsonDecode(upstream.text);
    final models = parseModels(decoded);
    final recommended = models
        .where(
          (model) =>
              _imageKeywords.any((key) => model.toLowerCase().contains(key)),
        )
        .toList();
    return recommended.isEmpty ? models.take(12).toList() : recommended;
  }

  Future<UpstreamResponse> getUpstreamModels() async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('${config.adminBaseUrl}/models');
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 20));
      req.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${config.adminApiKey}',
      );
      final resp = await req.close().timeout(const Duration(seconds: 30));
      final text = await utf8.decoder.bind(resp).join();
      return UpstreamResponse(resp.statusCode, text);
    } finally {
      client.close(force: true);
    }
  }

  Future<UpstreamResponse> postUpstream(Map<String, dynamic> body) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('${config.adminBaseUrl}/images/generations');
      final req = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 20));
      req.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${config.adminApiKey}',
      );
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
      final resp = await req.close().timeout(const Duration(seconds: 120));
      final text = await utf8.decoder.bind(resp).join();
      return UpstreamResponse(resp.statusCode, text);
    } finally {
      client.close(force: true);
    }
  }
}

class StateStore {
  StateStore(this.path, this.defaultQuota);

  final String path;
  final int defaultQuota;
  final accounts = <String, Account>{};
  final quotas = <String, UserQuota>{};
  final sessions = <String, AuthSession>{};
  final usage = <UsageRecord>[];

  Future<void> load() async {
    final file = File(path);
    if (!await file.exists()) {
      quotas['demo'] = UserQuota.defaultFor(defaultQuota);
      await save();
      return;
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) return;

    final rawAccounts = decoded['accounts'];
    if (rawAccounts is Map) {
      rawAccounts.forEach((key, value) {
        if (value is Map) {
          accounts[key.toString()] = Account.fromJson(
            Map<String, dynamic>.from(value),
          );
        }
      });
    }

    final rawQuotas = decoded['quotas'] ?? decoded['users'];
    if (rawQuotas is Map) {
      rawQuotas.forEach((key, value) {
        if (value is Map) {
          quotas[key.toString()] = UserQuota.fromJson(
            Map<String, dynamic>.from(value),
          );
        }
      });
    }

    final rawSessions = decoded['sessions'];
    if (rawSessions is Map) {
      rawSessions.forEach((key, value) {
        if (value is Map) {
          final session = AuthSession.fromJson(
            Map<String, dynamic>.from(value),
          );
          if (session.expiresAt.isAfter(DateTime.now())) {
            sessions[key.toString()] = session;
          }
        }
      });
    }

    final rawUsage = decoded['usage'];
    if (rawUsage is List) {
      for (final item in rawUsage) {
        if (item is Map) {
          usage.add(UsageRecord.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
  }

  Future<void> bootstrapAdmin(ServerConfig config) async {
    if (accounts.values.any((account) => account.role == AccountRole.admin)) {
      return;
    }
    if (config.bootstrapAdminPassword.trim().isEmpty) {
      stdout.writeln(
        'No admin account exists. Set BOX_ADMIN_PASSWORD once to bootstrap admin user.',
      );
      await save();
      return;
    }
    final adminId = 'u_admin';
    accounts[adminId] = Account(
      id: adminId,
      username: config.bootstrapAdminUsername,
      passwordHash: hashPassword(config.bootstrapAdminPassword),
      role: AccountRole.admin,
      status: 'normal',
      createdAt: DateTime.now(),
      lastLoginAt: null,
    );
    quotas.putIfAbsent(
      adminId,
      () => UserQuota.defaultFor(config.defaultQuota),
    );
    await save();
    stdout.writeln(
      'Bootstrapped admin account: ${config.bootstrapAdminUsername}',
    );
  }

  Account? accountByUsername(String username) {
    final normalized = username.toLowerCase();
    for (final account in accounts.values) {
      if (account.username.toLowerCase() == normalized) return account;
    }
    return null;
  }

  UserQuota quota(String id) =>
      quotas.putIfAbsent(id, () => UserQuota.defaultFor(defaultQuota));

  void addUsage(UsageRecord record) {
    usage.insert(0, record);
    if (usage.length > 200) usage.removeRange(200, usage.length);
  }

  Map<String, dynamic> toJson() => {
    'accounts': accounts.map((key, value) => MapEntry(key, value.toJson())),
    'quotas': quotas.map((key, value) => MapEntry(key, value.toJson())),
    'sessions': sessions.map((key, value) => MapEntry(key, value.toJson())),
    'usage': usage.map((item) => item.toJson()).toList(),
  };

  Map<String, dynamic> toAdminJson() => {
    'accounts': accounts.map(
      (key, value) => MapEntry(key, value.toPublicJson()),
    ),
    'quotas': quotas.map((key, value) => MapEntry(key, value.toJson())),
    'usage': usage.map((item) => item.toJson()).toList(),
  };

  Future<void> save() async {
    final file = File(path);
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(toJson()));
  }
}

enum AccountRole {
  user,
  admin;

  static AccountRole fromWire(String value) =>
      value == 'admin' ? AccountRole.admin : AccountRole.user;

  String get wireName => name;
}

class Account {
  Account({
    required this.id,
    required this.username,
    required this.passwordHash,
    required this.role,
    required this.status,
    required this.createdAt,
    required this.lastLoginAt,
  });

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    id: json['id']?.toString() ?? '',
    username: json['username']?.toString() ?? '',
    passwordHash: json['passwordHash']?.toString() ?? '',
    role: AccountRole.fromWire(json['role']?.toString() ?? 'user'),
    status: json['status']?.toString() ?? 'normal',
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now(),
    lastLoginAt: DateTime.tryParse(json['lastLoginAt']?.toString() ?? ''),
  );

  final String id;
  final String username;
  final String passwordHash;
  final AccountRole role;
  String status;
  final DateTime createdAt;
  DateTime? lastLoginAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'passwordHash': passwordHash,
    'role': role.wireName,
    'status': status,
    'createdAt': createdAt.toIso8601String(),
    'lastLoginAt': lastLoginAt?.toIso8601String(),
  };

  Map<String, dynamic> toPublicJson() => {
    'id': id,
    'username': username,
    'role': role.wireName,
    'status': status,
    'createdAt': createdAt.toIso8601String(),
    'lastLoginAt': lastLoginAt?.toIso8601String(),
  };
}

class AuthSession {
  const AuthSession({
    required this.token,
    required this.userId,
    required this.createdAt,
    required this.expiresAt,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    token: json['token']?.toString() ?? '',
    userId: json['userId']?.toString() ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now(),
    expiresAt:
        DateTime.tryParse(json['expiresAt']?.toString() ?? '') ??
        DateTime.now(),
  );

  final String token;
  final String userId;
  final DateTime createdAt;
  final DateTime expiresAt;

  Map<String, dynamic> toJson() => {
    'token': token,
    'userId': userId,
    'createdAt': createdAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
  };
}

class UserQuota {
  UserQuota({
    required this.remaining,
    required this.dailyLimit,
    required this.usedToday,
    required this.totalLimit,
    required this.status,
    required this.message,
  });

  factory UserQuota.defaultFor(int quota) => UserQuota(
    remaining: quota,
    dailyLimit: quota,
    usedToday: 0,
    totalLimit: quota,
    status: 'normal',
    message: '平台额度可用',
  );

  factory UserQuota.fromJson(Map<String, dynamic> json) => UserQuota(
    remaining: asInt(json['remaining'], 0),
    dailyLimit: asInt(json['dailyLimit'], 0),
    usedToday: asInt(json['usedToday'], 0),
    totalLimit: asNullableInt(json['totalLimit']),
    status: json['status']?.toString() ?? 'normal',
    message: json['message']?.toString() ?? '',
  );

  int remaining;
  int dailyLimit;
  int usedToday;
  int? totalLimit;
  String status;
  String message;

  Map<String, dynamic> toQuotaJson() => {
    'remaining': remaining,
    'dailyLimit': dailyLimit,
    'usedToday': usedToday,
    'totalLimit': totalLimit,
    'status': status,
    'message': message,
  };

  Map<String, dynamic> toJson() => toQuotaJson();
}

class UsageRecord {
  UsageRecord({
    required this.createdAt,
    required this.userId,
    required this.model,
    required this.cost,
    required this.success,
    this.statusCode,
    this.errorPreview = '',
  });

  factory UsageRecord.success(
    String userId,
    String model,
    int cost,
    int statusCode,
  ) => UsageRecord(
    createdAt: DateTime.now(),
    userId: userId,
    model: model,
    cost: cost,
    success: true,
    statusCode: statusCode,
  );

  factory UsageRecord.failed(
    String userId,
    String model,
    int cost,
    int statusCode,
    String preview,
  ) => UsageRecord(
    createdAt: DateTime.now(),
    userId: userId,
    model: model,
    cost: cost,
    success: false,
    statusCode: statusCode,
    errorPreview: preview,
  );

  factory UsageRecord.fromJson(Map<String, dynamic> json) => UsageRecord(
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now(),
    userId: json['userId']?.toString() ?? 'demo',
    model: json['model']?.toString() ?? '',
    cost: asInt(json['cost'], 0),
    success: json['success'] == true,
    statusCode: asNullableInt(json['statusCode']),
    errorPreview: json['errorPreview']?.toString() ?? '',
  );

  final DateTime createdAt;
  final String userId;
  final String model;
  final int cost;
  final bool success;
  final int? statusCode;
  final String errorPreview;

  Map<String, dynamic> toJson() => {
    'createdAt': createdAt.toIso8601String(),
    'userId': userId,
    'model': model,
    'cost': cost,
    'success': success,
    'statusCode': statusCode,
    'errorPreview': errorPreview,
  };
}

class UpstreamResponse {
  const UpstreamResponse(this.statusCode, this.text);

  final int statusCode;
  final String text;

  String get preview {
    final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length <= 320 ? compact : '${compact.substring(0, 320)}...';
  }
}

String? bearerToken(HttpRequest request) {
  final auth = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
  final match = RegExp(
    r'^Bearer\s+(.+)$',
    caseSensitive: false,
  ).firstMatch(auth.trim());
  return match?.group(1)?.trim();
}

String hashPassword(String password) {
  final salt = randomBase64(16);
  final digest = sha256.convert(utf8.encode('$salt:$password')).toString();
  return 'sha256:$salt:$digest';
}

bool verifyPassword(String password, String stored) {
  final parts = stored.split(':');
  if (parts.length != 3 || parts[0] != 'sha256') return false;
  final digest = sha256
      .convert(utf8.encode('${parts[1]}:$password'))
      .toString();
  return digest == parts[2];
}

String newToken(String prefix) => '${prefix}_${randomBase64(32)}';

String randomBase64(int bytes) {
  final random = Random.secure();
  final values = List<int>.generate(bytes, (_) => random.nextInt(256));
  return base64UrlEncode(values).replaceAll('=', '');
}

int calculateCost(Map<String, dynamic> body) {
  final n = asInt(body['n'], 1).clamp(1, 4);
  final quality = body['quality']?.toString().toLowerCase() ?? '';
  var cost = n * (quality == 'high' ? 2 : 1);
  if ((body['image']?.toString().trim().isNotEmpty ?? false) ||
      (body['reference_image']?.toString().trim().isNotEmpty ?? false) ||
      (body['input_image']?.toString().trim().isNotEmpty ?? false)) {
    cost += 1;
  }
  return cost;
}

List<String> parseModels(dynamic decoded) {
  if (decoded is! Map) return const [];
  final data = decoded['models'] ?? decoded['data'];
  if (data is! List) return const [];
  final models =
      data
          .map((item) {
            if (item is String) return item;
            if (item is Map && item['id'] != null) return item['id'].toString();
            return '';
          })
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  return models;
}

int asInt(dynamic value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

int? asNullableInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}

void cors(HttpResponse response) {
  response.headers.set('Access-Control-Allow-Origin', '*');
  response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  response.headers.set(
    'Access-Control-Allow-Headers',
    'Content-Type, Authorization, X-User-Id, X-Admin-Token',
  );
}

Future<void> jsonResponse(
  HttpResponse response,
  int statusCode,
  Map<String, dynamic> body,
) {
  return jsonText(response, statusCode, jsonEncode(body));
}

Future<void> jsonText(
  HttpResponse response,
  int statusCode,
  String text,
) async {
  cors(response);
  response.statusCode = statusCode;
  response.headers.contentType = ContentType.json;
  final bytes = Uint8List.fromList(utf8.encode(text));
  response.contentLength = bytes.length;
  response.add(bytes);
  await response.close();
}
