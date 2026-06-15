import 'dart:async';
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
  stdout.writeln(
    'Registration enabled: ${config.registrationEnabled}, default quota: ${config.registerDefaultQuota}',
  );
  stdout.writeln('State path: ${config.statePath}');
  stdout.writeln('Health endpoint:');
  stdout.writeln('  GET  /');
  stdout.writeln('Auth endpoints:');
  stdout.writeln('  POST /api/auth/register');
  stdout.writeln('  POST /api/auth/login');
  stdout.writeln('  GET  /api/auth/me');
  stdout.writeln('  POST /api/auth/logout');
  stdout.writeln('Image endpoints:');
  stdout.writeln('  GET  /api/image/quota');
  stdout.writeln('  GET  /api/image/models');
  stdout.writeln('  POST /api/image/generate');
  stdout.writeln('  GET  /api/image/usage');
  stdout.writeln('  GET  /api/image/proxy?url=<image-url>');
  stdout.writeln('Admin endpoints:');
  stdout.writeln('  GET  /admin/image/users');
  stdout.writeln('  GET  /admin/image/usage');
  stdout.writeln('  GET  /admin/image/usage/export.csv');
  stdout.writeln('  GET  /admin/image/usage/summary');
  stdout.writeln('  GET  /admin/image/provider');
  stdout.writeln('  POST /admin/image/provider');
  stdout.writeln('  POST /admin/image/provider/test');
  stdout.writeln('  POST /admin/accounts');
  stdout.writeln('  PATCH /admin/accounts/<userId>');
  stdout.writeln('  POST /admin/accounts/<userId>/status');
  stdout.writeln('  DELETE /admin/accounts/<userId>');
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
    required this.registrationEnabled,
    required this.registerDefaultQuota,
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
      registrationEnabled: parseEnvBool(
        env['IMAGE_REGISTRATION_ENABLED'],
        fallback: true,
      ),
      registerDefaultQuota:
          int.tryParse(
            env['IMAGE_REGISTER_DEFAULT_QUOTA'] ?? '',
          )?.clamp(0, 100000).toInt() ??
          5,
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
  final bool registrationEnabled;
  final int registerDefaultQuota;
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

    if (request.method == 'GET' && path == '/') {
      await health(request);
      return;
    }

    if (request.method == 'POST' && path == '/api/auth/register') {
      await register(request);
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
    if (request.method == 'GET' && path == '/api/image/usage') {
      final account = await requireUser(request);
      if (account == null) return;
      await selfUsageLogs(request, account);
      return;
    }
    if (request.method == 'GET' && path == '/api/image/proxy') {
      final account = await requireUser(request);
      if (account == null) return;
      await proxyImage(request, account);
      return;
    }
    if (request.method == 'GET' && path == '/admin/image/users') {
      if (!await requireAdmin(request)) return;
      await jsonResponse(request.response, HttpStatus.ok, store.toAdminJson());
      return;
    }
    if (request.method == 'GET' && path == '/admin/image/usage/summary') {
      if (!await requireAdmin(request)) return;
      await usageSummary(request);
      return;
    }
    if (request.method == 'GET' && path == '/admin/image/usage/export.csv') {
      if (!await requireAdmin(request)) return;
      await usageCsvExport(request);
      return;
    }
    if (request.method == 'GET' && path == '/admin/image/usage') {
      if (!await requireAdmin(request)) return;
      await usageLogs(request);
      return;
    }
    if (request.method == 'GET' && path == '/admin/image/provider') {
      if (!await requireAdmin(request)) return;
      await getProvider(request);
      return;
    }
    if (request.method == 'POST' && path == '/admin/image/provider') {
      if (!await requireAdmin(request)) return;
      await updateProvider(request);
      return;
    }
    if (request.method == 'POST' && path == '/admin/image/provider/test') {
      if (!await requireAdmin(request)) return;
      await testProviderEndpoint(request);
      return;
    }
    if (request.method == 'POST' && path == '/admin/accounts') {
      if (!await requireAdmin(request)) return;
      await createAccount(request);
      return;
    }
    final accountStatusMatch = RegExp(
      r'^/admin/accounts/([^/]+)/status$',
    ).firstMatch(path);
    if (request.method == 'POST' && accountStatusMatch != null) {
      if (!await requireAdmin(request)) return;
      await updateAccountStatus(
        request,
        Uri.decodeComponent(accountStatusMatch.group(1)!),
      );
      return;
    }
    final accountMatch = RegExp(r'^/admin/accounts/([^/]+)$').firstMatch(path);
    if (request.method == 'PATCH' && accountMatch != null) {
      if (!await requireAdmin(request)) return;
      await updateAccount(request, Uri.decodeComponent(accountMatch.group(1)!));
      return;
    }
    if (request.method == 'DELETE' && accountMatch != null) {
      if (!await requireAdmin(request)) return;
      await deleteAccount(request, Uri.decodeComponent(accountMatch.group(1)!));
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

  Future<void> health(HttpRequest request) async {
    await jsonResponse(request.response, HttpStatus.ok, {
      'ok': true,
      'service': 'box-image-platform',
      'message': 'Box Image Platform API running',
    });
  }

  Future<void> proxyImage(HttpRequest request, Account account) async {
    final rawUrl = request.uri.queryParameters['url']?.trim() ?? '';
    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '图片代理 URL 必须是 http/https 地址。'},
      });
      return;
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 12);
    try {
      final upstreamRequest = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 12));
      upstreamRequest.headers.set(
        HttpHeaders.acceptHeader,
        'image/*,*/*;q=0.8',
      );
      final upstreamResponse = await upstreamRequest.close().timeout(
        const Duration(seconds: 30),
      );
      final contentType = upstreamResponse.headers.contentType;
      final contentLength = upstreamResponse.contentLength;
      const maxBytes = 8 * 1024 * 1024;

      if (upstreamResponse.statusCode < 200 ||
          upstreamResponse.statusCode >= 300) {
        await jsonResponse(request.response, HttpStatus.badGateway, {
          'error': {'message': '上游图片读取失败：HTTP ${upstreamResponse.statusCode}'},
        });
        return;
      }
      if (contentLength > maxBytes) {
        await jsonResponse(request.response, HttpStatus.badRequest, {
          'error': {'message': '图片过大，暂不支持代理超过 8MB 的图片。'},
        });
        return;
      }
      if (contentType == null || contentType.primaryType != 'image') {
        await jsonResponse(request.response, HttpStatus.badRequest, {
          'error': {'message': '目标地址不是图片内容。'},
        });
        return;
      }

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = contentType;
      request.response.headers.set(
        HttpHeaders.cacheControlHeader,
        'public, max-age=3600',
      );
      request.response.headers.set('x-box-image-proxy', '1');
      if (contentLength >= 0) request.response.contentLength = contentLength;

      var received = 0;
      await for (final chunk in upstreamResponse) {
        received += chunk.length;
        if (received > maxBytes) break;
        request.response.add(chunk);
      }
      await request.response.close();
    } catch (error) {
      await jsonResponse(request.response, HttpStatus.badGateway, {
        'error': {'message': '图片代理失败：${compactPreview(error.toString())}'},
      });
    } finally {
      client.close(force: true);
    }
  }

  Future<void> register(HttpRequest request) async {
    if (!config.registrationEnabled) {
      await jsonResponse(request.response, HttpStatus.forbidden, {
        'error': {'message': '当前服务器已关闭开放注册，请联系管理员创建账号。'},
      });
      return;
    }
    final body = await readJsonObject(request);
    if (body == null) return;
    final username = body['username']?.toString().trim() ?? '';
    final password = body['password']?.toString() ?? '';
    final usernameError = validateRegisterUsername(username);
    if (usernameError != null) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': usernameError},
      });
      return;
    }
    if (password.length < 6) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '密码至少需要 6 位。'},
      });
      return;
    }
    if (store.accountByUsername(username) != null) {
      await jsonResponse(request.response, HttpStatus.conflict, {
        'error': {'message': '用户名已存在，请换一个。'},
      });
      return;
    }

    final now = DateTime.now();
    final account = Account(
      id: store.nextAccountId(),
      username: username,
      passwordHash: hashPassword(password),
      role: AccountRole.user,
      status: 'normal',
      createdAt: now,
      lastLoginAt: now,
    );
    store.accounts[account.id] = account;
    store.quotas[account.id] = UserQuota.defaultFor(
      config.registerDefaultQuota,
    );
    final token = createSession(account);
    await store.save();
    await jsonResponse(request.response, HttpStatus.created, {
      'token': token,
      'user': account.toPublicJson(),
      'quota': store.quota(account.id).toQuotaJson(),
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
    final token = createSession(account);
    await store.save();
    await jsonResponse(request.response, HttpStatus.ok, {
      'token': token,
      'user': account.toPublicJson(),
    });
  }

  String createSession(Account account) {
    final token = newToken('box_session');
    store.sessions[token] = AuthSession(
      token: token,
      userId: account.id,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );
    return token;
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
    final provider = effectiveProvider();
    if (provider.apiKey.trim().isEmpty) {
      await jsonResponse(request.response, HttpStatus.serviceUnavailable, {
        'error': {'message': '平台后端未配置上游 API Key，无法代理真实生图。'},
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

    final UpstreamResponse upstream;
    try {
      upstream = await postUpstream(decoded);
    } catch (error) {
      store.addUsage(
        UsageRecord.failed(account.id, model, cost, 503, '$error'),
      );
      await store.save();
      await jsonResponse(request.response, HttpStatus.serviceUnavailable, {
        'error': {'message': '上游 Provider 请求失败：${compactPreview('$error')}'},
      });
      return;
    }
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

  Future<void> testProviderEndpoint(HttpRequest request) async {
    await jsonResponse(request.response, HttpStatus.ok, await testProvider());
  }

  Future<Map<String, dynamic>> testProvider() async {
    final provider = effectiveProvider();
    if (provider.apiKey.trim().isEmpty) {
      return {
        'ok': false,
        'statusCode': null,
        'baseUrl': provider.baseUrl,
        'hasApiKey': false,
        'modelCount': 0,
        'modelsPreview': <String>[],
        'message': '未配置上游 API Key',
      };
    }
    final baseUri = Uri.tryParse(provider.baseUrl);
    if (baseUri == null ||
        (baseUri.scheme != 'http' && baseUri.scheme != 'https')) {
      return {
        'ok': false,
        'statusCode': null,
        'baseUrl': provider.baseUrl,
        'hasApiKey': true,
        'modelCount': 0,
        'modelsPreview': <String>[],
        'message': 'Provider Base URL 配置无效',
      };
    }
    try {
      final upstream = await getUpstreamModels(provider);
      if (upstream.statusCode < 200 || upstream.statusCode >= 300) {
        return {
          'ok': false,
          'statusCode': upstream.statusCode,
          'baseUrl': provider.baseUrl,
          'hasApiKey': true,
          'modelCount': 0,
          'modelsPreview': <String>[],
          'message': '上游模型接口失败：${upstream.statusCode} ${upstream.preview}',
        };
      }
      final decoded = jsonDecode(upstream.text);
      final models = parseModels(decoded);
      return {
        'ok': true,
        'statusCode': upstream.statusCode,
        'baseUrl': provider.baseUrl,
        'hasApiKey': true,
        'modelCount': models.length,
        'modelsPreview': models.take(12).toList(),
        'message': 'Provider 连接正常',
      };
    } on TimeoutException catch (error) {
      return providerTestError(provider, 'Provider 连接超时：$error');
    } on SocketException catch (error) {
      return providerTestError(provider, 'Provider 网络连接失败：$error');
    } on FormatException catch (error) {
      return providerTestError(provider, 'Provider 返回内容不是有效 JSON：$error');
    } catch (error) {
      return providerTestError(provider, 'Provider 连接失败：$error');
    }
  }

  Future<void> usageSummary(HttpRequest request) async {
    await jsonResponse(request.response, HttpStatus.ok, usageSummaryJson());
  }

  Map<String, dynamic> usageSummaryJson() {
    final today = dateKey(DateTime.now());
    final dayKeys = List.generate(
      7,
      (index) => dateKey(DateTime.now().subtract(Duration(days: 6 - index))),
    );
    final days = {for (final key in dayKeys) key: UsageDayAccumulator(key)};
    final topUsers = <String, UsageUserAccumulator>{};

    for (final item in store.usage) {
      final key = dateKey(item.createdAt);
      final day = days[key];
      if (day != null) day.add(item);
      if (key == today) {
        final account = store.accounts[item.userId];
        topUsers
            .putIfAbsent(
              item.userId,
              () => UsageUserAccumulator(
                userId: item.userId,
                username: account?.username ?? item.userId,
              ),
            )
            .add(item);
      }
    }

    final sortedTopUsers = topUsers.values.toList()
      ..sort((a, b) {
        final cost = b.cost.compareTo(a.cost);
        if (cost != 0) return cost;
        return b.requests.compareTo(a.requests);
      });

    return {
      'today': (days[today] ?? UsageDayAccumulator(today)).toJson(),
      'last7Days': dayKeys.map((key) => days[key]!.toJson()).toList(),
      'topUsersToday': sortedTopUsers
          .take(5)
          .map((item) => item.toJson())
          .toList(),
    };
  }

  Future<void> usageLogs(HttpRequest request) async {
    final query = request.uri.queryParameters;
    await jsonResponse(request.response, HttpStatus.ok, {
      'usage': usageJson(
        userId: query['userId']?.trim().isEmpty ?? true
            ? null
            : query['userId']!.trim(),
        success: parseBool(query['success']),
        limit: asInt(query['limit'], 200),
      ),
    });
  }

  Future<void> selfUsageLogs(HttpRequest request, Account account) async {
    final query = request.uri.queryParameters;
    await jsonResponse(request.response, HttpStatus.ok, {
      'usage': usageJson(
        userId: account.id,
        success: parseBool(query['success']),
        limit: asInt(query['limit'], 20),
      ),
    });
  }

  List<Map<String, dynamic>> usageJson({
    String? userId,
    bool? success,
    int limit = 200,
    int maxLimit = 200,
  }) {
    final effectiveLimit = limit.clamp(1, maxLimit).toInt();
    final result = <Map<String, dynamic>>[];
    for (final item in store.usage.reversed) {
      if (userId != null && item.userId != userId) continue;
      if (success != null && item.success != success) continue;
      final account = store.accounts[item.userId];
      final json = item.toJson();
      json['username'] = account?.username ?? item.userId;
      json['errorPreview'] = compactPreview(item.errorPreview);
      result.add(json);
      if (result.length >= effectiveLimit) break;
    }
    return result;
  }

  Future<void> usageCsvExport(HttpRequest request) async {
    final query = request.uri.queryParameters;
    final csv = usageCsv(
      userId: query['userId']?.trim().isEmpty ?? true
          ? null
          : query['userId']!.trim(),
      success: parseBool(query['success']),
      limit: asInt(query['limit'], 200),
    );
    await csvResponse(
      request.response,
      'box-image-usage-${dateKey(DateTime.now())}.csv',
      csv,
    );
  }

  String usageCsv({String? userId, bool? success, int limit = 200}) {
    final rows = usageJson(
      userId: userId,
      success: success,
      limit: limit,
      maxLimit: 1000,
    );
    final buffer = StringBuffer(
      'createdAt,userId,username,model,cost,success,statusCode,errorPreview\n',
    );
    for (final row in rows) {
      buffer.writeln(
        [
          row['createdAt'],
          row['userId'],
          row['username'],
          row['model'],
          row['cost'],
          row['success'],
          row['statusCode'],
          row['errorPreview'],
        ].map(csvCell).join(','),
      );
    }
    return buffer.toString();
  }

  Future<void> getProvider(HttpRequest request) async {
    await jsonResponse(
      request.response,
      HttpStatus.ok,
      store.providerPublicJson(config),
    );
  }

  Future<void> updateProvider(HttpRequest request) async {
    final decoded = await readJsonObject(request);
    if (decoded == null) return;
    final baseUrl = decoded['baseUrl']?.toString().trim() ?? '';
    final parsedBaseUrl = Uri.tryParse(baseUrl);
    if (baseUrl.isEmpty ||
        parsedBaseUrl == null ||
        (parsedBaseUrl.scheme != 'http' && parsedBaseUrl.scheme != 'https')) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': 'Base URL 必须是 http/https 地址'},
      });
      return;
    }
    final clearApiKey = decoded['clearApiKey'] == true;
    final apiKey = decoded['apiKey']?.toString() ?? '';
    final previous = store.providerConfig;
    final nextApiKeyCipher = clearApiKey
        ? ''
        : apiKey.trim().isEmpty
        ? previous?.apiKeyCipher ?? encodeProviderApiKey(config.adminApiKey)
        : encodeProviderApiKey(apiKey.trim());
    store.providerConfig = ProviderConfig(
      baseUrl: baseUrl.replaceAll(RegExp(r'/+$'), ''),
      apiKeyCipher: nextApiKeyCipher,
      allowedModels: parseAllowedModels(decoded['allowedModels']),
      updatedAt: DateTime.now(),
    );
    await store.save();
    await jsonResponse(
      request.response,
      HttpStatus.ok,
      store.providerPublicJson(config),
    );
  }

  Future<void> createAccount(HttpRequest request) async {
    final decoded = await readJsonObject(request);
    if (decoded == null) return;
    final username = decoded['username']?.toString().trim() ?? '';
    final password = decoded['password']?.toString() ?? '';
    final roleText = decoded['role']?.toString().trim() ?? 'user';
    if (username.isEmpty) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '用户名不能为空'},
      });
      return;
    }
    if (password.length < 6) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '密码长度至少 6 位'},
      });
      return;
    }
    final role = parseRole(roleText);
    if (role == null) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '角色只支持 user 或 admin'},
      });
      return;
    }
    if (store.accountByUsername(username) != null) {
      await jsonResponse(request.response, HttpStatus.conflict, {
        'error': {'message': '用户名已存在'},
      });
      return;
    }
    final id = store.nextAccountId();
    final account = Account(
      id: id,
      username: username,
      passwordHash: hashPassword(password),
      role: role,
      status: 'normal',
      createdAt: DateTime.now(),
      lastLoginAt: null,
    );
    store.accounts[id] = account;
    final dailyLimit = asInt(decoded['dailyLimit'], config.defaultQuota);
    final remaining = asInt(decoded['remaining'], dailyLimit);
    store.quotas[id] = UserQuota(
      remaining: remaining < 0 ? 0 : remaining,
      dailyLimit: dailyLimit < 0 ? 0 : dailyLimit,
      usedToday: 0,
      totalLimit: dailyLimit < 0 ? 0 : dailyLimit,
      status: 'normal',
      message: '平台额度可用',
    );
    await store.save();
    await jsonResponse(request.response, HttpStatus.ok, {
      'user': account.toPublicJson(),
      'quota': store.quota(id).toQuotaJson(),
    });
  }

  Future<void> updateAccount(HttpRequest request, String userId) async {
    final account = store.accounts[userId];
    if (account == null) {
      await jsonResponse(request.response, HttpStatus.notFound, {
        'error': {'message': '用户不存在'},
      });
      return;
    }
    final decoded = await readJsonObject(request);
    if (decoded == null) return;

    var nextRole = account.role;
    var nextStatus = account.status;
    if (decoded.containsKey('role')) {
      final role = parseRole(decoded['role']?.toString().trim() ?? '');
      if (role == null) {
        await jsonResponse(request.response, HttpStatus.badRequest, {
          'error': {'message': '角色只支持 user 或 admin'},
        });
        return;
      }
      nextRole = role;
    }
    if (decoded.containsKey('status')) {
      final status = decoded['status']?.toString().trim() ?? '';
      if (status != 'normal' && status != 'disabled') {
        await jsonResponse(request.response, HttpStatus.badRequest, {
          'error': {'message': '状态只支持 normal 或 disabled'},
        });
        return;
      }
      nextStatus = status;
    }
    if ((nextRole != AccountRole.admin || nextStatus != 'normal') &&
        store.isLastActiveAdmin(userId)) {
      await jsonResponse(request.response, HttpStatus.conflict, {
        'error': {'message': '不能降级或禁用最后一个管理员。'},
      });
      return;
    }
    if (decoded.containsKey('password')) {
      final password = decoded['password']?.toString() ?? '';
      if (password.isNotEmpty && password.length < 6) {
        await jsonResponse(request.response, HttpStatus.badRequest, {
          'error': {'message': '密码长度至少 6 位'},
        });
        return;
      }
      if (password.isNotEmpty) account.passwordHash = hashPassword(password);
    }

    account.role = nextRole;
    account.status = nextStatus;
    final quota = store.quota(userId);
    quota.status = nextStatus;
    quota.message = nextStatus == 'normal' ? '平台额度可用' : '账号已禁用';
    if (nextStatus != 'normal') {
      store.sessions.removeWhere((_, s) => s.userId == userId);
    }
    await store.save();
    await jsonResponse(request.response, HttpStatus.ok, account.toPublicJson());
  }

  Future<void> updateAccountStatus(HttpRequest request, String userId) async {
    final decoded = await readJsonObject(request);
    if (decoded == null) return;
    final status = decoded['status']?.toString().trim() ?? '';
    if (status != 'normal' && status != 'disabled') {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '状态只支持 normal 或 disabled'},
      });
      return;
    }
    await setAccountStatus(request, userId, status);
  }

  Future<void> setAccountStatus(
    HttpRequest request,
    String userId,
    String status,
  ) async {
    final account = store.accounts[userId];
    if (account == null) {
      await jsonResponse(request.response, HttpStatus.notFound, {
        'error': {'message': '用户不存在'},
      });
      return;
    }
    if (status != 'normal' && status != 'disabled') {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '状态只支持 normal 或 disabled'},
      });
      return;
    }
    if (status != 'normal' && store.isLastActiveAdmin(userId)) {
      await jsonResponse(request.response, HttpStatus.conflict, {
        'error': {'message': '不能禁用最后一个管理员。'},
      });
      return;
    }
    account.status = status;
    final quota = store.quota(userId);
    quota.status = status;
    quota.message = status == 'normal' ? '平台额度可用' : '账号已禁用';
    if (status != 'normal') {
      store.sessions.removeWhere((_, s) => s.userId == userId);
    }
    await store.save();
    await jsonResponse(request.response, HttpStatus.ok, {
      'user': account.toPublicJson(),
      'quota': quota.toQuotaJson(),
    });
  }

  Future<void> deleteAccount(HttpRequest request, String userId) async {
    final account = store.accounts[userId];
    if (account == null) {
      await jsonResponse(request.response, HttpStatus.notFound, {
        'error': {'message': '用户不存在'},
      });
      return;
    }
    if (account.role == AccountRole.admin) {
      await jsonResponse(request.response, HttpStatus.conflict, {
        'error': {'message': '管理员账号不能删除。请先降级或保留管理员账号。'},
      });
      return;
    }
    store.accounts.remove(userId);
    store.quotas.remove(userId);
    store.sessions.removeWhere((_, s) => s.userId == userId);
    await store.save();
    await jsonResponse(request.response, HttpStatus.ok, {
      'ok': true,
      'deletedUserId': userId,
    });
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
      store.sessions.remove(token);
      await store.save();
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
    final account = store.accounts[session.userId];
    if (account == null || account.status != 'normal') return null;
    return account;
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

  EffectiveProvider effectiveProvider() => store.effectiveProvider(config);

  Future<List<String>> allowedModels() async {
    final provider = effectiveProvider();
    if (provider.allowedModels.isNotEmpty) return provider.allowedModels;
    if (provider.apiKey.trim().isEmpty) return ['gpt-image-1', 'dall-e-3'];
    final upstream = await getUpstreamModels(provider);
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

  Future<UpstreamResponse> getUpstreamModels(EffectiveProvider provider) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('${provider.baseUrl}/models');
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 20));
      req.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${provider.apiKey}',
      );
      final resp = await req.close().timeout(const Duration(seconds: 30));
      final text = await utf8.decoder.bind(resp).join();
      return UpstreamResponse(resp.statusCode, text);
    } finally {
      client.close(force: true);
    }
  }

  Future<UpstreamResponse> postUpstream(Map<String, dynamic> body) async {
    final provider = effectiveProvider();
    final client = HttpClient();
    try {
      final uri = Uri.parse('${provider.baseUrl}/images/generations');
      final req = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 20));
      req.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${provider.apiKey}',
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
  ProviderConfig? providerConfig;

  Future<void> load() async {
    final file = File(path);
    if (!await file.exists()) {
      quotas['demo'] = UserQuota.defaultFor(defaultQuota);
      await save();
      return;
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) return;

    final rawProvider = decoded['providerConfig'];
    if (rawProvider is Map) {
      providerConfig = ProviderConfig.fromJson(
        Map<String, dynamic>.from(rawProvider),
      );
    }

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

  String nextAccountId() {
    String id;
    do {
      id = 'u_${randomBase64(9)}';
    } while (accounts.containsKey(id));
    return id;
  }

  bool isLastActiveAdmin(String id) {
    final activeAdmins = accounts.values.where(
      (account) =>
          account.role == AccountRole.admin && account.status == 'normal',
    );
    return activeAdmins.length == 1 && activeAdmins.first.id == id;
  }

  void addUsage(UsageRecord record) {
    usage.insert(0, record);
    if (usage.length > 200) usage.removeRange(200, usage.length);
  }

  Map<String, dynamic> toJson() => {
    if (providerConfig != null) 'providerConfig': providerConfig!.toJson(),
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

  EffectiveProvider effectiveProvider(ServerConfig config) {
    final provider = providerConfig;
    final providerApiKey = provider == null
        ? ''
        : decodeProviderApiKey(provider.apiKeyCipher);
    return EffectiveProvider(
      baseUrl: (provider?.baseUrl.trim().isNotEmpty ?? false)
          ? provider!.baseUrl
          : config.adminBaseUrl,
      apiKey: provider == null ? config.adminApiKey : providerApiKey,
      allowedModels: (provider?.allowedModels.isNotEmpty ?? false)
          ? provider!.allowedModels
          : config.allowedModels,
      updatedAt: provider?.updatedAt,
    );
  }

  Map<String, dynamic> providerPublicJson(ServerConfig config) {
    final provider = effectiveProvider(config);
    return {
      'baseUrl': provider.baseUrl,
      'apiKeyMask': maskApiKey(provider.apiKey),
      'hasApiKey': provider.apiKey.trim().isNotEmpty,
      'allowedModels': provider.allowedModels,
      'updatedAt': provider.updatedAt?.toIso8601String(),
    };
  }

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
  String passwordHash;
  AccountRole role;
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

class ProviderConfig {
  const ProviderConfig({
    required this.baseUrl,
    required this.apiKeyCipher,
    required this.allowedModels,
    required this.updatedAt,
  });

  factory ProviderConfig.fromJson(Map<String, dynamic> json) => ProviderConfig(
    baseUrl: (json['baseUrl']?.toString() ?? '').replaceAll(RegExp(r'/+$'), ''),
    apiKeyCipher: json['apiKeyCipher']?.toString() ?? '',
    allowedModels: parseAllowedModels(json['allowedModels']),
    updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
  );

  final String baseUrl;
  final String apiKeyCipher;
  final List<String> allowedModels;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'apiKeyCipher': apiKeyCipher,
    'allowedModels': allowedModels,
    'updatedAt': updatedAt?.toIso8601String(),
  };
}

class EffectiveProvider {
  const EffectiveProvider({
    required this.baseUrl,
    required this.apiKey,
    required this.allowedModels,
    required this.updatedAt,
  });

  final String baseUrl;
  final String apiKey;
  final List<String> allowedModels;
  final DateTime? updatedAt;
}

class UsageDayAccumulator {
  UsageDayAccumulator(this.date);

  final String date;
  var requests = 0;
  var success = 0;
  var failed = 0;
  var cost = 0;
  final activeUserIds = <String>{};

  void add(UsageRecord record) {
    requests += 1;
    if (record.success) {
      success += 1;
    } else {
      failed += 1;
    }
    cost += record.cost;
    activeUserIds.add(record.userId);
  }

  Map<String, dynamic> toJson() => {
    'date': date,
    'requests': requests,
    'success': success,
    'failed': failed,
    'cost': cost,
    'activeUsers': activeUserIds.length,
  };
}

class UsageUserAccumulator {
  UsageUserAccumulator({required this.userId, required this.username});

  final String userId;
  final String username;
  var requests = 0;
  var success = 0;
  var failed = 0;
  var cost = 0;

  void add(UsageRecord record) {
    requests += 1;
    if (record.success) {
      success += 1;
    } else {
      failed += 1;
    }
    cost += record.cost;
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'username': username,
    'requests': requests,
    'success': success,
    'failed': failed,
    'cost': cost,
  };
}

class UpstreamResponse {
  const UpstreamResponse(this.statusCode, this.text);

  final int statusCode;
  final String text;

  String get preview {
    return compactPreview(text);
  }
}

String? validateRegisterUsername(String username) {
  if (username.length < 3 || username.length > 20) {
    return '用户名需要 3-20 位。';
  }
  if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(username)) {
    return '用户名只支持字母、数字和下划线。';
  }
  const reserved = {
    'admin',
    'administrator',
    'root',
    'system',
    'support',
    'box',
    'null',
  };
  if (reserved.contains(username.toLowerCase())) {
    return '该用户名为系统保留名称，请换一个。';
  }
  return null;
}

