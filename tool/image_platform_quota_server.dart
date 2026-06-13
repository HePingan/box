import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  final server = await HttpServer.bind(config.host, config.port);
  stdout.writeln('AI image platform quota proxy server running:');
  stdout.writeln('  http://${config.host}:${config.port}');
  stdout.writeln('Admin base URL: ${config.adminBaseUrl}');
  stdout.writeln('Admin API key configured: ${config.adminApiKey.isNotEmpty}');
  stdout.writeln('State path: ${config.statePath}');
  stdout.writeln('Endpoints:');
  stdout.writeln('  GET  /api/image/quota');
  stdout.writeln('  GET  /api/image/models');
  stdout.writeln('  POST /api/image/generate');
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
    required this.adminToken,
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
      adminToken: env['IMAGE_ADMIN_TOKEN'] ?? '',
      allowedModels: allowed,
      defaultQuota: int.tryParse(env['IMAGE_DEFAULT_QUOTA'] ?? '') ?? 20,
      statePath: env['IMAGE_STATE_PATH'] ?? _defaultStatePath,
    );
  }

  final String host;
  final int port;
  final String adminBaseUrl;
  final String adminApiKey;
  final String adminToken;
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
      '${DateTime.now().toIso8601String()} ${request.method} $path user=${userIdOf(request)}',
    );

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }
    if (request.method == 'GET' && path == '/api/image/quota') {
      await quota(request);
      return;
    }
    if (request.method == 'GET' && path == '/api/image/models') {
      await models(request);
      return;
    }
    if (request.method == 'POST' && path == '/api/image/generate') {
      await generate(request);
      return;
    }
    if (request.method == 'GET' && path == '/admin/image/users') {
      if (!await requireAdmin(request)) return;
      await jsonResponse(request.response, HttpStatus.ok, store.toJson());
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

  Future<void> quota(HttpRequest request) async {
    final user = store.user(userIdOf(request));
    await jsonResponse(request.response, HttpStatus.ok, user.toQuotaJson());
  }

  Future<void> models(HttpRequest request) async {
    final models = await allowedModels();
    await jsonResponse(request.response, HttpStatus.ok, {'models': models});
  }

  Future<void> generate(HttpRequest request) async {
    if (config.adminApiKey.trim().isEmpty) {
      await jsonResponse(request.response, HttpStatus.serviceUnavailable, {
        'error': {'message': '平台后端未配置 IMAGE_ADMIN_API_KEY，无法代理真实生图。'},
      });
      return;
    }

    final raw = await utf8.decoder.bind(request).join();
    final decoded = raw.trim().isEmpty ? <String, dynamic>{} : jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '请求体必须是 JSON 对象'},
      });
      return;
    }
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
    final userId = userIdOf(request);
    final user = store.user(userId);
    if (user.status != 'normal') {
      await jsonResponse(request.response, HttpStatus.forbidden, {
        'error': {'message': '用户状态不可用：${user.status}'},
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
          userId,
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
      UsageRecord.success(userId, model, cost, upstream.statusCode),
    );
    await store.save();
    await jsonText(request.response, HttpStatus.ok, upstream.text);
  }

  Future<void> setQuota(HttpRequest request, String userId) async {
    final raw = await utf8.decoder.bind(request).join();
    final decoded = raw.trim().isEmpty ? <String, dynamic>{} : jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '请求体必须是 JSON 对象'},
      });
      return;
    }
    final user = store.user(userId);
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

  Future<bool> requireAdmin(HttpRequest request) async {
    if (config.adminToken.isEmpty) {
      await jsonResponse(request.response, HttpStatus.unauthorized, {
        'error': {'message': '未配置 IMAGE_ADMIN_TOKEN，管理接口已关闭。'},
      });
      return false;
    }
    final token = request.headers.value('x-admin-token') ?? '';
    if (token != config.adminToken) {
      await jsonResponse(request.response, HttpStatus.unauthorized, {
        'error': {'message': 'X-Admin-Token 无效。'},
      });
      return false;
    }
    return true;
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
  final users = <String, UserQuota>{};
  final usage = <UsageRecord>[];

  Future<void> load() async {
    final file = File(path);
    if (!await file.exists()) {
      users['demo'] = UserQuota.defaultFor(defaultQuota);
      await save();
      return;
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) return;
    final rawUsers = decoded['users'];
    if (rawUsers is Map) {
      rawUsers.forEach((key, value) {
        if (value is Map) {
          users[key.toString()] = UserQuota.fromJson(
            Map<String, dynamic>.from(value),
          );
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
    users.putIfAbsent('demo', () => UserQuota.defaultFor(defaultQuota));
  }

  UserQuota user(String id) =>
      users.putIfAbsent(id, () => UserQuota.defaultFor(defaultQuota));

  void addUsage(UsageRecord record) {
    usage.insert(0, record);
    if (usage.length > 200) usage.removeRange(200, usage.length);
  }

  Map<String, dynamic> toJson() => {
    'users': users.map((key, value) => MapEntry(key, value.toJson())),
    'usage': usage.map((item) => item.toJson()).toList(),
  };

  Future<void> save() async {
    final file = File(path);
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(toJson()));
  }
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

String userIdOf(HttpRequest request) {
  final header = request.headers.value('x-user-id')?.trim();
  if (header != null && header.isNotEmpty) return header;
  final query = request.uri.queryParameters['userId']?.trim();
  if (query != null && query.isNotEmpty) return query;
  return 'demo';
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