AccountRole? parseRole(String value) {
  if (value == 'user') return AccountRole.user;
  if (value == 'admin') return AccountRole.admin;
  return null;
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

Map<String, dynamic> providerTestError(
  EffectiveProvider provider,
  String message,
) => {
  'ok': false,
  'statusCode': null,
  'baseUrl': provider.baseUrl,
  'hasApiKey': provider.apiKey.trim().isNotEmpty,
  'modelCount': 0,
  'modelsPreview': <String>[],
  'message': compactPreview(message),
};

Future<void> csvResponse(
  HttpResponse response,
  String filename,
  String csv,
) async {
  response.statusCode = HttpStatus.ok;
  response.headers.contentType = ContentType('text', 'csv', charset: 'utf-8');
  response.headers.set(
    'content-disposition',
    'attachment; filename="$filename"',
  );
  response.write(csv);
  await response.close();
}

String csvCell(Object? value) {
  final text = value?.toString() ?? '';
  final needsQuotes =
      text.contains(',') ||
      text.contains('"') ||
      text.contains('\n') ||
      text.contains('\r');
  final escaped = text.replaceAll('"', '""');
  return needsQuotes ? '"$escaped"' : escaped;
}

String dateKey(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

String compactPreview(String text, {int max = 320}) {
  final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return compact.length <= max ? compact : '${compact.substring(0, max)}...';
}

List<String> parseAllowedModels(dynamic value) {
  Iterable<dynamic> raw;
  if (value is List) {
    raw = value;
  } else {
    raw = (value?.toString() ?? '').split(',');
  }
  final result =
      raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  return result;
}

String encodeProviderApiKey(String apiKey) =>
    base64UrlEncode(utf8.encode(apiKey)).replaceAll('=', '');

String decodeProviderApiKey(String cipher) {
  if (cipher.trim().isEmpty) return '';
  try {
    var normalized = cipher.trim();
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    return utf8.decode(base64Url.decode(normalized));
  } catch (_) {
    return cipher;
  }
}

String maskApiKey(String apiKey) {
  final value = apiKey.trim();
  if (value.isEmpty) return '';
  if (value.length <= 8) return '****';
  return '${value.substring(0, 3)}...${value.substring(value.length - 4)}';
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

bool? parseBool(String? value) {
  final text = value?.trim().toLowerCase() ?? '';
  if (text == 'true') return true;
  if (text == 'false') return false;
  return null;
}

bool parseEnvBool(String? value, {required bool fallback}) {
  final text = value?.trim().toLowerCase() ?? '';
  if (text.isEmpty) return fallback;
  if (text == '1' || text == 'true' || text == 'yes' || text == 'on') {
    return true;
  }
  if (text == '0' || text == 'false' || text == 'no' || text == 'off') {
    return false;
  }
  return fallback;
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
  response.headers.set(
    'Access-Control-Allow-Methods',
    'GET, POST, PATCH, DELETE, OPTIONS',
  );
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
