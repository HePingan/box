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

  // 启动时清理一次过期会话，并每 6 小时清一次（长期运行的进程不会自然重启）。
  final prunedAtBoot = store.pruneExpiredSessions();
  if (prunedAtBoot > 0) {
    stdout.writeln('Pruned $prunedAtBoot expired session(s) at startup.');
    await store.save();
  }
  Timer.periodic(const Duration(hours: 6), (_) async {
    final pruned = store.pruneExpiredSessions();
    if (pruned > 0) {
      stdout.writeln(
        '${DateTime.now().toIso8601String()} pruned $pruned expired session(s).',
      );
      await store.save();
    }
  });
  // A3：每 10 分钟清一次突发限流窗口的过期命中（内存防膨胀）。
  Timer.periodic(const Duration(minutes: 10), (_) {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 2));
    store.quizVisionBurstHits.updateAll(
      (_, hits) => hits..removeWhere((t) => t.isBefore(cutoff)),
    );
    store.quizVisionBurstHits.removeWhere((_, hits) => hits.isEmpty);
    // 顺带清用量/失败计数里两天前的旧日键（A2 落盘前先清，避免落盘垃圾）。
    final keepFloor = DateTime.now().toUtc()
        .toIso8601String()
        .substring(0, 10);
    void pruneDays(Map<String, Map<String, int>> map) {
      map.updateAll(
        (_, perDay) => perDay
          ..removeWhere((day, _) => day.compareTo(keepFloor) < 0),
      );
      map.removeWhere((_, perDay) => perDay.isEmpty);
    }

    pruneDays(store.quizVisionUsage);
    pruneDays(store.quizVisionUpstreamFailures);
  });
  // 启动时确保插件包目录存在（以 root 运行可正常创建）
  try {
    final stateFile = File(store.path);
    final parent = stateFile.parent;
    final dir = Directory('${parent.path}/plugin_packages');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  } catch (_) {}

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
  stdout.writeln('Quiz endpoints:');
  stdout.writeln('  GET  /api/quiz/catalogs');
  stdout.writeln('  GET  /api/quiz/sync?cursor=<n>&category=<id>');
  stdout.writeln('  POST /api/quiz/submissions');
  stdout.writeln('  POST /api/quiz/vision');
  stdout.writeln('  GET  /api/policy/plugins');
  stdout.writeln('  GET  /admin/policy/plugins');
  stdout.writeln('  PUT  /admin/policy/plugins');
  stdout.writeln('  PUT  /admin/accounts/<userId>/plugins');
  stdout.writeln('  GET  /admin/quiz-vision/provider');
  stdout.writeln('  POST /admin/quiz-vision/provider');
  stdout.writeln('Plugin market endpoints:');
  stdout.writeln('  GET  /api/plugin-market');
  stdout.writeln('  GET  /api/plugin-market/<id>');
  stdout.writeln('  POST /api/plugins/submissions');
  stdout.writeln('  POST /api/plugins/submissions/zip');
  stdout.writeln('  GET  /api/plugin-market/<id>/package');
  stdout.writeln('  POST /api/plugin-market/<id>/report');
  stdout.writeln('  GET  /admin/plugins/submissions/<id>/preview');
  stdout.writeln('  GET  /admin/plugins/reports');
  stdout.writeln('  POST /admin/plugins/authors/<id>/ban|unban');
  stdout.writeln('  GET  /api/plugins/mine');
  stdout.writeln('  GET  /admin/plugins/submissions');
  stdout.writeln('  POST /admin/plugins/submissions/<id>/approve|reject');
  stdout.writeln('  POST /admin/plugins/<id>/yank|feature');
  stdout.writeln('  POST /api/plugin-market/<id>/install');
  stdout.writeln('  POST /api/plugin-market/status');
  stdout.writeln('  GET  /admin/plugins/audit');
  stdout.writeln('  GET  /admin/plugins/stats');
  stdout.writeln('  GET  /admin/quiz/questions');
  stdout.writeln('  POST /admin/quiz/questions');
  stdout.writeln('  PATCH /admin/quiz/questions/<id>');
  stdout.writeln('  DELETE /admin/quiz/questions/<id>');
  stdout.writeln('  GET  /admin/quiz/submissions');
  stdout.writeln('  POST /admin/quiz/submissions/<id>/approve|reject');

  final app = PlatformQuotaServer(config, store);
  await for (final request in server) {
    unawaited(
      Future<void>(() async {
        try {
          await app.handle(request);
        } catch (error, stackTrace) {
          stderr.writeln('Unhandled request error: $error');
          stderr.writeln(stackTrace);
          await jsonResponse(request.response, HttpStatus.internalServerError, {
            'error': {'message': '平台服务异常：$error'},
          });
        }
      }),
    );
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

    final allowed = (env['IMAGE_ALLOWED_MODELS'] ?? '')
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
      registerDefaultQuota: int.tryParse(
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
  final LoginThrottle loginThrottle = LoginThrottle();

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
    // ── Personal center endpoints (user self-view, read-only) ──
    if (request.method == 'PATCH' && path == '/api/me/profile') {
      final account = await requireUser(request);
      if (account == null) return;
      await updateMyProfile(request, account);
      return;
    }
    if (request.method == 'GET' && path == '/api/me/overview') {
      final account = await requireUser(request);
      if (account == null) return;
      await meOverview(request, account);
      return;
    }
    if (request.method == 'GET' && path == '/api/me/quota/transactions') {
      final account = await requireUser(request);
      if (account == null) return;
      await meQuotaTransactions(request, account);
      return;
    }
    if (request.method == 'GET' && path == '/api/me/plugins') {
      final account = await requireUser(request);
      if (account == null) return;
      await mePlugins(request, account);
      return;
    }
    if (request.method == 'GET' && path == '/api/me/quiz/questions') {
      final account = await requireUser(request);
      if (account == null) return;
      await meQuizQuestions(request, account);
      return;
    }
    if (request.method == 'GET' && path == '/api/me/activity') {
      final account = await requireUser(request);
      if (account == null) return;
      await meActivity(request, account);
      return;
    }
    if (request.method == 'GET' && path == '/api/quiz/catalogs') {
      await quizCatalogs(request);
      return;
    }
    if (request.method == 'GET' && path == '/api/quiz/sync') {
      await quizSync(request);
      return;
    }
    if (request.method == 'POST' && path == '/api/quiz/submissions') {
      final account = await requireUser(request);
      if (account == null) return;
      await submitQuizQuestion(request, account);
      return;
    }
    if (request.method == 'POST' && path == '/api/quiz/vision') {
      final account = await requireUser(request);
      if (account == null) return;
      await quizVisionProxy(request, account);
      return;
    }
    // 别名路由：客户端引擎统一 POST {base}/chat/completions，base 指向
    // /api/quiz/vision 时正好落这里 —— 引擎零改动接入代理。
    if (request.method == 'POST' &&
        path == '/api/quiz/vision/chat/completions') {
      final account = await requireUser(request);
      if (account == null) return;
      await quizVisionProxy(request, account);
      return;
    }
    if (request.method == 'GET' && path == '/admin/quiz-vision/provider') {
      if (!await requireAdmin(request)) return;
      await adminGetQuizVisionProvider(request);
      return;
    }
    if (request.method == 'POST' && path == '/admin/quiz-vision/provider') {
      if (!await requireAdmin(request)) return;
      await adminUpdateQuizVisionProvider(request);
      return;
    }
    if (request.method == 'GET' && path == '/admin/quiz-vision/stats') {
      if (!await requireAdmin(request)) return;
      await adminGetQuizVisionStats(request);
      return;
    }
    if (request.method == 'GET' && path == '/api/policy/plugins') {
      // 允许未登录拉全局策略；登录则合并用户覆盖
      final account = await optionalUser(request);
      await getPluginPolicy(request, account);
      return;
    }
    if (request.method == 'GET' && path == '/admin/policy/plugins') {
      if (!await requireAdmin(request)) return;
      await adminGetPluginPolicy(request);
      return;
    }
    if (request.method == 'PUT' && path == '/admin/policy/plugins') {
      if (!await requireAdmin(request)) return;
      await adminPutPluginPolicy(request);
      return;
    }
    final userPluginsMatch =
        RegExp(r'^/admin/accounts/([^/]+)/plugins$').firstMatch(path);
    if (request.method == 'PUT' && userPluginsMatch != null) {
      if (!await requireAdmin(request)) return;
      await adminPutUserPlugins(request, userPluginsMatch.group(1)!);
      return;
    }
    // ── 云端书源 / 公告（新增） ──
    if (request.method == 'GET' && path == '/api/book-sources') {
      await publicBookSources(request);
      return;
    }
    if (request.method == 'GET' && path == '/admin/book-sources') {
      if (!await requireAdmin(request)) return;
      await adminListBookSources(request);
      return;
    }
    if (request.method == 'POST' && path == '/admin/book-sources/publish') {
      if (!await requireAdmin(request)) return;
      await adminPublishBookSources(request);
      return;
    }
    final bookSourceDeleteMatch =
        RegExp(r'^/admin/book-sources/([^/]+)$').firstMatch(path);
    if (request.method == 'DELETE' && bookSourceDeleteMatch != null) {
      if (!await requireAdmin(request)) return;
      await adminDeleteBookSource(
        request,
        Uri.decodeComponent(bookSourceDeleteMatch.group(1)!),
      );
      return;
    }
    if (request.method == 'GET' && path == '/api/announcements') {
      await publicAnnouncements(request);
      return;
    }
    if (request.method == 'GET' && path == '/admin/announcements') {
      if (!await requireAdmin(request)) return;
      await adminListAnnouncements(request);
      return;
    }
    if (request.method == 'POST' && path == '/admin/announcements') {
      if (!await requireAdmin(request)) return;
      await adminCreateAnnouncement(request);
      return;
    }
    final announcementIdMatch =
        RegExp(r'^/admin/announcements/([^/]+)$').firstMatch(path);
    if (announcementIdMatch != null &&
        (request.method == 'PATCH' || request.method == 'DELETE')) {
      if (!await requireAdmin(request)) return;
      final annId = Uri.decodeComponent(announcementIdMatch.group(1)!);
      if (request.method == 'PATCH') {
        await adminUpdateAnnouncement(request, annId);
      } else {
        await adminDeleteAnnouncement(request, annId);
      }
      return;
    }
    // ── Plugin market ──
    if (request.method == 'GET' && path == '/api/plugin-market') {
      await pluginMarketManifest(request);
      return;
    }
    final marketDetailMatch =
        RegExp(r'^/api/plugin-market/([^/]+)$').firstMatch(path);
    if (request.method == 'GET' && marketDetailMatch != null) {
      await pluginMarketDetail(
        request,
        Uri.decodeComponent(marketDetailMatch.group(1)!),
      );
      return;
    }
    if (request.method == 'POST' && path == '/api/plugins/submissions') {
      final account = await requireUser(request);
      if (account == null) return;
      await submitPlugin(request, account);
      return;
    }
    if (request.method == 'POST' && path == '/api/plugins/submissions/zip') {
      final account = await requireUser(request);
      if (account == null) return;
      await submitPluginZip(request, account);
      return;
    }
    final marketPackageMatch =
        RegExp(r'^/api/plugin-market/([^/]+)/package$').firstMatch(path);
    if (request.method == 'GET' && marketPackageMatch != null) {
      await pluginMarketPackage(
        request,
        Uri.decodeComponent(marketPackageMatch.group(1)!),
      );
      return;
    }
    final marketReportMatch =
        RegExp(r'^/api/plugin-market/([^/]+)/report$').firstMatch(path);
    if (request.method == 'POST' && marketReportMatch != null) {
      final account = await requireUser(request);
      if (account == null) return;
      await reportPlugin(
        request,
        account,
        Uri.decodeComponent(marketReportMatch.group(1)!),
      );
      return;
    }
    final previewMatch = RegExp(
      r'^/admin/plugins/submissions/([^/]+)/preview$',
    ).firstMatch(path);
    if (request.method == 'GET' && previewMatch != null) {
      if (!await requireAdmin(request)) return;
      await adminPreviewSubmission(request, previewMatch.group(1)!);
      return;
    }
    if (request.method == 'GET' && path == '/admin/plugins/reports') {
      if (!await requireAdmin(request)) return;
      await adminListReports(request);
      return;
    }
    final authorBanMatch = RegExp(
      r'^/admin/plugins/authors/([^/]+)/(ban|unban)$',
    ).firstMatch(path);
    if (request.method == 'POST' && authorBanMatch != null) {
      if (!await requireAdmin(request)) return;
      await adminBanAuthor(
        request,
        Uri.decodeComponent(authorBanMatch.group(1)!),
        authorBanMatch.group(2)! == 'ban',
      );
      return;
    }
    if (request.method == 'GET' && path == '/api/plugins/mine') {
      final account = await requireUser(request);
      if (account == null) return;
      await listMyPlugins(request, account);
      return;
    }
    if (request.method == 'GET' && path == '/admin/plugins/submissions') {
      if (!await requireAdmin(request)) return;
      await adminListPluginSubmissions(request);
      return;
    }
    if (request.method == 'POST' &&
        path == '/admin/plugins/submissions/bulk-review') {
      if (!await requireAdmin(request)) return;
      await adminBulkReviewPluginSubmissions(request);
      return;
    }
    final pluginReviewMatch = RegExp(
      r'^/admin/plugins/submissions/([^/]+)/(approve|reject)$',
    ).firstMatch(path);
    if (request.method == 'POST' && pluginReviewMatch != null) {
      if (!await requireAdmin(request)) return;
      await adminReviewPluginSubmission(
        request,
        pluginReviewMatch.group(1)!,
        pluginReviewMatch.group(2)!,
      );
      return;
    }
    final pluginYankMatch =
        RegExp(r'^/admin/plugins/([^/]+)/yank$').firstMatch(path);
    if (request.method == 'POST' && pluginYankMatch != null) {
      if (!await requireAdmin(request)) return;
      await adminYankPlugin(
        request,
        Uri.decodeComponent(pluginYankMatch.group(1)!),
      );
      return;
    }
    final pluginFeatureMatch =
        RegExp(r'^/admin/plugins/([^/]+)/feature$').firstMatch(path);
    if (request.method == 'POST' && pluginFeatureMatch != null) {
      if (!await requireAdmin(request)) return;
      await adminFeaturePlugin(
        request,
        Uri.decodeComponent(pluginFeatureMatch.group(1)!),
      );
      return;
    }
    final pluginInstallMatch =
        RegExp(r'^/api/plugin-market/([^/]+)/install$').firstMatch(path);
    if (request.method == 'POST' && pluginInstallMatch != null) {
      await pluginMarketInstall(
        request,
        Uri.decodeComponent(pluginInstallMatch.group(1)!),
      );
      return;
    }
    if (request.method == 'POST' && path == '/api/plugin-market/status') {
      await pluginMarketStatus(request);
      return;
    }
    if (request.method == 'GET' && path == '/admin/plugins/audit') {
      if (!await requireAdmin(request)) return;
      await adminPluginAudit(request);
      return;
    }
    if (request.method == 'GET' && path == '/admin/plugins/stats') {
      if (!await requireAdmin(request)) return;
      await adminPluginStats(request);
      return;
    }
    if (request.method == 'GET' && path == '/admin/quiz/questions') {
      if (!await requireAdmin(request)) return;
      await adminQuizQuestions(request);
      return;
    }
    if (request.method == 'POST' && path == '/admin/quiz/questions') {
      if (!await requireAdmin(request)) return;
      await createQuizQuestion(request);
      return;
    }
    if (request.method == 'POST' && path == '/admin/quiz/import') {
      if (!await requireAdmin(request)) return;
      await importQuizQuestions(request);
      return;
    }
    if (request.method == 'POST' && path == '/admin/quiz/questions/bulk') {
      if (!await requireAdmin(request)) return;
      await bulkUpdateQuizQuestions(request);
      return;
    }
    if (request.method == 'POST' && path == '/admin/quiz/categories/bulk') {
      if (!await requireAdmin(request)) return;
      await bulkCategorizeQuizQuestions(request);
      return;
    }
    if (request.method == 'GET' && path == '/admin/quiz/imports') {
      if (!await requireAdmin(request)) return;
      await adminQuizImports(request);
      return;
    }
    if (request.method == 'GET' && path == '/admin/quiz/incomplete') {
      if (!await requireAdmin(request)) return;
      await adminIncompleteQuizQuestions(request);
      return;
    }
    if (request.method == 'POST' && path == '/admin/quiz/incomplete/bulk') {
      if (!await requireAdmin(request)) return;
      await bulkIncompleteQuizQuestions(request);
      return;
    }
    if (request.method == 'PATCH' &&
        path.startsWith('/admin/quiz/incomplete/')) {
      if (!await requireAdmin(request)) return;
      await completeQuizQuestion(
        request,
        path.substring('/admin/quiz/incomplete/'.length),
      );
      return;
    }
    if (request.method == 'POST' && path == '/admin/quiz/images/upload') {
      if (!await requireAdmin(request)) return;
      await uploadQuizImage(request);
      return;
    }
    final quizImageMatch = RegExp(
      r'^/api/quiz/images/([^/]+)$',
    ).firstMatch(path);
    if (request.method == 'GET' && quizImageMatch != null) {
      await serveQuizImage(
        request,
        Uri.decodeComponent(quizImageMatch.group(1)!),
      );
      return;
    }
    if (request.method == 'GET' && path == '/admin/quiz/submissions') {
      if (!await requireAdmin(request)) return;
      await adminQuizSubmissions(request);
      return;
    }
    if (request.method == 'GET' && path == '/admin/quiz/submissions/pending') {
      if (!await requireAdmin(request)) return;
      await adminQuizSubmissions(request, forcedStatus: 'pending');
      return;
    }
    final quizQuestionMatch = RegExp(
      r'^/admin/quiz/questions/([^/]+)$',
    ).firstMatch(path);
    if (request.method == 'PATCH' && quizQuestionMatch != null) {
      if (!await requireAdmin(request)) return;
      await updateQuizQuestion(
        request,
        Uri.decodeComponent(quizQuestionMatch.group(1)!),
      );
      return;
    }
    if (request.method == 'DELETE' && quizQuestionMatch != null) {
      if (!await requireAdmin(request)) return;
      await deleteQuizQuestion(
        request,
        Uri.decodeComponent(quizQuestionMatch.group(1)!),
      );
      return;
    }
    final quizSubmissionAction = RegExp(
      r'^/admin/quiz/submissions/([^/]+)/(approve|reject)$',
    ).firstMatch(path);
    if (request.method == 'POST' && quizSubmissionAction != null) {
      if (!await requireAdmin(request)) return;
      await reviewQuizSubmission(
        request,
        Uri.decodeComponent(quizSubmissionAction.group(1)!),
        quizSubmissionAction.group(2)!,
      );
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
      final upstreamRequest =
          await client.getUrl(uri).timeout(const Duration(seconds: 12));
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

    // 登录节流：IP 与用户名双维度，锁定期内直接拒绝，不再做密码校验。
    final ip = clientIp(request);
    final throttleKeys = <String>['ip:$ip', 'user:${username.toLowerCase()}'];
    final retryAfter = loginThrottle.retryAfterSeconds(throttleKeys);
    if (retryAfter != null) {
      request.response.headers.set('Retry-After', '$retryAfter');
      await jsonResponse(request.response, HttpStatus.tooManyRequests, {
        'error': {'message': '登录失败次数过多，请 $retryAfter 秒后再试。'},
      });
      return;
    }

    final account = store.accountByUsername(username);
    if (account == null ||
        account.status != 'normal' ||
        !verifyPassword(password, account.passwordHash)) {
      loginThrottle.registerFailure(throttleKeys);
      await jsonResponse(request.response, HttpStatus.unauthorized, {
        'error': {'message': '用户名或密码错误'},
      });
      return;
    }
    loginThrottle.registerSuccess(throttleKeys);

    // 惰性迁移：旧格式哈希在首次登录时自动升级为 PBKDF2
    if (account.passwordHash.startsWith('sha256:')) {
      account.passwordHash = hashPassword(password);
      stderr.writeln(
          '[INFO] Migrated password hash for ${account.username} from sha256 to pbkdf2');
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

  /// PATCH /api/me/profile
  /// 仅允许当前 JWT 对应用户修改自己的展示昵称；不接受 userId，且不修改登录用户名。
  Future<void> updateMyProfile(HttpRequest request, Account account) async {
    final decoded = await readJsonObject(request);
    if (decoded == null) return;
    final nickname = decoded['nickname']?.toString().trim() ?? '';
    if (nickname.isEmpty || nickname.length > 32) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '昵称不能为空且长度不能超过 32 个字符'},
      });
      return;
    }
    account.nickname = nickname;
    await store.save();
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
      'topUsersToday':
          sortedTopUsers.take(5).map((item) => item.toJson()).toList(),
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

  // ── AI 读屏代理（新增） ──

  QuizVisionProviderConfig? get effectiveQuizVision {
    final provider = store.quizVisionProvider;
    if (provider == null || !provider.enabled) return null;
    if (provider.baseUrl.isEmpty || provider.apiKeyCipher.isEmpty) return null;
    return provider;
  }

  Map<String, dynamic> quizVisionPublicJson() {
    final provider = store.quizVisionProvider;
    final apiKey = decodeProviderApiKey(provider?.apiKeyCipher ?? '');
    return {
      'baseUrl': provider?.baseUrl ?? '',
      'apiKeyMask': maskApiKey(apiKey),
      'hasApiKey': apiKey.trim().isNotEmpty,
      'model': provider?.model ?? '',
      'enabled': provider?.enabled ?? false,
      'dailyCapPerAccount': quizVisionDailyCap,
      'updatedAt': provider?.updatedAt?.toIso8601String(),
    };
  }

  /// A1 用量统计：只记账号 ID/次数/失败数，不记任何请求内容。
  Map<String, dynamic> quizVisionStatsJson() {
    final dayKey = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    var total = 0;
    var failed = 0;
    final perAccount = <String, int>{};
    store.quizVisionUsage.forEach((accountId, perDay) {
      final today = perDay[dayKey] ?? 0;
      if (today <= 0) return;
      total += today;
      perAccount[accountId] = today;
    });
    store.quizVisionUpstreamFailures.forEach((accountId, perDay) {
      failed += perDay[dayKey] ?? 0;
    });
    return {
      'day': dayKey,
      'total': total,
      'failed': failed,
      'accounts': perAccount.length,
      'perAccount': perAccount,
      'dailyCapPerAccount': quizVisionDailyCap,
    };
  }

  Future<void> adminGetQuizVisionStats(HttpRequest request) async {
    await jsonResponse(request.response, HttpStatus.ok, quizVisionStatsJson());
  }

  Future<void> adminGetQuizVisionProvider(HttpRequest request) async {
    await jsonResponse(
      request.response,
      HttpStatus.ok,
      quizVisionPublicJson(),
    );
  }

  Future<void> adminUpdateQuizVisionProvider(HttpRequest request) async {
    final decoded = await readJsonObject(request);
    if (decoded == null) return;
    final previous = store.quizVisionProvider;
    final baseUrl = (decoded['baseUrl']?.toString() ?? previous?.baseUrl ?? '')
        .trim()
        .replaceAll(RegExp(r'/+$'), '');
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
    final nextApiKeyCipher = clearApiKey
        ? ''
        : apiKey.trim().isEmpty
            ? previous?.apiKeyCipher ?? ''
            : encodeProviderApiKey(apiKey.trim());
    final model = (decoded['model']?.toString() ??
            (previous?.model.isNotEmpty == true ? previous!.model : ''))
        .trim();
    final enabled = decoded['enabled'] is bool
        ? decoded['enabled'] as bool
        : previous?.enabled ?? false;
    store.quizVisionProvider = QuizVisionProviderConfig(
      baseUrl: baseUrl,
      apiKeyCipher: nextApiKeyCipher,
      model: model,
      enabled: enabled,
      updatedAt: DateTime.now(),
    );
    await store.save();
    store.markQuizVisionPersisted();
    await jsonResponse(request.response, HttpStatus.ok, quizVisionPublicJson());
  }

  Future<void> quizVisionProxy(HttpRequest request, Account account) async {
    final provider = effectiveQuizVision;
    if (provider == null) {
      await jsonResponse(request.response, HttpStatus.serviceUnavailable, {
        'error': {'message': 'AI 读屏上游未配置或已停用。'},
      });
      return;
    }
    final decoded = await readJsonObject(request);
    if (decoded == null) return;

    final dayKey = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    // A3 突发限流：每账号每分钟最多 quizVisionBurstCap 次（内存滑动窗口），
    // 防客户端死循环打爆上游渠道。
    if (store.quizVisionBurstRejected(account.id, DateTime.now())) {
      await jsonResponse(request.response, HttpStatus.tooManyRequests, {
        'error': {'message': 'AI 读屏请求过于频繁，请稍等几秒再试。'},
      });
      return;
    }
    // 每账号每日限额（UTC 日键）。
    final userCounts =
        store.quizVisionUsage.putIfAbsent(account.id, () => <String, int>{});
    final usedToday = userCounts[dayKey] ?? 0;
    if (usedToday >= quizVisionDailyCap) {
      await jsonResponse(request.response, HttpStatus.tooManyRequests, {
        'error': {
          'message': '今日 AI 读屏次数已用完（$quizVisionDailyCap 次/日），明天再试。',
        },
      });
      return;
    }

    // 透传 chat/completions 请求体；后台配置了 model 则强制覆盖。
    if (provider.model.isNotEmpty) {
      decoded['model'] = provider.model;
    }
    final UpstreamResponse upstream;
    try {
      upstream = await postChatCompletionUpstream(provider, decoded);
    } catch (error) {
      store.quizVisionRecordUpstreamFailure(account.id, dayKey);
      await jsonResponse(request.response, HttpStatus.serviceUnavailable, {
        'error': {'message': 'AI 读屏上游请求失败：${compactPreview('$error')}'},
      });
      return;
    }
    if (upstream.statusCode < 200 || upstream.statusCode >= 300) {
      store.quizVisionRecordUpstreamFailure(account.id, dayKey);
    }
    userCounts[dayKey] = usedToday + 1;
    store.quizVisionDirty = true;
    store.scheduleQuizVisionFlush();
    // 只记账号/状态/字节数，不记请求与响应内容，不记 key。
    stdout.writeln(
      '${DateTime.now().toIso8601String()} quiz-vision account=${account.id} '
      'upstream=${upstream.statusCode} bytes=${upstream.text.length}',
    );
    await jsonText(request.response, upstream.statusCode, upstream.text);
  }

  Future<UpstreamResponse> postChatCompletionUpstream(
    QuizVisionProviderConfig provider,
    Map<String, dynamic> body,
  ) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('${provider.baseUrl}/chat/completions');
      final req =
          await client.postUrl(uri).timeout(const Duration(seconds: 20));
      req.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${decodeProviderApiKey(provider.apiKeyCipher)}',
      );
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
      // 读屏截图 base64 较大，上游整链放宽到 90s。
      final resp = await req.close().timeout(const Duration(seconds: 90));
      final text = await utf8.decoder.bind(resp).join();
      return UpstreamResponse(resp.statusCode, text);
    } finally {
      client.close(force: true);
    }
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

  Future<void> quizCatalogs(HttpRequest request) async {
    final account = await optionalUser(request);
    final denied = store.pluginPolicy.denialFor(
      userId: account?.id,
      pluginId: 'builtin_quiz_bank_view',
      feature: 'cloud_pull',
    );
    if (denied != null) {
      await jsonResponse(request.response, HttpStatus.forbidden, {
        'error': {'message': denied, 'code': 'plugin_denied'},
      });
      return;
    }
    final catalogs = store.quizQuestions.values
        .where((q) => q.status == 'published')
        .map((q) => q.category)
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    await jsonResponse(request.response, HttpStatus.ok, {
      'catalogs': catalogs
          .map(
            (id) => {
              'id': id,
              'name': id,
              'count': store.quizQuestions.values
                  .where((q) => q.status == 'published' && q.category == id)
                  .length,
            },
          )
          .toList(),
      'cursor': store.quizSequence,
    });
  }

  Future<void> quizSync(HttpRequest request) async {
    final account = await optionalUser(request);
    final denied = store.pluginPolicy.denialFor(
      userId: account?.id,
      pluginId: 'builtin_quiz_bank_view',
      feature: 'cloud_pull',
    );
    if (denied != null) {
      await jsonResponse(request.response, HttpStatus.forbidden, {
        'error': {'message': denied, 'code': 'plugin_denied'},
      });
      return;
    }
    final cursor =
        int.tryParse(request.uri.queryParameters['cursor'] ?? '') ?? 0;
    final category = request.uri.queryParameters['category']?.trim() ?? '';
    final requestedLimit =
        int.tryParse(request.uri.queryParameters['limit'] ?? '') ?? 300;
    final limit = requestedLimit.clamp(1, 500);
    final eligible = store.quizChanges
        .where((change) => change.sequence > cursor)
        .where((change) {
      if (category.isEmpty) return true;
      final question = store.quizQuestions[change.questionId];
      return question?.category == category;
    }).toList();
    final page = eligible.take(limit).toList();
    final nextCursor = page.isEmpty ? cursor : page.last.sequence;
    final changes = page
        .map((change) => change.toJson(store.quizQuestions[change.questionId]))
        .toList();
    await jsonResponse(request.response, HttpStatus.ok, {
      'cursor': nextCursor,
      'nextCursor': nextCursor,
      'serverCursor': store.quizSequence,
      'hasMore': eligible.length > page.length,
      'changes': changes,
    });
  }

  Future<void> submitQuizQuestion(HttpRequest request, Account account) async {
    final denied = store.pluginPolicy.denialFor(
      userId: account.id,
      pluginId: 'builtin_quiz_bank_view',
      feature: 'cloud_push',
    );
    if (denied != null) {
      await jsonResponse(request.response, HttpStatus.forbidden, {
        'error': {'message': denied, 'code': 'plugin_denied'},
      });
      return;
    }
    final body = await readJsonObject(request);
    if (body == null) return;
    final question = QuizQuestion.fromRequest(
      body,
      id: store.nextQuizSubmissionId(),
      status: 'pending',
    );
    final error = question.validationError;
    if (error != null) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': error},
      });
      return;
    }
    final sameContent = store.quizQuestions.values
        .where(
          (q) =>
              q.identityKey == question.identityKey &&
              q.status == 'published',
        )
        .toList();
    final duplicate = sameContent.any((q) => quizImagesMatch(q, question));
    final sameContentDifferentImage =
        sameContent.isNotEmpty && !duplicate && quizHasKnownImage(question);
    final submission = QuizSubmission(
      id: question.id,
      question: question,
      submitterUserId: account.id,
      status: duplicate ? 'merged' : 'pending',
      submittedAt: DateTime.now(),
      reviewNote: duplicate
          ? '正式题库已存在相同题目与图片'
          : (sameContentDifferentImage ? '同文不同图，进入补图审核' : ''),
    );
    store.quizSubmissions[submission.id] = submission;
    await store.save();
    await jsonResponse(
      request.response,
      HttpStatus.created,
      submission.toJson(),
    );
  }

  Future<void> importQuizQuestions(HttpRequest request) async {
    final body = await readJsonObject(request);
    if (body == null) return;
    final rawItems = body['items'] ?? body['questions'] ?? body['data'];
    if (rawItems is! List) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '导入内容必须包含 items 数组。'},
      });
      return;
    }
    final publish = body['mode']?.toString() != 'pending';
    final dryRun = body['dryRun'] == true;
    var inserted = 0;
    var duplicateSkipped = 0;
    var invalid = 0;
    final errors = <Map<String, dynamic>>[];
    final seen = <String>{};
    final accepted = <QuizQuestion>[];
    for (var index = 0; index < rawItems.length; index++) {
      final raw = rawItems[index];
      if (raw is! Map) {
        invalid++;
        if (errors.length < 50) {
          errors.add({'index': index, 'message': '题目不是 JSON 对象'});
        }
        continue;
      }
      final question = QuizQuestion.fromRequest(
        Map<String, dynamic>.from(raw),
        id: store.nextQuizQuestionId(),
        status: publish ? 'published' : 'pending',
      );
      final error = question.validationError;
      if (error != null) {
        invalid++;
        if (errors.length < 50) {
          errors.add({
            'index': index,
            'message': error,
            'question': question.question,
          });
        }
        continue;
      }
      final duplicate = !seen.add(question.identityKey) ||
          store.quizQuestions.values.any(
            (q) =>
                q.identityKey == question.identityKey && q.status != 'archived',
          );
      if (duplicate) {
        duplicateSkipped++;
        continue;
      }
      accepted.add(question);
    }
    inserted = accepted.length;
    final now = DateTime.now();
    final importId = 'qi_${randomBase64(9)}';
    if (!dryRun) {
      for (final question in accepted) {
        store.quizQuestions[question.id] = question;
        if (question.status == 'published') {
          store.recordQuizChange(question.id, 'upsert');
        }
      }
      for (var index = 0; index < rawItems.length; index++) {
        final raw = rawItems[index];
        if (raw is! Map) continue;
        final candidate = QuizQuestion.fromRequest(
          Map<String, dynamic>.from(raw),
          id: '',
          status: 'incomplete',
        );
        final error = candidate.validationError;
        if (error != null) {
          store.quizIncomplete.add(
            QuizIncompleteRecord(
              id: 'qi_item_${randomBase64(9)}',
              importId: importId,
              sourceIndex: index,
              question: candidate.question,
              type: candidate.type,
              options: candidate.options,
              correctAnswer: candidate.correctAnswer,
              analysis: candidate.analysis,
              source: candidate.source,
              reason: error,
              createdAt: now,
              category: candidate.category,
            ),
          );
        }
      }
      store.quizImports.add(
        QuizImportRecord(
          id: importId,
          importedAt: now,
          mode: publish ? 'published' : 'pending',
          total: rawItems.length,
          inserted: inserted,
          duplicateSkipped: duplicateSkipped,
          invalid: invalid,
        ),
      );
      await store.save();
    }
    await jsonResponse(request.response, HttpStatus.ok, {
      'dryRun': dryRun,
      'mode': publish ? 'published' : 'pending',
      'total': rawItems.length,
      'inserted': inserted,
      'duplicateSkipped': duplicateSkipped,
      'invalid': invalid,
      'errors': errors,
    });
  }

  Future<void> bulkCategorizeQuizQuestions(HttpRequest request) async {
    final body = await readJsonObject(request);
    if (body == null) return;
    final category = body['category']?.toString().trim() ?? '';
    final ids =
        (body['ids'] as List? ?? const []).map((id) => id.toString()).toSet();
    if (category.isEmpty || ids.isEmpty) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': 'category 和 ids 不能为空'},
      });
      return;
    }
    var updated = 0;
    for (final id in ids) {
      final question = store.quizQuestions[id];
      if (question == null || question.status == 'archived') continue;
      if (question.category == category) continue;
      question.category = category;
      question.revision++;
      question.updatedAt = DateTime.now();
      if (question.status == 'published') store.recordQuizChange(id, 'upsert');
      updated++;
    }
    await store.save();
    await jsonResponse(request.response, HttpStatus.ok, {
      'updated': updated,
      'category': category,
    });
  }

  Future<void> adminQuizImports(HttpRequest request) async {
    await jsonResponse(request.response, HttpStatus.ok, {
      'imports': store.quizImports
          .map((record) => record.toJson())
          .toList()
          .reversed
          .toList(),
    });
  }

  Future<void> adminIncompleteQuizQuestions(HttpRequest request) async {
    final filter = request.uri.queryParameters['filter']?.trim() ?? '';
    final q = request.uri.queryParameters['q']?.trim().toLowerCase() ?? '';
    // 「人工标记为问题题」的题：题库里 status=incomplete 的记录。
    //
    // 背景：残缺队列 store.quizIncomplete 只收**导入时校验失败**的临时记录，
    // 已发布题标不进去。用户要「把答案存疑的题标记出来、后端能看」，
    // 故这里把题库里 status=incomplete 的题**合成**成残缺记录一并返回，
    // 用 questionId 区分来源（空=导入残缺，非空=人工标记）。
    // 管理端「残缺」格与队列因此天然覆盖两类，无需第二套 UI。
    final flagged = store.quizQuestions.values
        .where((question) => question.status == 'incomplete')
        .map(
          (question) => QuizIncompleteRecord(
            id: 'flag_${question.id}',
            importId: '',
            sourceIndex: 0,
            question: question.question,
            type: question.type,
            options: question.options,
            correctAnswer: question.correctAnswer,
            analysis: question.analysis,
            source: question.source,
            reason: question.issueReason.isNotEmpty
                ? question.issueReason
                : '需按图确认答案',
            createdAt: question.updatedAt,
            category: question.category,
            questionId: question.id,
          ),
        )
        .toList();
    final imported = store.quizIncomplete.length;
    Iterable<QuizIncompleteRecord> items = [
      ...store.quizIncomplete,
      ...flagged,
    ];
    if (filter == 'missing_answer') {
      items = items.where((item) => item.correctAnswer.trim().isEmpty);
    } else if (filter == 'missing_options') {
      items = items.where(
        (item) => item.type != 'true_false' && item.options.length < 2,
      );
    } else if (filter == 'has_reason') {
      items = items.where((item) => item.reason.trim().isNotEmpty);
    } else if (filter == 'flagged') {
      // 只留「人工标记为问题题」的题（questionId 非空即来自题库 flagged 合成）。
      // 注意不要用 has_reason 替代：导入残缺记录也都带 validationError 当 reason，
      // has_reason 会把 122 条导入残缺一起捞出来，分不出人工标记的。
      items = items.where((item) => item.questionId.trim().isNotEmpty);
    }
    if (q.isNotEmpty) {
      items = items.where(
        (item) =>
            item.question.toLowerCase().contains(q) ||
            item.reason.toLowerCase().contains(q) ||
            item.category.toLowerCase().contains(q),
      );
    }
    final list = items.map((item) => item.toJson()).toList().reversed.toList();
    await jsonResponse(request.response, HttpStatus.ok, {
      'items': list,
      'total': list.length,
      'queueTotal': list.length,
      'importedTotal': imported,
      'flaggedTotal': flagged.length,
      'filter': filter,
    });
  }

  /// 待补全批量操作：discard / set_category
  Future<void> bulkIncompleteQuizQuestions(HttpRequest request) async {
    final body = await readJsonObject(request);
    if (body == null) return;
    final action = body['action']?.toString().trim() ?? '';
    final ids = (body['ids'] as List? ?? const [])
        .map((id) => id.toString())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (action.isEmpty || ids.isEmpty) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': 'action 和 ids 不能为空'},
      });
      return;
    }
    if (action == 'discard' || action == 'delete') {
      // 人工标记的题（flag_<questionId>）不能真删 —— 它对应题库里一道存在的
      // 题，「丢弃」的语义是**取消标记**（status 翻回 published）。
      var unflagged = 0;
      for (final id in ids) {
        final match = RegExp(r'^flag_(.+)$').firstMatch(id);
        if (match == null) continue;
        final question = store.quizQuestions[match.group(1)!];
        if (question == null || question.status != 'incomplete') continue;
        store.quizQuestions[question.id] = question.copyWith(status: 'published');
        store.recordQuizChange(question.id, 'upsert');
        unflagged++;
      }
      final before = store.quizIncomplete.length;
      store.quizIncomplete.removeWhere((item) => ids.contains(item.id));
      final removed = before - store.quizIncomplete.length;
      await store.save();
      await jsonResponse(request.response, HttpStatus.ok, {
        'action': 'discard',
        'removed': removed,
        'unflagged': unflagged,
        'remaining': store.quizIncomplete.length,
      });
      return;
    }
    if (action == 'set_category') {
      final category = body['category']?.toString().trim() ?? '';
      if (category.isEmpty) {
        await jsonResponse(request.response, HttpStatus.badRequest, {
          'error': {'message': 'category 不能为空'},
        });
        return;
      }
      var updated = 0;
      final next = <QuizIncompleteRecord>[];
      for (final item in store.quizIncomplete) {
        if (!ids.contains(item.id)) {
          next.add(item);
          continue;
        }
        updated++;
        next.add(item.copyWith(category: category));
      }
      store.quizIncomplete
        ..clear()
        ..addAll(next);
      await store.save();
      await jsonResponse(request.response, HttpStatus.ok, {
        'action': 'set_category',
        'updated': updated,
        'category': category,
      });
      return;
    }
    if (action == 'publish' || action == 'complete') {
      final defaultAnswer = body['correctAnswer']?.toString().trim() ??
          body['answer']?.toString().trim() ??
          '';
      final defaultCategory = body['category']?.toString().trim() ?? '';
      final defaultAnalysis = body['analysis']?.toString().trim() ?? '';
      final defaultImage = body['image']?.toString().trim() ?? '';
      final answersRaw = body['answers'];
      final answers = <String, String>{};
      if (answersRaw is Map) {
        answersRaw.forEach((key, value) {
          final id = key.toString();
          final answer = value.toString().trim();
          if (id.isNotEmpty && answer.isNotEmpty) answers[id] = answer;
        });
      }
      var published = 0;
      var skipped = 0;
      final errors = <Map<String, dynamic>>[];
      final remain = <QuizIncompleteRecord>[];
      for (final record in store.quizIncomplete) {
        if (!ids.contains(record.id)) {
          remain.add(record);
          continue;
        }
        final answer = (answers[record.id] ?? defaultAnswer).trim();
        if (answer.isEmpty) {
          skipped++;
          errors.add({'id': record.id, 'message': '缺少正确答案'});
          remain.add(record);
          continue;
        }
        if (answer.length > 200) {
          skipped++;
          errors.add({'id': record.id, 'message': '正确答案过长'});
          remain.add(record);
          continue;
        }
        final category =
            defaultCategory.isNotEmpty ? defaultCategory : record.category;
        final analysis =
            defaultAnalysis.isNotEmpty ? defaultAnalysis : record.analysis;
        final question = QuizQuestion.fromRequest(
          {
            'question': record.question,
            'type': record.type,
            'options': record.options,
            'correctAnswer': answer,
            'analysis': analysis,
            'category': category,
            'source': record.source,
            'image': defaultImage,
          },
          id: store.nextQuizQuestionId(),
          status: 'published',
        );
        final error = question.validationError;
        if (error != null) {
          skipped++;
          errors.add({'id': record.id, 'message': error});
          remain.add(record);
          continue;
        }
        if (store.quizQuestions.values.any(
          (item) =>
              item.identityKey == question.identityKey &&
              item.status != 'archived',
        )) {
          skipped++;
          errors.add({'id': record.id, 'message': '题目及选项已存在'});
          remain.add(record);
          continue;
        }
        store.quizQuestions[question.id] = question;
        store.recordQuizChange(question.id, 'upsert');
        published++;
      }
      store.quizIncomplete
        ..clear()
        ..addAll(remain);
      await store.save();
      await jsonResponse(request.response, HttpStatus.ok, {
        'action': 'publish',
        'published': published,
        'skipped': skipped,
        'remaining': store.quizIncomplete.length,
        'errors': errors,
      });
      return;
    }
    await jsonResponse(request.response, HttpStatus.badRequest, {
      'error': {
        'message': '不支持的 action：$action（支持 discard/set_category/publish）'
      },
    });
  }

  Future<void> completeQuizQuestion(
    HttpRequest request,
    String recordId,
  ) async {
    // 「人工标记为问题题」的记录：id 形如 flag_<questionId>，它不在
    // store.quizIncomplete 里，而是题库中一道真实 status=incomplete 的题。
    // 处理语义与导入残缺不同 —— 导入残缺失配后是**新建**一道题；已发布过的题
    // 必须**原地更新**（否则会留下脏的旧题 + 制造重复题干）。
    final flaggedMatch = RegExp(r'^flag_(.+)$').firstMatch(recordId);
    if (flaggedMatch != null) {
      await completeFlaggedQuizQuestion(
        request,
        flaggedMatch.group(1)!,
      );
      return;
    }
    QuizIncompleteRecord? record;
    for (final item in store.quizIncomplete) {
      if (item.id == recordId) {
        record = item;
        break;
      }
    }
    if (record == null) {
      await jsonResponse(request.response, HttpStatus.notFound, {
        'error': {'message': '待补全题目不存在'},
      });
      return;
    }
    final body = await readJsonObject(request);
    if (body == null) return;
    final answer = body['correctAnswer']?.toString().trim() ??
        body['answer']?.toString().trim() ??
        '';
    if (answer.isEmpty) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '正确答案不能为空'},
      });
      return;
    }
    if (answer.length > 200) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '正确答案过长'},
      });
      return;
    }
    final options = (body['options'] as List?)
            ?.map((o) => o.toString().trim())
            .where((o) => o.isNotEmpty)
            .toList() ??
        record.options;
    final type = body['type']?.toString() ?? record.type;
    if (type != 'true_false' && options.length < 2) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '选项不能为空且至少两项'},
      });
      return;
    }
    final category = (body['category']?.toString() ?? record.category).trim();
    final question = QuizQuestion.fromRequest(
      {
        'question': body['question']?.toString() ?? record.question,
        'type': type,
        'options': options,
        'correctAnswer': answer,
        'analysis': body['analysis']?.toString() ?? record.analysis,
        'category': category,
        'source': record.source,
        'image': body['image']?.toString() ?? '',
        // 补图必须连指纹一起入库，否则引擎 _bestImageScore 直接 -1。
        'imagePerceptualHash': body['imagePerceptualHash']?.toString() ?? '',
        'imageRegionHash': body['imageRegionHash']?.toString() ?? '',
      },
      id: store.nextQuizQuestionId(),
      status: 'published',
    );
    final error = question.validationError;
    if (error != null) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': error},
      });
      return;
    }
    if (store.quizQuestions.values.any(
      (item) => item.identityKey == question.identityKey,
    )) {
      await jsonResponse(request.response, HttpStatus.conflict, {
        'error': {'message': '题目及选项已存在'},
      });
      return;
    }
    store.quizQuestions[question.id] = question;
    store.quizIncomplete.remove(record);
    store.recordQuizChange(question.id, 'upsert');
    await store.save();
    await jsonResponse(request.response, HttpStatus.ok, {
      'question': question.toJson(),
    });
  }

  /// 处理「人工标记为问题题」的题（id 形如 flag_<questionId>）。
  ///
  /// 与导入残缺的关键差异：这些题**已在题库中且可能早已发布**，所以是
  /// **原地更新**（补正确答案 / 分析 / 图片 + 指纹），完成后把
  /// status 从 incomplete 翻回 published；不新建题、不动 id/identityKey。
  Future<void> completeFlaggedQuizQuestion(
    HttpRequest request,
    String questionId,
  ) async {
    final existing = store.quizQuestions[questionId];
    if (existing == null) {
      await jsonResponse(request.response, HttpStatus.notFound, {
        'error': {'message': '题目不存在'},
      });
      return;
    }
    final body = await readJsonObject(request);
    if (body == null) return;
    final answer = body['correctAnswer']?.toString().trim() ??
        body['answer']?.toString().trim() ??
        '';
    if (answer.isEmpty) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '正确答案不能为空'},
      });
      return;
    }
    if (answer.length > 200) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '正确答案过长'},
      });
      return;
    }
    final nextQuestion = body['question']?.toString() ?? existing.question;
    final nextType = body['type']?.toString() ?? existing.type;
    final nextOptions = (body['options'] as List?)
            ?.map((o) => o.toString().trim())
            .where((o) => o.isNotEmpty)
            .toList() ??
        existing.options;
    final updated = QuizQuestion(
      id: existing.id,
      // 答案变了 identityKey 必须跟着重算，否则去重/匹配全乱。
      identityKey: quizIdentityKey(nextQuestion, nextOptions, answer),
      question: nextQuestion,
      type: nextType,
      options: nextOptions,
      correctAnswer: answer,
      analysis: body['analysis']?.toString() ?? existing.analysis,
      category: (body['category']?.toString() ?? existing.category).trim(),
      source: existing.source,
      // 补图必须连指纹一起入库，否则引擎 _bestImageScore 直接 -1。
      image: body['image']?.toString().isNotEmpty == true
          ? body['image']!.toString()
          : existing.image,
      imagePerceptualHash: body['imagePerceptualHash']?.toString().isNotEmpty ==
              true
          ? body['imagePerceptualHash']!.toString()
          : existing.imagePerceptualHash,
      imageRegionHash: body['imageRegionHash']?.toString().isNotEmpty == true
          ? body['imageRegionHash']!.toString()
          : existing.imageRegionHash,
      imageSha256: existing.imageSha256,
      imageStatus: existing.imageStatus,
      issueReason: '',          // 补全即问题已解，清掉标记说明
      status: 'published',
      revision: existing.revision + 1,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
    );
    final error = updated.validationError;
    if (error != null) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': error},
      });
      return;
    }
    store.quizQuestions[questionId] = updated;
    store.recordQuizChange(questionId, 'upsert');
    await store.save();
    await jsonResponse(request.response, HttpStatus.ok, {
      'question': updated.toJson(),
      'unflagged': true,
    });
  }

  Future<void> uploadQuizImage(HttpRequest request) async {
    final body = await readJsonObject(request);
    if (body == null) return;
    final imageData = body['image']?.toString() ?? '';
    if (imageData.isEmpty) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '图片数据不能为空'},
      });
      return;
    }
    Uint8List bytes;
    var ext = 'bin';
    try {
      final dataUrl = RegExp(
        r'^data:image/([a-zA-Z0-9+.-]+);base64,(.+)$',
        multiLine: false,
      ).firstMatch(imageData);
      if (dataUrl != null) {
        ext = _normalizeImageExt(dataUrl.group(1)!);
        bytes = base64Decode(dataUrl.group(2)!);
      } else {
        bytes = base64Decode(imageData);
        ext = 'png';
      }
    } catch (_) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '图片 base64 无效'},
      });
      return;
    }
    if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '图片大小无效（限制 8MB）'},
      });
      return;
    }
    final hash = sha256.convert(bytes).toString().substring(0, 16);
    final filename = 'quiz_${DateTime.now().millisecondsSinceEpoch}_$hash.$ext';
    final dir = store.quizImagesDir;
    if (!await dir.exists()) await dir.create(recursive: true);
    final path = '${dir.path}/$filename';
    await File(path).writeAsBytes(bytes, flush: true);
    await jsonResponse(request.response, HttpStatus.ok, {
      'url': '/api/quiz/images/$filename',
      'filename': filename,
    });
  }

  Future<void> serveQuizImage(HttpRequest request, String filename) async {
    final safeName = filename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '');
    if (safeName.isEmpty || safeName != filename) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '非法文件名'},
      });
      return;
    }
    final file = File('${store.quizImagesDir.path}/$safeName');
    if (!await file.exists()) {
      await jsonResponse(request.response, HttpStatus.notFound, {
        'error': {'message': '图片不存在'},
      });
      return;
    }
    final bytes = await file.readAsBytes();
    final ext =
        safeName.contains('.') ? safeName.split('.').last.toLowerCase() : 'bin';
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.set(
      HttpHeaders.contentTypeHeader,
      _imageContentType(ext),
    );
    request.response.headers.set(
      HttpHeaders.cacheControlHeader,
      'public, max-age=86400',
    );
    request.response.add(bytes);
    await request.response.close();
  }

  String _normalizeImageExt(String raw) {
    final value = raw.toLowerCase();
    if (value.contains('jpeg') || value == 'jpg') return 'jpg';
    if (value.contains('png')) return 'png';
    if (value.contains('webp')) return 'webp';
    if (value.contains('gif')) return 'gif';
    return 'png';
  }

  String _imageContentType(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> adminQuizQuestions(HttpRequest request) async {
    final keyword = request.uri.queryParameters['q']?.trim().toLowerCase() ??
        request.uri.queryParameters['search']?.trim().toLowerCase() ??
        '';
    final status = request.uri.queryParameters['status']?.trim() ?? '';
    final records = store.quizQuestions.values
        .where((q) {
          if (status.isNotEmpty && q.status != status) return false;
          return keyword.isEmpty ||
              q.question.toLowerCase().contains(keyword) ||
              q.options.any((o) => o.toLowerCase().contains(keyword));
        })
        .map((q) => q.toJson())
        .toList()
      ..sort(
        (a, b) => (b['updatedAt']?.toString() ?? '').compareTo(
          a['updatedAt']?.toString() ?? '',
        ),
      );
    await jsonResponse(request.response, HttpStatus.ok, {
      'questions': records,
      'total': records.length,
    });
  }

  Future<void> createQuizQuestion(HttpRequest request) async {
    final body = await readJsonObject(request);
    if (body == null) return;
    final question = QuizQuestion.fromRequest(
      body,
      id: store.nextQuizQuestionId(),
      status: body['status']?.toString() ?? 'published',
    );
    final error = question.validationError;
    if (error != null) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': error},
      });
      return;
    }
    if (store.quizQuestions.values.any(
      (q) => q.identityKey == question.identityKey && q.status != 'archived',
    )) {
      await jsonResponse(request.response, HttpStatus.conflict, {
        'error': {'message': '题干与完整选项集已存在，不能重复创建。'},
      });
      return;
    }
    store.quizQuestions[question.id] = question;
    if (question.status == 'published') {
      store.recordQuizChange(question.id, 'upsert');
    }
    await store.save();
    await jsonResponse(request.response, HttpStatus.created, question.toJson());
  }

  /// 正式题批量更新：目前支持 set_image / set_category。
  Future<void> bulkUpdateQuizQuestions(HttpRequest request) async {
    final body = await readJsonObject(request);
    if (body == null) return;
    final action = body['action']?.toString().trim() ?? '';
    final ids = (body['ids'] as List? ?? const [])
        .map((id) => id.toString())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (action.isEmpty || ids.isEmpty) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': 'action 和 ids 不能为空'},
      });
      return;
    }
    if (action == 'set_image') {
      final image = body['image']?.toString().trim() ?? '';
      if (image.isEmpty) {
        await jsonResponse(request.response, HttpStatus.badRequest, {
          'error': {'message': 'image 不能为空'},
        });
        return;
      }
      // 客户端算好的题图指纹。服务端**从不**自行计算 dHash，只从请求体读；
      // 不带 ⇒ 入库题「有图无指纹」⇒ 引擎 _bestImageScore 直接 -1
      // ⇒ 同题干多候选仍然只靠文字二选一，用户继续看到「请人工确认」。
      final perceptualHash =
          body['imagePerceptualHash']?.toString().trim() ?? '';
      final regionHash = body['imageRegionHash']?.toString().trim() ?? '';
      final hasHash = RegExp(r'^[0-9a-f]{16}$').hasMatch(perceptualHash) &&
          RegExp(r'^[0-9a-f]{16}$').hasMatch(regionHash);
      var updated = 0;
      for (final id in ids) {
        final old = store.quizQuestions[id];
        if (old == null || old.status == 'archived') continue;
        final question = hasHash
            ? old.copyWith(
                image: image,
                imagePerceptualHash: perceptualHash,
                imageRegionHash: regionHash,
              )
            : old.copyWith(image: image);
        question.revision = old.revision + 1;
        store.quizQuestions[id] = question;
        if (question.status == 'published') {
          store.recordQuizChange(id, 'upsert');
        }
        updated++;
      }
      await store.save();
      await jsonResponse(request.response, HttpStatus.ok, {
        'action': 'set_image',
        'updated': updated,
        'image': image,
      });
      return;
    }
    if (action == 'set_category') {
      final category = body['category']?.toString().trim() ?? '';
      if (category.isEmpty) {
        await jsonResponse(request.response, HttpStatus.badRequest, {
          'error': {'message': 'category 不能为空'},
        });
        return;
      }
      var updated = 0;
      for (final id in ids) {
        final old = store.quizQuestions[id];
        if (old == null || old.status == 'archived') continue;
        final question = QuizQuestion.fromRequest(
          {...old.toJson(), 'category': category},
          id: id,
          status: old.status,
          revision: old.revision + 1,
          createdAt: old.createdAt,
        );
        store.quizQuestions[id] = question;
        if (question.status == 'published') {
          store.recordQuizChange(id, 'upsert');
        }
        updated++;
      }
      await store.save();
      await jsonResponse(request.response, HttpStatus.ok, {
        'action': 'set_category',
        'updated': updated,
        'category': category,
      });
      return;
    }
    await jsonResponse(request.response, HttpStatus.badRequest, {
      'error': {
        'message': '不支持的 action：$action（支持 set_image/set_category）',
      },
    });
  }

  Future<void> updateQuizQuestion(HttpRequest request, String id) async {
    final old = store.quizQuestions[id];
    if (old == null) {
      await jsonResponse(request.response, HttpStatus.notFound, {
        'error': {'message': '题目不存在'},
      });
      return;
    }
    final body = await readJsonObject(request);
    if (body == null) return;
    final status = body['status']?.toString() ?? old.status;
    final question = QuizQuestion.fromRequest(
      {
        ...old.toJson(),
        ...body,
        // 翻回 published 时顺手清掉标记原因；标记时写入传入的 reason。
        'issueReason': status == 'incomplete'
            ? (body['issueReason']?.toString() ?? old.issueReason)
            : '',
      },
      id: id,
      status: status,
      revision: old.revision + 1,
      createdAt: old.createdAt,
    );
    final error = question.validationError;
    if (error != null) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': error},
      });
      return;
    }
    // 查重只拦「本次更新新引入的冲突」，不拦已经存在的历史冲突。
    //
    // 背景：库里存量数据本就有 identityKey 相同的记录（早期算法没把答案纳入指纹，
    // 看图题批量录入时产生了重复）。如果无条件查重，给这类题改图/改分类都会撞上
    // 它的历史孪生记录而被 409 挡死，补图功能完全不可用。
    //
    // 判定方式：比较更新前后各自撞到的记录集合。集合没变大说明冲突是历史遗留的，
    // 本次更新既没制造新重复也没加重问题，放行；一旦撞上了原先没撞的记录，
    // 说明是真的想把两道不同的题合并成一道，拦下。
    Set<String> conflictIds(String identityKey) => store.quizQuestions.values
        .where((q) =>
            q.id != id &&
            q.identityKey == identityKey &&
            q.status != 'archived')
        .map((q) => q.id)
        .toSet();

    final newConflicts =
        conflictIds(question.identityKey).difference(conflictIds(old.identityKey));
    if (newConflicts.isNotEmpty) {
      await jsonResponse(request.response, HttpStatus.conflict, {
        'error': {'message': '题干与完整选项集已存在，不能合并覆盖。'},
      });
      return;
    }
    store.quizQuestions[id] = question;
    store.recordQuizChange(
      id,
      question.status == 'archived' ? 'delete' : 'upsert',
    );
    await store.save();
    await jsonResponse(request.response, HttpStatus.ok, question.toJson());
  }

  Future<void> deleteQuizQuestion(HttpRequest request, String id) async {
    final question = store.quizQuestions[id];
    if (question == null) {
      await jsonResponse(request.response, HttpStatus.notFound, {
        'error': {'message': '题目不存在'},
      });
      return;
    }
    question.status = 'archived';
    question.revision++;
    question.updatedAt = DateTime.now();
    store.recordQuizChange(id, 'delete');
    await store.save();
    await jsonResponse(request.response, HttpStatus.ok, {'ok': true, 'id': id});
  }

  Future<void> adminQuizSubmissions(
    HttpRequest request, {
    String? forcedStatus,
  }) async {
    final status =
        forcedStatus ?? request.uri.queryParameters['status']?.trim() ?? '';
    final records = store.quizSubmissions.values
        .where((s) => status.isEmpty || s.status == status)
        .map((s) => s.toJson())
        .toList()
      ..sort(
        (a, b) => (b['submittedAt']?.toString() ?? '').compareTo(
          a['submittedAt']?.toString() ?? '',
        ),
      );
    await jsonResponse(request.response, HttpStatus.ok, {
      'submissions': records,
      'total': records.length,
    });
  }

  Future<void> reviewQuizSubmission(
    HttpRequest request,
    String id,
    String action,
  ) async {
    final submission = store.quizSubmissions[id];
    if (submission == null) {
      await jsonResponse(request.response, HttpStatus.notFound, {
        'error': {'message': '候选题不存在'},
      });
      return;
    }
    final body = await readJsonObject(request) ?? const <String, dynamic>{};
    if (action == 'reject') {
      submission.status = 'rejected';
      submission.reviewNote = body['reviewNote']?.toString() ?? '';
      submission.reviewedAt = DateTime.now();
    } else {
      final matches = store.quizQuestions.values
          .where(
            (q) =>
                q.status == 'published' &&
                q.identityKey == submission.question.identityKey &&
                quizImagesMatch(q, submission.question),
          )
          .toList();
      final duplicate = matches.isEmpty ? null : matches.first;
      if (duplicate != null) {
        submission.status = 'merged';
        submission.linkedQuestionId = duplicate.id;
      } else {
        final published = submission.question.copyWith(
          id: store.nextQuizQuestionId(),
          status: 'published',
        );
        store.quizQuestions[published.id] = published;
        store.recordQuizChange(published.id, 'upsert');
        submission.status = 'approved';
        submission.linkedQuestionId = published.id;
      }
      submission.reviewNote = body['reviewNote']?.toString() ?? '';
      submission.reviewedAt = DateTime.now();
    }
    await store.save();
    await jsonResponse(request.response, HttpStatus.ok, submission.toJson());
  }

  // ── 云端书源（新增） ──

  /// 公开只读：客户端拉取全量/增量书源。
  ///
  /// `?since=<version>`：若客户端持有版本已是最新，返回 changed=false 且不带
  /// sources，省流量；否则返回全量（含 removed 墓碑）。
  Future<void> publicBookSources(HttpRequest request) async {
    final since = asInt(request.uri.queryParameters['since'], -1);
    final upToDate = since >= 0 && since >= store.bookSourceVersion;
    final all = store.cloudBookSources.values.toList()
      ..sort((a, b) {
        final bySort = a.sort.compareTo(b.sort);
        if (bySort != 0) return bySort;
        return a.name.compareTo(b.name);
      });
    await jsonResponse(request.response, HttpStatus.ok, {
      'version': store.bookSourceVersion,
      'changed': !upToDate,
      'publishedAt': store.bookSourcePublishedAt?.toIso8601String(),
      'count': all.where((s) => !s.removed).length,
      if (!upToDate)
        'sources': all.map((s) => s.toClientJson()).toList(growable: false),
    });
  }

  /// 管理端：列出云端书源（含墓碑，便于管理员看到删除记录）。
  Future<void> adminListBookSources(HttpRequest request) async {
    final all = store.cloudBookSources.values.toList()
      ..sort((a, b) {
        final bySort = a.sort.compareTo(b.sort);
        if (bySort != 0) return bySort;
        return a.name.compareTo(b.name);
      });
    await jsonResponse(request.response, HttpStatus.ok, {
      'version': store.bookSourceVersion,
      'publishedAt': store.bookSourcePublishedAt?.toIso8601String(),
      'sources': all.map((s) => s.toJson()).toList(growable: false),
    });
  }

  /// 管理端：发布（覆盖式或合并式）书源。管理员直接发布，无审核态。
  ///
  /// body: {
  ///   "sources": [ {name,url,group,rawJson,enabled,weight,sort,id?}, ... ],
  ///   "mode": "merge" | "replace",       // 默认 merge
  ///   "announce": true,                   // 默认 true，自动生成一条公告
  ///   "announcementTitle": "...",         // 可选，覆盖默认标题
  ///   "announcementBody": "..."           // 可选
  /// }
  Future<void> adminPublishBookSources(HttpRequest request) async {
    final body = await readJsonObject(request);
    if (body == null) return;
    final rawSources = body['sources'];
    if (rawSources is! List) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': 'sources 必须是数组'},
      });
      return;
    }
    final mode = (body['mode']?.toString() ?? 'merge').toLowerCase();
    if (mode != 'merge' && mode != 'replace') {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': 'mode 只能是 merge 或 replace'},
      });
      return;
    }

    final now = DateTime.now();
    final incoming = <String, CloudBookSource>{};
    var added = 0;
    var updated = 0;
    for (final item in rawSources) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final name = (map['name']?.toString() ?? '').trim();
      final url = (map['url']?.toString() ?? '').trim();
      if (name.isEmpty || url.isEmpty) {
        await jsonResponse(request.response, HttpStatus.badRequest, {
          'error': {'message': '每条书源都必须有 name 和 url'},
        });
        return;
      }
      // 身份：显式 id 优先，否则按 url 归一化去重（同一站点视为同一书源）。
      final explicitId = (map['id']?.toString() ?? '').trim();
      final urlKey = bookSourceUrlKey(url);
      CloudBookSource? existing;
      if (explicitId.isNotEmpty) {
        existing = store.cloudBookSources[explicitId];
      } else {
        for (final s in store.cloudBookSources.values) {
          if (bookSourceUrlKey(s.url) == urlKey) {
            existing = s;
            break;
          }
        }
      }
      final id = existing?.id ??
          (explicitId.isNotEmpty ? explicitId : store.nextBookSourceId());
      var rawJson = (map['rawJson']?.toString() ?? '').trim();
      if (rawJson.isEmpty) {
        // 没给完整规则就用最小可用规则，客户端仍能识别名称与地址。
        rawJson = jsonEncode({'bookSourceName': name, 'bookSourceUrl': url});
      }
      final source = CloudBookSource(
        id: id,
        name: name,
        url: url,
        group: (map['group']?.toString() ?? '').trim(),
        rawJson: rawJson,
        enabled: map['enabled'] != false,
        weight: asInt(map['weight'], existing?.weight ?? 0),
        sort: asInt(map['sort'], existing?.sort ?? 0),
        updatedAt: now,
      );
      if (existing == null || existing.removed) {
        added++;
      } else {
        updated++;
      }
      incoming[id] = source;
    }

    if (incoming.isEmpty) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '没有有效书源'},
      });
      return;
    }

    var removed = 0;
    if (mode == 'replace') {
      // 覆盖式：本次未出现的既有书源转为墓碑，客户端会同步删除。
      for (final entry in store.cloudBookSources.entries.toList()) {
        if (incoming.containsKey(entry.key) || entry.value.removed) continue;
        store.cloudBookSources[entry.key] = CloudBookSource(
          id: entry.value.id,
          name: entry.value.name,
          url: entry.value.url,
          group: entry.value.group,
          rawJson: entry.value.rawJson,
          enabled: false,
          weight: entry.value.weight,
          sort: entry.value.sort,
          updatedAt: now,
          removed: true,
        );
        removed++;
      }
    }
    store.cloudBookSources.addAll(incoming);
    store.bookSourceVersion++;
    store.bookSourcePublishedAt = now;

    Announcement? announcement;
    if (body['announce'] != false) {
      final title = (body['announcementTitle']?.toString() ?? '').trim();
      final text = (body['announcementBody']?.toString() ?? '').trim();
      final parts = <String>[];
      if (added > 0) parts.add('新增 $added 个');
      if (updated > 0) parts.add('更新 $updated 个');
      if (removed > 0) parts.add('下架 $removed 个');
      final summary = parts.isEmpty ? '书源已更新' : '本次${parts.join('、')}书源';
      announcement = Announcement(
        id: store.nextAnnouncementId(),
        title: title.isEmpty ? '书源已更新' : title,
        body: text.isEmpty
            ? '$summary。到「小说 - 书源管理」下拉刷新，或在「我的」页点「检查书源更新」即可同步。'
            : text,
        level: 'notice',
        publishedAt: now,
        updatedAt: now,
      );
      store.announcements[announcement.id] = announcement;
      store.announcementVersion++;
    }

    await store.save();
    await jsonResponse(request.response, HttpStatus.ok, {
      'version': store.bookSourceVersion,
      'publishedAt': now.toIso8601String(),
      'added': added,
      'updated': updated,
      'removed': removed,
      'total': store.cloudBookSources.values.where((s) => !s.removed).length,
      if (announcement != null) 'announcement': announcement.toJson(),
    });
  }

  /// 管理端：删除单个云端书源（写墓碑，不物理删，保证客户端能同步删除）。
  Future<void> adminDeleteBookSource(HttpRequest request, String id) async {
    final existing = store.cloudBookSources[id];
    if (existing == null) {
      await jsonResponse(request.response, HttpStatus.notFound, {
        'error': {'message': '书源不存在'},
      });
      return;
    }
    // 已是墓碑：幂等返回成功，不再推进版本号（避免重复删除刷版本、
    // 触发所有客户端做一次无意义的全量同步）。
    if (existing.removed) {
      await jsonResponse(request.response, HttpStatus.ok, {
        'id': id,
        'removed': true,
        'alreadyRemoved': true,
        'version': store.bookSourceVersion,
        'total': store.cloudBookSources.values.where((s) => !s.removed).length,
      });
      return;
    }
    final now = DateTime.now();
    store.cloudBookSources[id] = CloudBookSource(
      id: existing.id,
      name: existing.name,
      url: existing.url,
      group: existing.group,
      rawJson: existing.rawJson,
      enabled: false,
      weight: existing.weight,
      sort: existing.sort,
      updatedAt: now,
      removed: true,
    );
    store.bookSourceVersion++;
    store.bookSourcePublishedAt = now;
    await store.save();
    await jsonResponse(request.response, HttpStatus.ok, {
      'id': id,
      'removed': true,
      'version': store.bookSourceVersion,
      'total': store.cloudBookSources.values.where((s) => !s.removed).length,
    });
  }

  // ── 公告（新增） ──

  /// 公开只读：客户端拉公告列表。默认只返回已发布的，置顶优先、其余按时间倒序。
  Future<void> publicAnnouncements(HttpRequest request) async {
    final limit = asInt(request.uri.queryParameters['limit'], 50).clamp(1, 200);
    final items = store.announcements.values.where((a) => a.published).toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.publishedAt.compareTo(a.publishedAt);
      });
    final page = items.take(limit).toList(growable: false);
    await jsonResponse(request.response, HttpStatus.ok, {
      'version': store.announcementVersion,
      'total': items.length,
      // count 与书源接口保持同名语义：本次返回的条目数。
      'count': page.length,
      'announcements': page
          .map((a) => a.toClientJson())
          .toList(growable: false),
    });
  }

  /// 管理端：列出全部公告（含未发布草稿）。
  Future<void> adminListAnnouncements(HttpRequest request) async {
    final items = store.announcements.values.toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.publishedAt.compareTo(a.publishedAt);
      });
    await jsonResponse(request.response, HttpStatus.ok, {
      'version': store.announcementVersion,
      'announcements': items.map((a) => a.toJson()).toList(growable: false),
    });
  }

  /// 管理端：新建公告。管理员直接发布（published 默认 true）。
  Future<void> adminCreateAnnouncement(HttpRequest request) async {
    final body = await readJsonObject(request);
    if (body == null) return;
    final title = (body['title']?.toString() ?? '').trim();
    final text = (body['body']?.toString() ?? '').trim();
    if (title.isEmpty) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '标题不能为空'},
      });
      return;
    }
    if (title.length > 80) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '标题不能超过 80 字'},
      });
      return;
    }
    if (text.length > 4000) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '正文不能超过 4000 字'},
      });
      return;
    }
    final now = DateTime.now();
    final announcement = Announcement(
      id: store.nextAnnouncementId(),
      title: title,
      body: text,
      level: normalizeAnnouncementLevel(body['level']?.toString()),
      publishedAt: now,
      updatedAt: now,
      pinned: body['pinned'] == true,
      linkUrl: (body['linkUrl']?.toString() ?? '').trim(),
      published: body['published'] != false,
    );
    store.announcements[announcement.id] = announcement;
    store.announcementVersion++;
    // 公告条数设上限，避免状态文件无界膨胀（保留最近 300 条）。
    if (store.announcements.length > 300) {
      final ordered = store.announcements.values.toList()
        ..sort((a, b) => a.publishedAt.compareTo(b.publishedAt));
      for (final old in ordered.take(store.announcements.length - 300)) {
        store.announcements.remove(old.id);
      }
    }
    await store.save();
    await jsonResponse(request.response, HttpStatus.ok, announcement.toJson());
  }

  /// 管理端：修改公告（标题/正文/级别/置顶/上下架）。
  Future<void> adminUpdateAnnouncement(HttpRequest request, String id) async {
    final existing = store.announcements[id];
    if (existing == null) {
      await jsonResponse(request.response, HttpStatus.notFound, {
        'error': {'message': '公告不存在'},
      });
      return;
    }
    final body = await readJsonObject(request);
    if (body == null) return;
    final nextTitle = body.containsKey('title')
        ? (body['title']?.toString() ?? '').trim()
        : existing.title;
    if (nextTitle.isEmpty) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '标题不能为空'},
      });
      return;
    }
    final updated = existing.copyWith(
      title: nextTitle,
      body: body.containsKey('body')
          ? (body['body']?.toString() ?? '').trim()
          : null,
      level: body.containsKey('level') ? body['level']?.toString() : null,
      pinned: body.containsKey('pinned') ? body['pinned'] == true : null,
      linkUrl: body.containsKey('linkUrl')
          ? (body['linkUrl']?.toString() ?? '').trim()
          : null,
      published:
          body.containsKey('published') ? body['published'] != false : null,
    );
    store.announcements[id] = updated;
    store.announcementVersion++;
    await store.save();
    await jsonResponse(request.response, HttpStatus.ok, updated.toJson());
  }

  /// 管理端：删除公告。
  Future<void> adminDeleteAnnouncement(HttpRequest request, String id) async {
    final removed = store.announcements.remove(id);
    if (removed == null) {
      await jsonResponse(request.response, HttpStatus.notFound, {
        'error': {'message': '公告不存在'},
      });
      return;
    }
    store.announcementVersion++;
    await store.save();
    await jsonResponse(request.response, HttpStatus.ok, {
      'id': id,
      'deleted': true,
      'version': store.announcementVersion,
    });
  }

  Future<Account?> optionalUser(HttpRequest request) async {
    final auth = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    final token = auth.toLowerCase().startsWith('bearer ')
        ? auth.substring(7).trim()
        : auth.trim();
    if (token.isEmpty) return null;
    final session = store.sessions[token];
    if (session == null || !session.expiresAt.isAfter(DateTime.now())) {
      return null;
    }
    return store.accounts[session.userId];
  }

  Future<void> getPluginPolicy(HttpRequest request, Account? account) async {
    await jsonResponse(
      request.response,
      HttpStatus.ok,
      store.pluginPolicy.toClientJson(account?.id),
    );
  }

  Future<void> adminGetPluginPolicy(HttpRequest request) async {
    await jsonResponse(
      request.response,
      HttpStatus.ok,
      store.pluginPolicy.toAdminJson(store.accounts),
    );
  }

  Future<void> adminPutPluginPolicy(HttpRequest request) async {
    final body = await readJsonObject(request);
    if (body == null) return;
    store.pluginPolicy.applyAdminPatch(body);
    await store.save();
    await jsonResponse(
      request.response,
      HttpStatus.ok,
      store.pluginPolicy.toAdminJson(store.accounts),
    );
  }

  Future<void> adminPutUserPlugins(HttpRequest request, String userId) async {
    final account = store.accounts[userId];
    if (account == null) {
      await jsonResponse(request.response, HttpStatus.notFound, {
        'error': {'message': '用户不存在'},
      });
      return;
    }
    final body = await readJsonObject(request);
    if (body == null) return;
    store.pluginPolicy.applyUserPatch(userId, body);
    await store.save();
    await jsonResponse(request.response, HttpStatus.ok, {
      'userId': userId,
      'policy': store.pluginPolicy.userOverrideJson(userId),
      'effective': store.pluginPolicy.toClientJson(userId),
    });
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
      final req =
          await client.postUrl(uri).timeout(const Duration(seconds: 20));
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

  // ───────── Plugin market ─────────

  static const _allowedPluginActions = {
    'toast',
    'navigate',
    'openDailyNews',
    'openNovelList',
    'openVideoList',
    'openImageGenerator',
  };

  static const _allowedPluginAreas = {
    'recommend',
    'music',
    'video',
    'comic',
    'novel',
  };

  static const _allowedPluginPermissions = {
    'network',
    'storage',
    'clipboard',
    'none',
  };

  Future<void> pluginMarketManifest(HttpRequest request) async {
    final qp = request.uri.queryParameters;
    final channel = (qp['channel'] ?? 'stable').trim();
    // A3: 搜索 / 分类 / 排序
    final q = (qp['q'] ?? '').trim().toLowerCase();
    final tag = (qp['tag'] ?? '').trim().toLowerCase();
    final area = (qp['area'] ?? '').trim();
    // sort: recommended(默认) | downloads | updated | title
    final sortBy = (qp['sort'] ?? 'recommended').trim();

    var releases = store.pluginReleases.values
        .where((r) => r.status == 'published')
        .where((r) => channel != 'stable' || !r.beta)
        .toList();

    if (area.isNotEmpty) {
      releases = releases.where((r) => r.areaCode == area).toList();
    }
    if (tag.isNotEmpty) {
      releases = releases
          .where((r) => r.tags.any((t) => t.toLowerCase() == tag))
          .toList();
    }
    if (q.isNotEmpty) {
      releases = releases.where((r) {
        return r.title.toLowerCase().contains(q) ||
            r.subtitle.toLowerCase().contains(q) ||
            r.pluginId.toLowerCase().contains(q) ||
            r.authorName.toLowerCase().contains(q) ||
            r.tags.any((t) => t.toLowerCase().contains(q));
      }).toList();
    }

    final plugins = releases.map((r) => r.toMarketJson()).toList();
    int cmpRecommended(Map<String, dynamic> a, Map<String, dynamic> b) {
      final fa = a['featured'] == true ? 0 : 1;
      final fb = b['featured'] == true ? 0 : 1;
      if (fa != fb) return fa.compareTo(fb);
      final sa = asInt(a['sort'], 9999);
      final sb = asInt(b['sort'], 9999);
      if (sa != sb) return sa.compareTo(sb);
      return (a['title']?.toString() ?? '')
          .compareTo(b['title']?.toString() ?? '');
    }

    switch (sortBy) {
      case 'downloads':
        plugins.sort((a, b) => asInt(b['downloadCount'], 0)
            .compareTo(asInt(a['downloadCount'], 0)));
        break;
      case 'updated':
        plugins.sort((a, b) => (b['publishedAt']?.toString() ?? '')
            .compareTo(a['publishedAt']?.toString() ?? ''));
        break;
      case 'title':
        plugins.sort((a, b) => (a['title']?.toString() ?? '')
            .compareTo(b['title']?.toString() ?? ''));
        break;
      default:
        plugins.sort(cmpRecommended);
    }

    // 聚合可用标签（基于当前 channel 的全部已发布插件，便于前端渲染筛选栏）
    final tagCount = <String, int>{};
    for (final r in store.pluginReleases.values
        .where((r) => r.status == 'published')
        .where((r) => channel != 'stable' || !r.beta)) {
      for (final t in r.tags) {
        final k = t.trim();
        if (k.isEmpty) continue;
        tagCount[k] = (tagCount[k] ?? 0) + 1;
      }
    }
    final tags = tagCount.entries
        .map((e) => {'tag': e.key, 'count': e.value})
        .toList()
      ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

    await jsonResponse(request.response, HttpStatus.ok, {
      'version': store.pluginMarketVersion,
      'channel': channel.isEmpty ? 'stable' : channel,
      'updatedAt': DateTime.now().toIso8601String(),
      'plugins': plugins,
      'count': plugins.length,
      'sort': sortBy,
      if (q.isNotEmpty) 'q': q,
      if (tag.isNotEmpty) 'tag': tag,
      if (area.isNotEmpty) 'area': area,
      'availableTags': tags,
    });
  }

  Future<void> pluginMarketDetail(HttpRequest request, String pluginId) async {
    final release = store.pluginReleases[pluginId];
    if (release == null || release.status != 'published') {
      await jsonResponse(request.response, HttpStatus.notFound, {
        'error': {'message': '插件不存在或未发布'},
      });
      return;
    }
    await jsonResponse(request.response, HttpStatus.ok, release.toMarketJson());
  }

  Future<void> submitPlugin(HttpRequest request, Account account) async {
    if (isAuthorBanned(account.id)) {
      final reason = store.pluginBannedAuthors[account.id] ?? '管理员禁止投稿';
      await jsonResponse(request.response, HttpStatus.forbidden, {
        'error': {'message': '账号已被禁止投稿：$reason'},
      });
      return;
    }
    final body = await readJsonObject(request);
    if (body == null) return;

    final title = (body['title']?.toString() ?? '').trim();
    final subtitle = (body['subtitle']?.toString() ?? '').trim();
    final actionCode = (body['actionCode']?.toString() ??
            body['action']?.toString() ??
            'toast')
        .trim();
    final areaCodeRaw = (body['areaCode']?.toString() ??
            body['area']?.toString() ??
            'recommend')
        .trim();
    final areaCode =
        _allowedPluginAreas.contains(areaCodeRaw) ? areaCodeRaw : 'recommend';
    final version = (body['version']?.toString() ?? '1.0.0').trim();
    final minAppVersion = (body['minAppVersion']?.toString() ?? '').trim();
    final changelog = (body['changelog']?.toString() ?? '').trim();
    final payloadRaw = body['payload'];
    final Map<String, dynamic> payloadData;
    final String payloadText;
    if (payloadRaw is Map) {
      payloadData = Map<String, dynamic>.from(payloadRaw);
      payloadText = '';
    } else {
      payloadData = const {};
      payloadText = (payloadRaw?.toString() ?? '').trim();
    }

    if (title.isEmpty) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '标题不能为空'},
      });
      return;
    }
    if (!_allowedPluginActions.contains(actionCode)) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {
          'message': 'actionCode 不在白名单：$actionCode',
          'allowed': _allowedPluginActions.toList(),
        },
      });
      return;
    }

    final permissions = <String>[];
    final rawPerms = body['permissions'];
    if (rawPerms is List) {
      for (final p in rawPerms) {
        final code = p.toString().trim();
        if (_allowedPluginPermissions.contains(code)) permissions.add(code);
      }
    }
    final tags = <String>[];
    final rawTags = body['tags'];
    if (rawTags is List) {
      for (final t in rawTags) {
        final s = t.toString().trim();
        if (s.isNotEmpty) tags.add(s);
      }
    }

    // plugin id: user supplied slug or auto
    var slug =
        (body['slug']?.toString() ?? body['id']?.toString() ?? '').trim();
    slug = slug
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_\-\.]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (slug.startsWith('builtin_') || slug.startsWith('market_')) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '禁止使用系统保留 id 前缀'},
      });
      return;
    }
    if (slug.isEmpty) {
      slug = 'p_${randomBase64(6).toLowerCase()}';
    }
    final pluginId =
        slug.startsWith('user.') ? slug : 'user.${account.id}.$slug';

    // 作者禁投稿（拒绝过多）
    final rejects = store.pluginSubmissions.values
        .where((s) => s.authorUserId == account.id && s.status == 'rejected')
        .length;
    if (rejects >= 8) {
      await jsonResponse(request.response, HttpStatus.forbidden, {
        'error': {'message': '拒绝次数过多，已禁止投稿，请联系管理员'},
      });
      return;
    }

    // 每日投稿上限 5
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final todayCount = store.pluginSubmissions.values
        .where((s) =>
            s.authorUserId == account.id && !s.createdAt.isBefore(dayStart))
        .length;
    if (todayCount >= 5) {
      await jsonResponse(request.response, HttpStatus.tooManyRequests, {
        'error': {'message': '今日投稿已达上限（5），请明天再试'},
      });
      return;
    }

    // rate limit: max 20 pending per user
    final minePending = store.pluginSubmissions.values
        .where(
            (s) => s.authorUserId == account.id && s.status == 'pending_review')
        .length;
    if (minePending >= 20) {
      await jsonResponse(request.response, HttpStatus.tooManyRequests, {
        'error': {'message': '待审投稿过多，请等待审核后再提交'},
      });
      return;
    }

    final id = store.nextPluginSubmissionId();
    final submission = PluginSubmission(
      id: id,
      pluginId: pluginId,
      authorUserId: account.id,
      authorName: account.username,
      title: title,
      subtitle: subtitle,
      version: version.isEmpty ? '1.0.0' : version,
      minAppVersion: minAppVersion,
      areaCode: areaCode,
      actionCode: actionCode,
      payload: payloadText,
      payloadData: payloadData,
      permissions: permissions,
      tags: tags,
      changelog: changelog,
      status: 'pending_review',
      reviewNote: '',
      reviewerId: '',
      createdAt: DateTime.now(),
      reviewedAt: null,
      colorValue: asInt(body['colorValue'], 0xFF4F46E5),
      iconName: (body['iconName']?.toString() ?? body['icon']?.toString() ?? '')
          .trim(),
      sort: asInt(body['sort'], 5000),
      beta: body['beta'] == true,
    );
    store.pluginSubmissions[id] = submission;
    store.addPluginAudit(
      PluginAuditEvent(
        id: 'pa_${randomBase64(8)}',
        action: 'submit',
        actorUserId: account.id,
        actorName: account.username,
        pluginId: pluginId,
        submissionId: id,
        note: title,
        createdAt: DateTime.now(),
      ),
    );
    await store.save();
    await jsonResponse(request.response, HttpStatus.created, {
      ...submission.toJson(),
      'quota': {
        'todayUsed': todayCount + 1,
        'todayLimit': 5,
        'pending': minePending + 1,
        'rejects': rejects,
      },
    });
  }

  static const int _maxPluginZipBytes = 5 * 1024 * 1024;
  static const int _maxPluginIconBytes = 256 * 1024;
  static final _bannedZipExt = RegExp(
    r'\.(so|dex|apk|jar|class|exe|dll|js|mjs|cjs|wasm|sh|bat|cmd|ps1|php|py|rb|pl)$',
    caseSensitive: false,
  );
  // P2.6: 资源白名单（目录与无扩展名入口除外）
  static final _allowedZipExt = RegExp(
    r'\.(json|txt|png|md|jpg|jpeg|webp)$',
    caseSensitive: false,
  );

  Directory get _pluginPackagesDir {
    final stateFile = File(store.path);
    final parent = stateFile.parent;
    final dir = Directory('${parent.path}/plugin_packages');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Future<Directory?> ensurePluginPackagesDir() async {
    try {
      final dir = _pluginPackagesDir;
      // write probe
      final probe = File('${dir.path}/.write_probe');
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return dir;
    } catch (e) {
      stderr.writeln('plugin_packages dir not writable: $e');
      return null;
    }
  }

  int _pluginPackagesTotalBytes() {
    try {
      final dir = _pluginPackagesDir;
      var total = 0;
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is File) {
          total += entity.lengthSync();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  bool isAuthorBanned(String userId) {
    return store.pluginBannedAuthors.containsKey(userId);
  }

  Future<void> submitPluginZip(HttpRequest request, Account account) async {
    if (isAuthorBanned(account.id)) {
      final reason = store.pluginBannedAuthors[account.id] ?? '管理员禁止投稿';
      store.bumpPluginCounter('submit_banned');
      await jsonResponse(request.response, HttpStatus.forbidden, {
        'error': {
          'message': '账号已被禁止投稿：$reason',
          'code': 'author_banned',
        },
      });
      return;
    }
    // 配额检查（与 JSON 投稿一致）
    final rejects = store.pluginSubmissions.values
        .where((s) => s.authorUserId == account.id && s.status == 'rejected')
        .length;
    if (rejects >= 8) {
      store.bumpPluginCounter('submit_reject_limit');
      await jsonResponse(request.response, HttpStatus.forbidden, {
        'error': {
          'message': '拒绝次数过多，已禁止投稿，请联系管理员',
          'code': 'reject_limit',
        },
      });
      return;
    }
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final todayCount = store.pluginSubmissions.values
        .where((s) =>
            s.authorUserId == account.id && !s.createdAt.isBefore(dayStart))
        .length;
    if (todayCount >= 5) {
      store.bumpPluginCounter('submit_daily_limit');
      await jsonResponse(request.response, HttpStatus.tooManyRequests, {
        'error': {
          'message': '今日投稿已达上限（5），请明天再试',
          'code': 'daily_limit',
          'quota': {'todayUsed': todayCount, 'todayLimit': 5},
        },
      });
      return;
    }
    final minePending = store.pluginSubmissions.values
        .where(
            (s) => s.authorUserId == account.id && s.status == 'pending_review')
        .length;
    if (minePending >= 20) {
      store.bumpPluginCounter('submit_pending_limit');
      await jsonResponse(request.response, HttpStatus.tooManyRequests, {
        'error': {
          'message': '待审投稿过多，请等待审核后再提交',
          'code': 'pending_limit',
          'quota': {'pendingUsed': minePending, 'pendingLimit': 20},
        },
      });
      return;
    }

    final contentType = request.headers.contentType;
    Map<String, String> fields = {};
    List<int>? zipBytes;

    if (contentType != null &&
        contentType.mimeType.toLowerCase() == 'multipart/form-data') {
      final parsed = await parseMultipartForm(request);
      if (parsed == null) {
        await jsonResponse(request.response, HttpStatus.badRequest, {
          'error': {'message': '无法解析 multipart 表单'},
        });
        return;
      }
      fields = parsed.fields;
      zipBytes = parsed.files['package'] ??
          parsed.files['file'] ??
          parsed.files['zip'];
    } else {
      final body = await readJsonObject(request);
      if (body == null) return;
      fields = body.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
      final b64 =
          (body['packageBase64'] ?? body['zipBase64'] ?? '').toString().trim();
      if (b64.isNotEmpty) {
        try {
          zipBytes =
              base64Decode(b64.contains(',') ? b64.split(',').last : b64);
        } catch (_) {
          await jsonResponse(request.response, HttpStatus.badRequest, {
            'error': {'message': 'packageBase64 解码失败'},
          });
          return;
        }
      }
    }

    if (zipBytes == null || zipBytes.isEmpty) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '请上传 zip 包（字段 package/file 或 packageBase64）'},
      });
      return;
    }
    if (zipBytes.length > _maxPluginZipBytes) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': 'zip 包过大，上限 5MB'},
      });
      return;
    }

    final validated = await validateAndExtractPluginZip(zipBytes);
    if (validated.error != null) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': validated.error},
      });
      return;
    }
    final meta = validated.meta!;
    // form fields override optional metadata
    final title = (fields['title'] ?? meta['title']?.toString() ?? '').trim();
    final subtitle =
        (fields['subtitle'] ?? meta['subtitle']?.toString() ?? '').trim();
    final actionCode =
        (fields['actionCode'] ?? meta['actionCode']?.toString() ?? 'toast')
            .trim();
    final areaCodeRaw =
        (fields['areaCode'] ?? meta['areaCode']?.toString() ?? 'recommend')
            .trim();
    final areaCode =
        _allowedPluginAreas.contains(areaCodeRaw) ? areaCodeRaw : 'recommend';
    final version =
        (fields['version'] ?? meta['version']?.toString() ?? '1.0.0').trim();
    final minAppVersion =
        (fields['minAppVersion'] ?? meta['minAppVersion']?.toString() ?? '')
            .trim();
    final changelog =
        (fields['changelog'] ?? meta['changelog']?.toString() ?? '').trim();

    if (title.isEmpty) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '标题不能为空（plugin.json 或表单 title）'},
      });
      return;
    }
    if (!_allowedPluginActions.contains(actionCode)) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {
          'message': 'actionCode 不在白名单：$actionCode',
          'allowed': _allowedPluginActions.toList(),
        },
      });
      return;
    }

    var slug =
        (fields['slug'] ?? fields['id'] ?? meta['id']?.toString() ?? '').trim();
    slug = slug
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_\-\.]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (slug.startsWith('builtin_') || slug.startsWith('market_')) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '禁止使用系统保留 id 前缀'},
      });
      return;
    }
    if (slug.startsWith('user.')) {
      // ok
    } else if (slug.isEmpty) {
      slug = 'p_${randomBase64(6).toLowerCase()}';
    }
    final pluginId =
        slug.startsWith('user.') ? slug : 'user.${account.id}.$slug';

    final permissions = <String>[];
    final rawPerms = meta['permissions'];
    if (rawPerms is List) {
      for (final p in rawPerms) {
        final code = p.toString().trim();
        if (_allowedPluginPermissions.contains(code)) permissions.add(code);
      }
    }
    if (fields['permissions'] != null && fields['permissions']!.isNotEmpty) {
      for (final p in fields['permissions']!.split(RegExp(r'[,，\s]+'))) {
        final code = p.trim();
        if (_allowedPluginPermissions.contains(code)) permissions.add(code);
      }
    }
    final tags = <String>['用户投稿', 'zip'];
    final rawTags = meta['tags'];
    if (rawTags is List) {
      for (final t in rawTags) {
        final s = t.toString().trim();
        if (s.isNotEmpty) tags.add(s);
      }
    }
    if (fields['tags'] != null && fields['tags']!.isNotEmpty) {
      for (final t in fields['tags']!.split(RegExp(r'[,，\s]+'))) {
        final s = t.trim();
        if (s.isNotEmpty) tags.add(s);
      }
    }

    Map<String, dynamic> payloadData = const {};
    String payloadText = '';
    final payloadRaw = meta['payload'] ?? validated.payloadFromFile;
    if (payloadRaw is Map) {
      payloadData = Map<String, dynamic>.from(payloadRaw);
    } else if (payloadRaw != null) {
      payloadText = payloadRaw.toString();
    }
    if (fields['payload'] != null && fields['payload']!.trim().isNotEmpty) {
      payloadText = fields['payload']!.trim();
      payloadData = const {};
    }

    final zipSha = sha256.convert(zipBytes).toString();
    final id = store.nextPluginSubmissionId();
    final relPath =
        '${pluginId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}/$id.zip';
    final packagesDir = await ensurePluginPackagesDir();
    if (packagesDir == null) {
      store.bumpPluginCounter('storage_unwritable');
      stderr.writeln('[plugin-market] storage unwritable user=${account.id}');
      await jsonResponse(request.response, HttpStatus.serviceUnavailable, {
        'error': {
          'message': '服务器插件包存储不可写，请联系管理员',
          'code': 'storage_unwritable',
        },
      });
      return;
    }
    // 全局包体积上限 2GB
    final used = _pluginPackagesTotalBytes();
    if (used + zipBytes.length > 2 * 1024 * 1024 * 1024) {
      store.bumpPluginCounter('storage_full');
      await jsonResponse(request.response, HttpStatus.insufficientStorage, {
        'error': {
          'message': '服务器插件包存储空间不足',
          'code': 'storage_full',
          'storage': pluginStorageSnapshot(),
        },
      });
      return;
    }
    // 单用户累计 50MB
    final userUsed = store.pluginSubmissions.values
        .where((s) => s.authorUserId == account.id)
        .fold<int>(0, (sum, s) => sum + s.packageSize);
    if (userUsed + zipBytes.length > 50 * 1024 * 1024) {
      store.bumpPluginCounter('user_storage_limit');
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {
          'message': '你的插件包累计已超过 50MB 上限',
          'code': 'user_storage_limit',
          'quota': {
            'userBytesUsed': userUsed,
            'userBytesLimit': 50 * 1024 * 1024,
          },
        },
      });
      return;
    }
    final outFile = File('${packagesDir.path}/$relPath');
    try {
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(zipBytes, flush: true);
    } catch (e) {
      store.bumpPluginCounter('storage_write_fail');
      stderr.writeln('[plugin-market] zip write fail: $e');
      await jsonResponse(request.response, HttpStatus.internalServerError, {
        'error': {
          'message': '保存 zip 失败，请稍后重试',
          'code': 'storage_write_fail',
        },
      });
      return;
    }

    // packageJson snapshot for install validation (from plugin.json)
    final packageMap = <String, dynamic>{
      'schema': 1,
      'id': pluginId,
      'title': title,
      'subtitle': subtitle,
      'version': version.isEmpty ? '1.0.0' : version,
      'minAppVersion': minAppVersion,
      'areaCode': areaCode,
      'actionCode': actionCode,
      'payload': payloadData.isEmpty ? payloadText : payloadData,
      'permissions': permissions,
      'tags': tags,
      'changelog': changelog,
      'author': account.username,
      'authorUserId': account.id,
      'packageFormat': 'zip',
      'packageSha256': zipSha,
    };
    final packageJson = jsonEncode(packageMap);

    final submission = PluginSubmission(
      id: id,
      pluginId: pluginId,
      authorUserId: account.id,
      authorName: account.username,
      title: title,
      subtitle: subtitle,
      version: version.isEmpty ? '1.0.0' : version,
      minAppVersion: minAppVersion,
      areaCode: areaCode,
      actionCode: actionCode,
      payload: payloadText,
      payloadData: payloadData,
      permissions: permissions,
      tags: tags,
      changelog: changelog,
      status: 'pending_review',
      reviewNote: '',
      reviewerId: '',
      createdAt: DateTime.now(),
      reviewedAt: null,
      colorValue:
          asInt(fields['colorValue'], asInt(meta['colorValue'], 0xFF4F46E5)),
      iconName:
          (fields['iconName'] ?? meta['iconName']?.toString() ?? '').trim(),
      sort: asInt(fields['sort'], asInt(meta['sort'], 5000)),
      beta: fields['beta'] == 'true' || meta['beta'] == true,
      packagePath: relPath,
      packageSha256: zipSha,
      packageSize: zipBytes.length,
      packageFormat: 'zip',
      packageJson: packageJson,
    );
    store.pluginSubmissions[id] = submission;
    store.bumpPluginCounter('submit_zip_ok');
    stderr.writeln(
      '[plugin-market] submit_zip ok id=$pluginId sub=$id user=${account.id} size=${zipBytes.length}',
    );
    store.addPluginAudit(
      PluginAuditEvent(
        id: 'pa_${randomBase64(8)}',
        action: 'submit_zip',
        actorUserId: account.id,
        actorName: account.username,
        pluginId: pluginId,
        submissionId: id,
        note: '${title} (${zipBytes.length}B)',
        createdAt: DateTime.now(),
      ),
    );
    await store.save();
    await jsonResponse(request.response, HttpStatus.created, {
      ...submission.toJson(),
      'quota': {
        'todayUsed': todayCount + 1,
        'todayLimit': 5,
        'pending': minePending + 1,
        'rejects': rejects,
      },
    });
  }

  Future<void> pluginMarketPackage(
    HttpRequest request,
    String pluginId,
  ) async {
    final release = store.pluginReleases[pluginId];
    if (release == null || release.status != 'published') {
      store.bumpPluginCounter('package_miss');
      await jsonResponse(request.response, HttpStatus.notFound, {
        'error': {
          'message': '插件不存在或未发布',
          'code': 'package_not_found',
        },
      });
      return;
    }
    if (release.packagePath.isEmpty) {
      // fallback: return packageJson as application/json attachment
      if (release.packageJson.isEmpty) {
        store.bumpPluginCounter('package_miss');
        await jsonResponse(request.response, HttpStatus.notFound, {
          'error': {
            'message': '该插件无包文件',
            'code': 'package_empty',
          },
        });
        return;
      }
      final bytes = utf8.encode(release.packageJson);
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      );
      request.response.headers.set('X-Package-Sha256', release.packageSha256);
      request.response.headers.set('X-Package-Format', 'json');
      request.response.add(bytes);
      await request.response.close();
      return;
    }
    final file = File('${_pluginPackagesDir.path}/${release.packagePath}');
    if (!file.existsSync()) {
      store.bumpPluginCounter('package_file_missing');
      stderr.writeln(
          '[plugin-market] package file missing id=$pluginId path=${release.packagePath}');
      await jsonResponse(request.response, HttpStatus.notFound, {
        'error': {
          'message': '包文件丢失，请联系管理员重新发布',
          'code': 'package_file_missing',
        },
      });
      return;
    }
    final bytes = await file.readAsBytes();
    final actualSha = sha256.convert(bytes).toString();
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType('application', 'zip');
    request.response.headers.set(
      'Content-Disposition',
      'attachment; filename="${pluginId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}.zip"',
    );
    request.response.headers.set('X-Package-Sha256',
        release.packageSha256.isEmpty ? actualSha : release.packageSha256);
    request.response.headers.set('X-Package-Format', 'zip');
    request.response.headers.contentLength = bytes.length;
    request.response.add(bytes);
    await request.response.close();
  }

  Future<({String? error, Map<String, dynamic>? meta, dynamic payloadFromFile})>
      validateAndExtractPluginZip(List<int> zipBytes) async {
    final tmpRoot = await Directory.systemTemp.createTemp('box_plugin_zip_');
    try {
      final zipFile = File('${tmpRoot.path}/pkg.zip');
      await zipFile.writeAsBytes(zipBytes, flush: true);
      // list entries first
      final list = await Process.run('unzip', ['-Z1', zipFile.path]);
      if (list.exitCode != 0) {
        return (
          error: '不是有效的 zip 文件',
          meta: null,
          payloadFromFile: null,
        );
      }
      final names = (list.stdout?.toString() ?? '')
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (names.isEmpty) {
        return (error: 'zip 为空', meta: null, payloadFromFile: null);
      }
      for (final name in names) {
        if (name.contains('..') || name.startsWith('/')) {
          return (error: 'zip 含非法路径：$name', meta: null, payloadFromFile: null);
        }
        if (_bannedZipExt.hasMatch(name)) {
          return (
            error: '禁止的文件类型：$name',
            meta: null,
            payloadFromFile: null,
          );
        }
        // 目录（以 / 结尾）放行；有扩展名则必须白名单
        if (!name.endsWith('/')) {
          final base = name.split('/').last;
          if (base.contains('.') && !_allowedZipExt.hasMatch(base)) {
            return (
              error: '非白名单资源：$name（仅允许 json/txt/png/md/jpg/webp）',
              meta: null,
              payloadFromFile: null,
            );
          }
        }
      }
      // allow nested one-level folder plugin.json
      final pluginJsonName = names.firstWhere(
        (n) =>
            n == 'plugin.json' || RegExp(r'^[^/]+/plugin\.json$').hasMatch(n),
        orElse: () => '',
      );
      if (pluginJsonName.isEmpty) {
        return (
          error: 'zip 内必须包含 plugin.json',
          meta: null,
          payloadFromFile: null,
        );
      }
      final extract = await Process.run(
        'unzip',
        ['-o', '-q', zipFile.path, '-d', tmpRoot.path],
      );
      if (extract.exitCode != 0) {
        return (error: '解压失败', meta: null, payloadFromFile: null);
      }
      final pluginFile = File('${tmpRoot.path}/$pluginJsonName');
      if (!pluginFile.existsSync()) {
        return (error: '找不到 plugin.json', meta: null, payloadFromFile: null);
      }
      Map<String, dynamic> meta;
      try {
        final decoded = jsonDecode(await pluginFile.readAsString());
        if (decoded is! Map) {
          return (
            error: 'plugin.json 必须是对象',
            meta: null,
            payloadFromFile: null
          );
        }
        meta = Map<String, dynamic>.from(decoded);
      } catch (e) {
        return (
          error: 'plugin.json 解析失败：$e',
          meta: null,
          payloadFromFile: null
        );
      }
      dynamic payloadFromFile;
      final baseDir = pluginFile.parent.path;
      final payloadFile = File('$baseDir/payload.json');
      if (payloadFile.existsSync()) {
        try {
          final p = jsonDecode(await payloadFile.readAsString());
          payloadFromFile = p;
        } catch (_) {}
      }
      // icon.png：可选，≤256KB；根或与 plugin.json 同级
      final iconCandidates = <String>[
        'icon.png',
        if (pluginJsonName.contains('/'))
          '${pluginJsonName.split('/').first}/icon.png',
      ];
      for (final rel in iconCandidates) {
        final iconFile = File('${tmpRoot.path}/$rel');
        if (!iconFile.existsSync()) continue;
        final len = await iconFile.length();
        if (len > _maxPluginIconBytes) {
          return (
            error: 'icon.png 过大（上限 256KB）',
            meta: null,
            payloadFromFile: null,
          );
        }
        if (len == 0) {
          return (
            error: 'icon.png 为空',
            meta: null,
            payloadFromFile: null,
          );
        }
        meta['iconName'] = 'icon.png';
        meta['iconSize'] = len;
        meta['hasIcon'] = true;
        break;
      }
      return (error: null, meta: meta, payloadFromFile: payloadFromFile);
    } finally {
      try {
        await tmpRoot.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<MultipartForm?> parseMultipartForm(HttpRequest request) async {
    final contentType = request.headers.contentType;
    if (contentType == null) return null;
    final boundary = contentType.parameters['boundary'];
    if (boundary == null || boundary.isEmpty) return null;
    final body = await request.fold<List<int>>(
      <int>[],
      (prev, chunk) {
        prev.addAll(chunk);
        return prev;
      },
    );
    final separator = utf8.encode('--$boundary');
    final fields = <String, String>{};
    final files = <String, List<int>>{};

    int index = 0;
    // skip preamble
    while (true) {
      final start = _indexOfBytes(body, separator, index);
      if (start < 0) break;
      index = start + separator.length;
      if (index < body.length &&
          body[index] == 45 &&
          index + 1 < body.length &&
          body[index + 1] == 45) {
        break; // --
      }
      // skip CRLF
      if (index + 1 < body.length &&
          body[index] == 13 &&
          body[index + 1] == 10) {
        index += 2;
      } else if (index < body.length && body[index] == 10) {
        index += 1;
      }
      final next = _indexOfBytes(body, separator, index);
      final end = next < 0 ? body.length : next;
      // part is body[index:end] possibly ending with CRLF
      var partEnd = end;
      if (partEnd >= 2 && body[partEnd - 2] == 13 && body[partEnd - 1] == 10) {
        partEnd -= 2;
      } else if (partEnd >= 1 && body[partEnd - 1] == 10) {
        partEnd -= 1;
      }
      final part = body.sublist(index, partEnd);
      final headerSep = _indexOfBytes(part, [13, 10, 13, 10], 0);
      final headerSep2 =
          headerSep < 0 ? _indexOfBytes(part, [10, 10], 0) : headerSep;
      if (headerSep2 < 0) {
        index = end;
        continue;
      }
      final headerBytes = part.sublist(0, headerSep2);
      final contentStart = headerSep >= 0 ? headerSep2 + 4 : headerSep2 + 2;
      final content = part.sublist(contentStart);
      final headers = utf8.decode(headerBytes, allowMalformed: true);
      final nameMatch = RegExp(r'name="([^"]+)"').firstMatch(headers);
      if (nameMatch == null) {
        index = end;
        continue;
      }
      final name = nameMatch.group(1)!;
      final isFile = headers.toLowerCase().contains('filename=');
      if (isFile) {
        files[name] = content;
      } else {
        fields[name] = utf8.decode(content, allowMalformed: true).trim();
      }
      index = end;
    }
    return MultipartForm(fields: fields, files: files);
  }

  int _indexOfBytes(List<int> data, List<int> pattern, int start) {
    if (pattern.isEmpty) return start;
    outer:
    for (var i = start; i <= data.length - pattern.length; i++) {
      for (var j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  Future<void> listMyPlugins(HttpRequest request, Account account) async {
    final list = store.pluginSubmissions.values
        .where((s) => s.authorUserId == account.id)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await jsonResponse(request.response, HttpStatus.ok, {
      'items': list.map((e) => e.toJson()).toList(),
      'count': list.length,
    });
  }

  Future<void> adminListPluginSubmissions(HttpRequest request) async {
    final status = (request.uri.queryParameters['status'] ?? '').trim();
    var list = store.pluginSubmissions.values.toList();
    if (status.isNotEmpty) {
      list = list.where((s) => s.status == status).toList();
    }
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final published = store.pluginReleases.values
        .where((r) => r.status == 'published')
        .map((r) => r.toAdminJson())
        .toList();
    final rejectsToday = store.pluginSubmissions.values.where((s) {
      if (s.status != 'rejected' || s.reviewedAt == null) return false;
      final t = s.reviewedAt!;
      final n = DateTime.now();
      return t.year == n.year && t.month == n.month && t.day == n.day;
    }).length;
    await jsonResponse(request.response, HttpStatus.ok, {
      'items': list.map((e) => e.toJson()).toList(),
      'count': list.length,
      'published': published,
      'publishedCount': published.length,
      'pendingCount': store.pluginSubmissions.values
          .where((s) => s.status == 'pending_review')
          .length,
      'rejectsToday': rejectsToday,
      'audit': store.pluginAudit.take(30).map((e) => e.toJson()).toList(),
      'openReports':
          store.pluginReports.where((r) => r.status == 'open').length,
      'bannedAuthors': store.pluginBannedAuthors,
      'storage': pluginStorageSnapshot(),
      'counters': store.pluginCounters,
    });
  }

  Future<void> adminPluginStats(HttpRequest request) async {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final todaySubmits = store.pluginSubmissions.values
        .where((s) => !s.createdAt.isBefore(dayStart))
        .length;
    final todayZip = store.pluginSubmissions.values
        .where((s) =>
            !s.createdAt.isBefore(dayStart) &&
            (s.packageFormat == 'zip' || s.packagePath.isNotEmpty))
        .length;
    final pending = store.pluginSubmissions.values
        .where((s) => s.status == 'pending_review')
        .length;
    final published = store.pluginReleases.values
        .where((r) => r.status == 'published')
        .length;
    final yanked =
        store.pluginReleases.values.where((r) => r.status == 'yanked').length;
    await jsonResponse(request.response, HttpStatus.ok, {
      'storage': pluginStorageSnapshot(),
      'counters': store.pluginCounters,
      'today': {
        'submissions': todaySubmits,
        'zipSubmissions': todayZip,
        'rejects': store.pluginSubmissions.values.where((s) {
          if (s.status != 'rejected' || s.reviewedAt == null) return false;
          final t = s.reviewedAt!;
          return t.year == now.year && t.month == now.month && t.day == now.day;
        }).length,
      },
      'totals': {
        'submissions': store.pluginSubmissions.length,
        'pending': pending,
        'published': published,
        'yanked': yanked,
        'reportsOpen':
            store.pluginReports.where((r) => r.status == 'open').length,
        'bannedAuthors': store.pluginBannedAuthors.length,
        'auditEvents': store.pluginAudit.length,
      },
      'packagesDirWritable': await ensurePluginPackagesDir() != null,
      'recentAudit': store.pluginAudit.take(20).map((e) => e.toJson()).toList(),
    });
  }

  Map<String, dynamic> pluginStorageSnapshot() {
    final used = _pluginPackagesTotalBytes();
    var files = 0;
    var path = '';
    try {
      final dir = _pluginPackagesDir;
      path = dir.path;
      for (final e in dir.listSync(recursive: true, followLinks: false)) {
        if (e is File) files++;
      }
    } catch (_) {}
    return {
      'path': path,
      'bytesUsed': used,
      'fileCount': files,
      'limitBytes': 2 * 1024 * 1024 * 1024,
      'userLimitBytes': 50 * 1024 * 1024,
    };
  }

  Future<void> adminReviewPluginSubmission(
    HttpRequest request,
    String submissionId,
    String action,
  ) async {
    final sub = store.pluginSubmissions[submissionId];
    if (sub == null) {
      await jsonResponse(request.response, HttpStatus.notFound, {
        'error': {'message': '投稿不存在'},
      });
      return;
    }
    if (sub.status != 'pending_review') {
      await jsonResponse(request.response, HttpStatus.conflict, {
        'error': {'message': '当前状态不可审核：${sub.status}'},
      });
      return;
    }
    final body = await readJsonObject(request) ?? <String, dynamic>{};
    final note =
        (body['note']?.toString() ?? body['reviewNote']?.toString() ?? '')
            .trim();
    final admin = await optionalUser(request);
    final result = _applyReviewDecision(
      sub: sub,
      action: action,
      note: note,
      featured: body['featured'] == true,
      admin: admin,
    );
    await store.save();
    await jsonResponse(request.response, HttpStatus.ok, result);
  }

  /// 审核决策核心：修改状态/发布 release/写审计，不写 HTTP 响应，供单条与批量共用。
  /// 调用方负责 `store.save()`。返回结果 map。
  Map<String, dynamic> _applyReviewDecision({
    required PluginSubmission sub,
    required String action,
    required String note,
    required bool featured,
    Account? admin,
  }) {
    final submissionId = sub.id;
    if (action == 'reject') {
      store.pluginSubmissions[submissionId] = sub.copyWith(
        status: 'rejected',
        reviewNote: note.isEmpty ? '未通过审核' : note,
        reviewerId: admin?.id ?? '',
        reviewedAt: DateTime.now(),
      );
      store.addPluginAudit(
        PluginAuditEvent(
          id: 'pa_${randomBase64(8)}',
          action: 'reject',
          actorUserId: admin?.id ?? '',
          actorName: admin?.username ?? 'admin',
          pluginId: sub.pluginId,
          submissionId: submissionId,
          note: note.isEmpty ? '未通过审核' : note,
          createdAt: DateTime.now(),
        ),
      );
      return store.pluginSubmissions[submissionId]!.toJson();
    }

    // approve → publish release（覆盖同 id，保留旧版本号历史）
    final oldRelease = store.pluginReleases[sub.pluginId];
    final packageMap = <String, dynamic>{
      'schema': 1,
      'id': sub.pluginId,
      'title': sub.title,
      'subtitle': sub.subtitle,
      'version': sub.version,
      'minAppVersion': sub.minAppVersion,
      'areaCode': sub.areaCode,
      'actionCode': sub.actionCode,
      'payload': sub.payloadData.isEmpty ? sub.payload : sub.payloadData,
      'permissions': sub.permissions,
      'tags': sub.tags,
      'changelog': sub.changelog,
      'author': sub.authorName,
      'authorUserId': sub.authorUserId,
      if (sub.packageFormat.isNotEmpty) 'packageFormat': sub.packageFormat,
      if (sub.packageSha256.isNotEmpty) 'packageSha256': sub.packageSha256,
    };
    final packageJson =
        sub.packageJson.isNotEmpty ? sub.packageJson : jsonEncode(packageMap);
    final packageSha256 = sub.packageSha256.isNotEmpty
        ? sub.packageSha256
        : sha256.convert(utf8.encode(packageJson)).toString();
    final previousVersions = <String>[
      ...?oldRelease?.previousVersions,
      if (oldRelease != null &&
          oldRelease.version.isNotEmpty &&
          oldRelease.version != sub.version)
        oldRelease.version,
    ];
    final release = PluginRelease(
      pluginId: sub.pluginId,
      version: sub.version,
      title: sub.title,
      subtitle: sub.subtitle,
      authorUserId: sub.authorUserId,
      authorName: sub.authorName,
      areaCode: sub.areaCode,
      actionCode: sub.actionCode,
      payload: sub.payload,
      payloadData: sub.payloadData,
      permissions: sub.permissions,
      tags: sub.tags,
      changelog: sub.changelog,
      minAppVersion: sub.minAppVersion,
      status: 'published',
      featured: featured,
      beta: sub.beta,
      sort: sub.sort,
      colorValue: sub.colorValue,
      iconName: sub.iconName,
      downloadCount: oldRelease?.downloadCount ?? 0,
      publishedAt: DateTime.now(),
      submissionId: sub.id,
      packageJson: packageJson,
      packageSha256: packageSha256,
      previousVersions: previousVersions,
      packagePath: sub.packagePath,
      packageFormat: sub.packageFormat.isEmpty
          ? (sub.packagePath.isNotEmpty ? 'zip' : 'json')
          : sub.packageFormat,
      packageSize: sub.packageSize,
    );
    store.pluginReleases[sub.pluginId] = release;
    store.pluginMarketVersion += 1;
    store.pluginSubmissions[submissionId] = sub.copyWith(
      status: 'published',
      reviewNote: note,
      reviewerId: admin?.id ?? '',
      reviewedAt: DateTime.now(),
    );
    store.addPluginAudit(
      PluginAuditEvent(
        id: 'pa_${randomBase64(8)}',
        action: 'approve',
        actorUserId: admin?.id ?? '',
        actorName: admin?.username ?? 'admin',
        pluginId: sub.pluginId,
        submissionId: submissionId,
        note: note.isEmpty ? 'v${sub.version}' : note,
        createdAt: DateTime.now(),
      ),
    );
    return {
      'submission': store.pluginSubmissions[submissionId]!.toJson(),
      'release': release.toAdminJson(),
      'marketVersion': store.pluginMarketVersion,
    };
  }

  /// A1 批量审核：一次性通过/拒绝多个投稿，统一 note。
  Future<void> adminBulkReviewPluginSubmissions(HttpRequest request) async {
    final body = await readJsonObject(request) ?? <String, dynamic>{};
    final action = (body['action']?.toString() ?? '').trim();
    if (action != 'approve' && action != 'reject') {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': 'action 必须为 approve 或 reject'},
      });
      return;
    }
    final note =
        (body['note']?.toString() ?? body['reviewNote']?.toString() ?? '')
            .trim();
    final featured = body['featured'] == true;
    final idsRaw = body['ids'];
    final ids = <String>[];
    if (idsRaw is List) {
      for (final id in idsRaw) {
        final s = id.toString().trim();
        if (s.isNotEmpty) ids.add(s);
      }
    }
    if (ids.isEmpty) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': 'ids 不能为空'},
      });
      return;
    }
    if (ids.length > 50) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '单次批量上限 50 条'},
      });
      return;
    }
    final admin = await optionalUser(request);
    final ok = <String>[];
    final skipped = <Map<String, dynamic>>[];
    for (final id in ids) {
      final sub = store.pluginSubmissions[id];
      if (sub == null) {
        skipped.add({'id': id, 'reason': '投稿不存在'});
        continue;
      }
      if (sub.status != 'pending_review') {
        skipped.add({'id': id, 'reason': '状态不可审核：${sub.status}'});
        continue;
      }
      _applyReviewDecision(
        sub: sub,
        action: action,
        note: note,
        featured: featured,
        admin: admin,
      );
      ok.add(id);
    }
    if (ok.isNotEmpty) {
      store.bumpPluginCounter('bulk_review_$action');
      await store.save();
    }
    await jsonResponse(request.response, HttpStatus.ok, {
      'action': action,
      'requested': ids.length,
      'succeeded': ok.length,
      'skipped': skipped,
      'okIds': ok,
      'marketVersion': store.pluginMarketVersion,
    });
  }

  Future<void> adminYankPlugin(HttpRequest request, String pluginId) async {
    final release = store.pluginReleases[pluginId];
    if (release == null) {
      await jsonResponse(request.response, HttpStatus.notFound, {
        'error': {'message': '发布记录不存在'},
      });
      return;
    }
    final body = await readJsonObject(request) ?? <String, dynamic>{};
    final note = (body['note']?.toString() ?? '').trim();
    final forceUninstall = body['forceUninstall'] == true;
    store.pluginReleases[pluginId] = release.copyWith(
      status: 'yanked',
      yankNote: note.isEmpty ? '管理员下架' : note,
      forceUninstall: forceUninstall,
    );
    store.pluginMarketVersion += 1;
    final admin = await optionalUser(request);
    store.addPluginAudit(
      PluginAuditEvent(
        id: 'pa_${randomBase64(8)}',
        action: forceUninstall ? 'yank_force_uninstall' : 'yank',
        actorUserId: admin?.id ?? '',
        actorName: admin?.username ?? 'admin',
        pluginId: pluginId,
        submissionId: release.submissionId,
        note: note.isEmpty ? '管理员下架' : note,
        createdAt: DateTime.now(),
      ),
    );
    await store.save();
    await jsonResponse(request.response, HttpStatus.ok, {
      'release': store.pluginReleases[pluginId]!.toAdminJson(),
      'marketVersion': store.pluginMarketVersion,
    });
  }

  Future<void> reportPlugin(
    HttpRequest request,
    Account account,
    String pluginId,
  ) async {
    final release = store.pluginReleases[pluginId];
    if (release == null || release.status != 'published') {
      await jsonResponse(request.response, HttpStatus.notFound, {
        'error': {'message': '插件不存在或未发布'},
      });
      return;
    }
    final body = await readJsonObject(request) ?? <String, dynamic>{};
    final reason = (body['reason']?.toString() ?? '').trim();
    if (reason.isEmpty) {
      await jsonResponse(request.response, HttpStatus.badRequest, {
        'error': {'message': '请填写举报原因'},
      });
      return;
    }
    // 同用户同插件 24h 限 1 次
    final since = DateTime.now().subtract(const Duration(hours: 24));
    final dup = store.pluginReports.any((r) =>
        r.pluginId == pluginId &&
        r.reporterUserId == account.id &&
        r.createdAt.isAfter(since));
    if (dup) {
      await jsonResponse(request.response, HttpStatus.tooManyRequests, {
        'error': {'message': '24 小时内已举报过该插件'},
      });
      return;
    }
    final report = PluginReport(
      id: 'pr_${randomBase64(8)}',
      pluginId: pluginId,
      reporterUserId: account.id,
      reporterName: account.username,
      reason: reason,
      createdAt: DateTime.now(),
      status: 'open',
    );
    store.pluginReports.insert(0, report);
    if (store.pluginReports.length > 500) {
      store.pluginReports.removeRange(500, store.pluginReports.length);
    }
    store.addPluginAudit(
      PluginAuditEvent(
        id: 'pa_${randomBase64(8)}',
        action: 'report',
        actorUserId: account.id,
        actorName: account.username,
        pluginId: pluginId,
        submissionId: release.submissionId,
        note: reason,
        createdAt: DateTime.now(),
      ),
    );
    await store.save();
    await jsonResponse(request.response, HttpStatus.created, report.toJson());
  }

  Future<void> adminListReports(HttpRequest request) async {
    final status = (request.uri.queryParameters['status'] ?? '').trim();
    var list = store.pluginReports.toList();
    if (status.isNotEmpty) {
      list = list.where((r) => r.status == status).toList();
    }
    await jsonResponse(request.response, HttpStatus.ok, {
      'items': list.map((e) => e.toJson()).toList(),
      'count': list.length,
      'openCount': store.pluginReports.where((r) => r.status == 'open').length,
    });
  }

  Future<void> adminBanAuthor(
    HttpRequest request,
    String userId,
    bool ban,
  ) async {
    final body = await readJsonObject(request) ?? <String, dynamic>{};
    final note =
        (body['note']?.toString() ?? body['reason']?.toString() ?? '').trim();
    final admin = await optionalUser(request);
    if (ban) {
      store.pluginBannedAuthors[userId] = note.isEmpty ? '管理员禁止投稿' : note;
    } else {
      store.pluginBannedAuthors.remove(userId);
    }
    store.addPluginAudit(
      PluginAuditEvent(
        id: 'pa_${randomBase64(8)}',
        action: ban ? 'ban_author' : 'unban_author',
        actorUserId: admin?.id ?? '',
        actorName: admin?.username ?? 'admin',
        pluginId: '',
        submissionId: '',
        note: '$userId ${note.isEmpty ? '' : note}',
        createdAt: DateTime.now(),
      ),
    );
    await store.save();
    await jsonResponse(request.response, HttpStatus.ok, {
      'userId': userId,
      'banned': ban,
      'reason': store.pluginBannedAuthors[userId],
      'bannedAuthors': store.pluginBannedAuthors,
    });
  }

  Future<void> adminPreviewSubmission(
    HttpRequest request,
    String submissionId,
  ) async {
    final sub = store.pluginSubmissions[submissionId];
    if (sub == null) {
      await jsonResponse(request.response, HttpStatus.notFound, {
        'error': {'message': '投稿不存在'},
      });
      return;
    }
    final actionOk = _allowedPluginActions.contains(sub.actionCode);
    final files = <Map<String, dynamic>>[];
    String? packageError;
    if (sub.packagePath.isNotEmpty) {
      try {
        final file = File('${_pluginPackagesDir.path}/${sub.packagePath}');
        if (!file.existsSync()) {
          packageError = '包文件丢失';
        } else {
          final list = await Process.run('unzip', ['-Z1', file.path]);
          if (list.exitCode == 0) {
            final names = (list.stdout?.toString() ?? '')
                .split('\n')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
            // sizes via unzip -Z
            final detail = await Process.run('unzip', ['-Z', file.path]);
            final sizeMap = <String, int>{};
            for (final line in (detail.stdout?.toString() ?? '').split('\n')) {
              // typical:  "  123  Defl:N  ..." last field name
              final parts = line.trim().split(RegExp(r'\s+'));
              if (parts.length >= 8 && int.tryParse(parts[0]) != null) {
                sizeMap[parts.last] = int.tryParse(parts[0]) ?? 0;
              }
            }
            for (final name in names.take(50)) {
              final base = name.split('/').last;
              final hasExt = !name.endsWith('/') && base.contains('.');
              files.add({
                'name': name,
                'size': sizeMap[name] ?? 0,
                'banned': _bannedZipExt.hasMatch(name),
                'allowed': !hasExt || _allowedZipExt.hasMatch(base),
                'isIcon': base.toLowerCase() == 'icon.png',
              });
            }
          } else {
            packageError = '无法列出 zip 内容';
          }
        }
      } catch (e) {
        packageError = '预览失败：$e';
      }
    }
    Map<String, dynamic>? pluginJson;
    if (sub.packageJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(sub.packageJson);
        if (decoded is Map) pluginJson = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    // A2: 提取 icon.png 缩略图（≤256KB）为 base64，供审核端直接预览
    String? iconBase64;
    int iconBytes = 0;
    if (sub.packagePath.isNotEmpty) {
      try {
        final iconEntry = files.firstWhere(
          (f) => f['isIcon'] == true,
          orElse: () => const {},
        );
        final iconName = iconEntry['name']?.toString() ?? '';
        final iconSize = (iconEntry['size'] as int?) ?? 0;
        if (iconName.isNotEmpty && iconSize <= _maxPluginIconBytes) {
          final file = File('${_pluginPackagesDir.path}/${sub.packagePath}');
          if (file.existsSync()) {
            final out = await Process.run(
              'unzip',
              ['-p', file.path, iconName],
              stdoutEncoding: null,
            );
            if (out.exitCode == 0 && out.stdout is List<int>) {
              final bytes = out.stdout as List<int>;
              if (bytes.isNotEmpty && bytes.length <= _maxPluginIconBytes) {
                iconBase64 = base64Encode(bytes);
                iconBytes = bytes.length;
              }
            }
          }
        }
      } catch (_) {}
    }
    final hasBanned = files.any((f) => f['banned'] == true);
    final hasDisallowed = files.any((f) => f['allowed'] == false);
    final hasIcon = files.any((f) => f['isIcon'] == true);
    await jsonResponse(request.response, HttpStatus.ok, {
      'submission': sub.toJson(),
      'compatibility': {
        'actionAllowed': actionOk,
        'actionCode': sub.actionCode,
        'areaCode': sub.areaCode,
        'hasTitle': sub.title.trim().isNotEmpty,
        'packageFormat': sub.packageFormat,
        'packageSize': sub.packageSize,
        'packageSha256': sub.packageSha256,
      },
      'pluginJson': pluginJson,
      'files': files,
      if (iconBase64 != null) 'iconBase64': iconBase64,
      if (iconBase64 != null) 'iconBytes': iconBytes,
      if (packageError != null) 'packageError': packageError,
      'checklist': {
        'actionWhitelist': actionOk,
        'noReservedId': !sub.pluginId.startsWith('builtin_') &&
            !sub.pluginId.startsWith('market_'),
        'hasPackageOrPayload': sub.packagePath.isNotEmpty ||
            sub.payload.isNotEmpty ||
            sub.payloadData.isNotEmpty,
        'resourceWhitelist': !hasBanned && !hasDisallowed,
        'hasIconPng': hasIcon,
        'iconMax256k': true,
      },
    });
  }

  Future<void> pluginMarketInstall(HttpRequest request, String pluginId) async {
    final release = store.pluginReleases[pluginId];
    if (release == null || release.status != 'published') {
      store.bumpPluginCounter('install_miss');
      stderr.writeln('[plugin-market] install miss id=$pluginId');
      await jsonResponse(request.response, HttpStatus.notFound, {
        'error': {
          'message': '插件不可安装（未发布或已下架）',
          'code': 'plugin_not_installable',
        },
      });
      return;
    }
    store.pluginReleases[pluginId] = release.copyWith(
      downloadCount: release.downloadCount + 1,
    );
    store.bumpPluginCounter('install_ok');
    store.addPluginAudit(
      PluginAuditEvent(
        id: 'pa_${randomBase64(8)}',
        action: 'install',
        actorUserId: '',
        actorName: 'client',
        pluginId: pluginId,
        submissionId: release.submissionId,
        note: 'v${release.version}',
        createdAt: DateTime.now(),
      ),
    );
    await store.save();
    stderr.writeln(
        '[plugin-market] install ok id=$pluginId v=${release.version}');
    await jsonResponse(request.response, HttpStatus.ok, {
      'id': pluginId,
      'downloadCount': store.pluginReleases[pluginId]!.downloadCount,
      'version': release.version,
      'packageSha256': release.packageSha256,
      'packageJson': release.packageJson,
      'packageFormat': release.packageFormat.isEmpty
          ? (release.packagePath.isNotEmpty ? 'zip' : 'json')
          : release.packageFormat,
      'packageSize': release.packageSize,
      if (release.packagePath.isNotEmpty)
        'packageUrl': '/api/plugin-market/$pluginId/package',
    });
  }

  Future<void> pluginMarketStatus(HttpRequest request) async {
    final body = await readJsonObject(request) ?? <String, dynamic>{};
    final idsRaw = body['ids'];
    final ids = <String>[];
    if (idsRaw is List) {
      for (final id in idsRaw) {
        final s = id.toString().trim();
        if (s.isNotEmpty) ids.add(s);
      }
    }
    final items = <Map<String, dynamic>>[];
    for (final id in ids) {
      final release = store.pluginReleases[id];
      if (release == null) {
        items.add({
          'id': id,
          'status': 'unknown',
          'message': '商店无此插件',
        });
        continue;
      }
      items.add({
        'id': id,
        'status': release.status,
        'version': release.version,
        'yankNote': release.yankNote,
        'packageSha256': release.packageSha256,
        'downloadCount': release.downloadCount,
        'title': release.title,
        'forceUninstall': release.forceUninstall,
        'changelog': release.changelog,
      });
    }
    await jsonResponse(request.response, HttpStatus.ok, {
      'items': items,
      'marketVersion': store.pluginMarketVersion,
    });
  }

  Future<void> adminPluginAudit(HttpRequest request) async {
    await jsonResponse(request.response, HttpStatus.ok, {
      'items': store.pluginAudit.map((e) => e.toJson()).toList(),
      'count': store.pluginAudit.length,
    });
  }

  Future<void> adminFeaturePlugin(HttpRequest request, String pluginId) async {
    final release = store.pluginReleases[pluginId];
    if (release == null || release.status != 'published') {
      await jsonResponse(request.response, HttpStatus.notFound, {
        'error': {'message': '仅已发布插件可推荐'},
      });
      return;
    }
    final body = await readJsonObject(request) ?? <String, dynamic>{};
    final featured = body['featured'] != false;
    store.pluginReleases[pluginId] = release.copyWith(featured: featured);
    store.pluginMarketVersion += 1;
    await store.save();
    await jsonResponse(request.response, HttpStatus.ok, {
      'release': store.pluginReleases[pluginId]!.toAdminJson(),
      'marketVersion': store.pluginMarketVersion,
    });
  }

  // ── Personal Center: User Self-View Endpoints ──

  /// GET /api/me/overview
  /// 返回当前登录用户的个人中心总览：基础信息 + 额度 + 统计摘要。
  Future<void> meOverview(HttpRequest request, Account account) async {
    final user = store.quota(account.id);
    // 今日生图次数（成功请求数，来自 usage 中当天且 userId 匹配的记录）
    final today = dateKey(DateTime.now());
    var todayRequests = 0;
    var todayCost = 0;
    var todaySuccess = 0;
    for (final item in store.usage) {
      if (item.userId != account.id) continue;
      if (dateKey(item.createdAt) != today) continue;
      todayRequests++;
      todayCost += item.cost;
      if (item.success) todaySuccess++;
    }
    // 历史提交题目总数
    final mySubmissions = store.quizSubmissions.values
        .where((s) => s.submitterUserId == account.id)
        .toList();
    final pendingSubmissions =
        mySubmissions.where((s) => s.status == 'pending').length;
    final mergedSubmissions =
        mySubmissions.where((s) => s.status == 'merged').length;
    final approvedSubmissions =
        mySubmissions.where((s) => s.status == 'approved').length;
    // 已发布题目总数（全局）
    final publishedCount =
        store.quizQuestions.values.where((q) => q.status == 'published').length;
    await jsonResponse(request.response, HttpStatus.ok, {
      'user': account.toPublicJson(),
      'quota': user.toQuotaJson(),
      'stats': {
        'todayRequests': todayRequests,
        'todaySuccess': todaySuccess,
        'todayCost': todayCost,
        'mySubmissions': mySubmissions.length,
        'myPendingSubmissions': pendingSubmissions,
        'myMergedSubmissions': mergedSubmissions,
        'myApprovedSubmissions': approvedSubmissions,
        'publishedQuestions': publishedCount,
      },
    });
  }

  /// GET /api/me/quota/transactions
  /// 返回当前用户的生图用量明细（只读，按时间倒序，默认最近 20 条，最多 200 条）。
  Future<void> meQuotaTransactions(HttpRequest request, Account account) async {
    final query = request.uri.queryParameters;
    final limit = asInt(query['limit'] ?? '', 20).clamp(1, 200);
    final successFilter = parseBool(query['success']);
    final transactions = usageJson(
      userId: account.id,
      success: successFilter,
      limit: limit,
      maxLimit: 200,
    );
    // 汇总覆盖全部匹配记录，而不是被 limit 截断后的当页数据，
    // 否则客户端展示的“共 N 条 / 消耗 N 点”会永远等于 limit。
    var matchedTotal = 0;
    var totalCost = 0;
    var totalSuccess = 0;
    for (final item in store.usage) {
      if (item.userId != account.id) continue;
      if (successFilter != null && item.success != successFilter) continue;
      matchedTotal++;
      totalCost += item.cost;
      if (item.success) totalSuccess++;
    }
    await jsonResponse(request.response, HttpStatus.ok, {
      'transactions': transactions,
      'summary': {
        'total': matchedTotal,
        'returned': transactions.length,
        'totalCost': totalCost,
        'totalSuccess': totalSuccess,
        'totalFailed': matchedTotal - totalSuccess,
      },
    });
  }

  /// GET /api/me/plugins
  /// 返回当前用户投稿的插件，支持 ?status=...、?offset=N、?limit=N。
  Future<void> mePlugins(HttpRequest request, Account account) async {
    final query = request.uri.queryParameters;
    final status = (query['status'] ?? '').trim().toLowerCase();
    final offset = asInt(query['offset'] ?? '', 0).clamp(0, 100000);
    final limit = asInt(query['limit'] ?? '', 20).clamp(1, 100);
    final list = store.pluginSubmissions.values
        .where((item) => item.authorUserId == account.id)
        .where((item) => status.isEmpty || item.status.toLowerCase() == status)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final page = list.skip(offset).take(limit).toList();
    await jsonResponse(request.response, HttpStatus.ok, {
      'items': page.map((item) => item.toJson()).toList(),
      'total': list.length,
      'offset': offset,
      'limit': limit,
      'hasMore': offset + page.length < list.length,
    });
  }

  /// GET /api/me/quiz/questions
  /// 返回当前用户提交/审核的题目列表（只读，不暴露其他用户的数据）。
  /// 支持 ?status=pending|merged|approved|all 与 ?limit=N (默认 20, 最大 100)
  Future<void> meQuizQuestions(HttpRequest request, Account account) async {
    final query = request.uri.queryParameters;
    final statusFilter = (query['status'] ?? 'all').trim().toLowerCase();
    final offset = asInt(query['offset'] ?? '', 0).clamp(0, 100000);
    final limit = asInt(query['limit'] ?? '', 20).clamp(1, 100);
    final submissions = store.quizSubmissions.values
        .where((s) => s.submitterUserId == account.id)
        .toList()
      ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    final filtered = switch (statusFilter) {
      'pending' => submissions.where((s) => s.status == 'pending').toList(),
      'merged' => submissions.where((s) => s.status == 'merged').toList(),
      'approved' => submissions.where((s) => s.status == 'approved').toList(),
      _ => submissions,
    };
    final page = filtered.skip(offset).take(limit).toList();
    final result = page
        .map((s) => {
              'id': s.id,
              'question': s.question.toJson(),
              'status': s.status,
              'submittedAt': s.submittedAt.toIso8601String(),
              'reviewNote': s.reviewNote,
              if (s.linkedQuestionId != null)
                'linkedQuestionId': s.linkedQuestionId,
              if (s.reviewedAt != null)
                'reviewedAt': s.reviewedAt!.toIso8601String(),
            })
        .toList();
    await jsonResponse(request.response, HttpStatus.ok, {
      'questions': result,
      'total': filtered.length,
      'offset': offset,
      'limit': limit,
      'hasMore': offset + page.length < filtered.length,
    });
  }

  /// GET /api/me/activity
  /// 返回最近 30 天的每日活动摘要（请求数、成功数、消耗点数）。
  Future<void> meActivity(HttpRequest request, Account account) async {
    final days = List.generate(30, (index) {
      final d = DateTime.now().subtract(Duration(days: 29 - index));
      return dateKey(d);
    });
    final daily = <String, Map<String, dynamic>>{};
    for (final key in days) {
      daily[key] = {'date': key, 'requests': 0, 'success': 0, 'cost': 0};
    }
    for (final item in store.usage) {
      if (item.userId != account.id) continue;
      final key = dateKey(item.createdAt);
      final day = daily[key];
      if (day == null) continue;
      day['requests'] = (day['requests'] as int) + 1;
      day['cost'] = (day['cost'] as int) + item.cost;
      if (item.success) day['success'] = (day['success'] as int) + 1;
    }
    // 按日期升序排列
    final activity = days.map((key) => daily[key]!).toList();
    await jsonResponse(request.response, HttpStatus.ok, {
      'activity': activity,
      'totalRequests':
          activity.fold(0, (sum, d) => sum + (d['requests'] as int)),
      'totalSuccess': activity.fold(0, (sum, d) => sum + (d['success'] as int)),
      'totalCost': activity.fold(0, (sum, d) => sum + (d['cost'] as int)),
    });
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
  final quizQuestions = <String, QuizQuestion>{};
  final quizSubmissions = <String, QuizSubmission>{};
  final quizChanges = <QuizChange>[];
  final quizImports = <QuizImportRecord>[];
  final quizIncomplete = <QuizIncompleteRecord>[];
  int quizSequence = 0;
  PluginPolicyState pluginPolicy = PluginPolicyState.defaults();
  final pluginSubmissions = <String, PluginSubmission>{};
  final pluginReleases = <String, PluginRelease>{};
  final pluginAudit = <PluginAuditEvent>[];
  final pluginReports = <PluginReport>[];
  final pluginBannedAuthors = <String, String>{}; // userId -> reason
  final pluginCounters = <String, int>{};
  int pluginMarketVersion = 1;
  ProviderConfig? providerConfig;

  // AI 读屏上游凭证（管理员配置，永不下发客户端）。
  QuizVisionProviderConfig? quizVisionProvider;
  // 每日限额计数（UTC 日键）。A2：延迟合并落盘——正常随既有 save() 持久化，
  // 用量变化只置脏，由 _flushQuizVision 限频 60s 合并写（启发式：崩溃窗口内
  // 最多丢 60s 计数，重启后按落盘值恢复，防滥用用途足够）。
  final quizVisionUsage = <String, Map<String, int>>{};
  // A1：每账号每日上游失败数（异常+非2xx），随 save 持久化，供 /admin 统计。
  final quizVisionUpstreamFailures = <String, Map<String, int>>{};
  // A3：突发限流窗口（仅内存，重启清零）。
  final quizVisionBurstHits = <String, List<DateTime>>{};
  bool quizVisionDirty = false;
  DateTime? quizVisionLastPersistedAt;
  Timer? quizVisionFlushTimer;

  // ── 云端书源 / 公告（新增） ──
  final cloudBookSources = <String, CloudBookSource>{};
  int bookSourceVersion = 0;
  DateTime? bookSourcePublishedAt;
  final announcements = <String, Announcement>{};
  int announcementVersion = 0;

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

    final rawQuizVision = decoded['quizVisionProvider'];
    if (rawQuizVision is Map) {
      quizVisionProvider = QuizVisionProviderConfig.fromJson(
        Map<String, dynamic>.from(rawQuizVision),
      );
    }
    final rawQuizVisionUsage = decoded['quizVisionUsage'];
    if (rawQuizVisionUsage is Map) {
      rawQuizVisionUsage.forEach((key, value) {
        if (value is Map) {
          quizVisionUsage[key.toString()] = value.map(
            (k, v) => MapEntry(k.toString(), (v is num ? v.toInt() : 0)),
          );
        }
      });
    }
    final rawQuizVisionFailures = decoded['quizVisionUpstreamFailures'];
    if (rawQuizVisionFailures is Map) {
      rawQuizVisionFailures.forEach((key, value) {
        if (value is Map) {
          quizVisionUpstreamFailures[key.toString()] = value.map(
            (k, v) => MapEntry(k.toString(), (v is num ? v.toInt() : 0)),
          );
        }
      });
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

    final rawQuizQuestions = decoded['quizQuestions'];
    if (rawQuizQuestions is Map) {
      rawQuizQuestions.forEach((key, value) {
        if (value is Map) {
          quizQuestions[key.toString()] = QuizQuestion.fromJson(
            Map<String, dynamic>.from(value),
          );
        }
      });
    }
    final rawQuizSubmissions = decoded['quizSubmissions'];
    if (rawQuizSubmissions is Map) {
      rawQuizSubmissions.forEach((key, value) {
        if (value is Map) {
          quizSubmissions[key.toString()] = QuizSubmission.fromJson(
            Map<String, dynamic>.from(value),
          );
        }
      });
    }
    final rawQuizChanges = decoded['quizChanges'];
    if (rawQuizChanges is List) {
      for (final value in rawQuizChanges) {
        if (value is Map) {
          quizChanges.add(
            QuizChange.fromJson(Map<String, dynamic>.from(value)),
          );
        }
      }
    }
    final rawQuizImports = decoded['quizImports'];
    if (rawQuizImports is List) {
      for (final value in rawQuizImports.whereType<Map>()) {
        quizImports.add(
          QuizImportRecord.fromJson(Map<String, dynamic>.from(value)),
        );
      }
    }
    final rawQuizIncomplete = decoded['quizIncomplete'];
    if (rawQuizIncomplete is List) {
      for (final value in rawQuizIncomplete.whereType<Map>()) {
        quizIncomplete.add(
          QuizIncompleteRecord.fromJson(Map<String, dynamic>.from(value)),
        );
      }
    }
    quizSequence = asInt(
      decoded['quizSequence'],
      quizChanges.fold(0, (max, c) => c.sequence > max ? c.sequence : max),
    );

    final rawUsage = decoded['usage'];
    if (rawUsage is List) {
      for (final item in rawUsage) {
        if (item is Map) {
          usage.add(UsageRecord.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    final rawPolicy = decoded['pluginPolicy'];
    if (rawPolicy is Map) {
      pluginPolicy = PluginPolicyState.fromJson(
        Map<String, dynamic>.from(rawPolicy),
      );
    } else {
      pluginPolicy = PluginPolicyState.defaults();
    }

    final rawPluginSubs = decoded['pluginSubmissions'];
    if (rawPluginSubs is Map) {
      rawPluginSubs.forEach((key, value) {
        if (value is Map) {
          pluginSubmissions[key.toString()] = PluginSubmission.fromJson(
            Map<String, dynamic>.from(value),
          );
        }
      });
    }
    final rawPluginReleases = decoded['pluginReleases'];
    if (rawPluginReleases is Map) {
      rawPluginReleases.forEach((key, value) {
        if (value is Map) {
          pluginReleases[key.toString()] = PluginRelease.fromJson(
            Map<String, dynamic>.from(value),
          );
        }
      });
    }
    pluginMarketVersion = asInt(decoded['pluginMarketVersion'], 1);
    if (pluginMarketVersion <= 0) pluginMarketVersion = 1;
    final rawAudit = decoded['pluginAudit'];
    if (rawAudit is List) {
      for (final value in rawAudit.whereType<Map>()) {
        pluginAudit.add(
          PluginAuditEvent.fromJson(Map<String, dynamic>.from(value)),
        );
      }
    }
    final rawReports = decoded['pluginReports'];
    if (rawReports is List) {
      for (final value in rawReports.whereType<Map>()) {
        pluginReports.add(
          PluginReport.fromJson(Map<String, dynamic>.from(value)),
        );
      }
    }
    final rawBanned = decoded['pluginBannedAuthors'];
    if (rawBanned is Map) {
      rawBanned.forEach((k, v) {
        pluginBannedAuthors[k.toString()] = v?.toString() ?? 'banned';
      });
    }
    final rawCounters = decoded['pluginCounters'];
    if (rawCounters is Map) {
      rawCounters.forEach((k, v) {
        pluginCounters[k.toString()] = asInt(v, 0);
      });
    }

    final rawCloudSources = decoded['cloudBookSources'];
    if (rawCloudSources is Map) {
      rawCloudSources.forEach((key, value) {
        if (value is Map) {
          cloudBookSources[key.toString()] = CloudBookSource.fromJson(
            Map<String, dynamic>.from(value),
          );
        }
      });
    }
    bookSourceVersion = asInt(decoded['bookSourceVersion'], 0);
    bookSourcePublishedAt = DateTime.tryParse(
      decoded['bookSourcePublishedAt']?.toString() ?? '',
    );
    final rawAnnouncements = decoded['announcements'];
    if (rawAnnouncements is Map) {
      rawAnnouncements.forEach((key, value) {
        if (value is Map) {
          announcements[key.toString()] = Announcement.fromJson(
            Map<String, dynamic>.from(value),
          );
        }
      });
    }
    announcementVersion = asInt(decoded['announcementVersion'], 0);
  }

  void addPluginAudit(PluginAuditEvent event) {
    pluginAudit.insert(0, event);
    if (pluginAudit.length > 500) {
      pluginAudit.removeRange(500, pluginAudit.length);
    }
  }

  void bumpPluginCounter(String key, [int by = 1]) {
    pluginCounters[key] = (pluginCounters[key] ?? 0) + by;
  }

  /// 题库图片目录，始终与状态文件同目录。
  ///
  /// 原先硬编码为相对路径 '.var/quiz_images'，而状态文件由 IMAGE_STATE_PATH
  /// 指到别处（生产是 /opt/box-backend/data/），两者分家会导致图片落在
  /// WorkingDirectory 下、被备份漏掉。这里统一从状态文件目录推导。
  Directory get quizImagesDir =>
      Directory('${File(path).parent.path}/quiz_images');

  /// 清理已过期会话，返回清理条数。
  ///
  /// 会话有效期 30 天，但此前没有任何回收机制：过期条目会永久留在状态文件里，
  /// 既让文件无谓膨胀，也意味着一份泄露的旧状态文件里全是长期有效的令牌。
  /// 启动时清一次，之后按固定周期清。
  int pruneExpiredSessions() {
    final now = DateTime.now();
    final expired = <String>[];
    sessions.forEach((token, session) {
      if (session.expiresAt.isBefore(now)) expired.add(token);
    });
    for (final token in expired) {
      sessions.remove(token);
    }
    return expired.length;
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
    const adminId = 'u_admin';
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

  String nextQuizQuestionId() => 'q_${randomBase64(9)}';
  String nextQuizSubmissionId() => 'qs_${randomBase64(9)}';
  String nextPluginSubmissionId() => 'ps_${randomBase64(9)}';
  String nextBookSourceId() => 'bs_${randomBase64(9)}';
  String nextAnnouncementId() => 'an_${randomBase64(9)}';

  void recordQuizChange(String questionId, String operation) {
    quizSequence++;
    quizChanges.add(
      QuizChange(
        sequence: quizSequence,
        questionId: questionId,
        operation: operation,
        changedAt: DateTime.now(),
      ),
    );
    if (quizChanges.length > 5000) {
      quizChanges.removeRange(0, quizChanges.length - 5000);
    }
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
        if (quizVisionProvider != null)
          'quizVisionProvider': quizVisionProvider!.toJson(),
        if (quizVisionUsage.isNotEmpty)
          'quizVisionUsage': quizVisionUsage,
        if (quizVisionUpstreamFailures.isNotEmpty)
          'quizVisionUpstreamFailures': quizVisionUpstreamFailures,
        'accounts': accounts.map((key, value) => MapEntry(key, value.toJson())),
        'quotas': quotas.map((key, value) => MapEntry(key, value.toJson())),
        'sessions': sessions.map((key, value) => MapEntry(key, value.toJson())),
        'usage': usage.map((item) => item.toJson()).toList(),
        'quizQuestions': quizQuestions.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
        'quizSubmissions': quizSubmissions.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
        'quizChanges': quizChanges.map((item) => item.toJson(null)).toList(),
        'quizImports': quizImports.map((item) => item.toJson()).toList(),
        'quizIncomplete': quizIncomplete.map((item) => item.toJson()).toList(),
        'quizSequence': quizSequence,
        'pluginPolicy': pluginPolicy.toJson(),
        'pluginSubmissions': pluginSubmissions.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
        'pluginReleases': pluginReleases.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
        'pluginMarketVersion': pluginMarketVersion,
        'pluginAudit': pluginAudit.map((e) => e.toJson()).toList(),
        'pluginReports': pluginReports.map((e) => e.toJson()).toList(),
        'pluginBannedAuthors': pluginBannedAuthors,
        'pluginCounters': pluginCounters,
        'cloudBookSources': cloudBookSources.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
        'bookSourceVersion': bookSourceVersion,
        if (bookSourcePublishedAt != null)
          'bookSourcePublishedAt': bookSourcePublishedAt!.toIso8601String(),
        'announcements': announcements.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
        'announcementVersion': announcementVersion,
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
    final providerApiKey =
        provider == null ? '' : decodeProviderApiKey(provider.apiKeyCipher);
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

  // ── A1/A2：读屏用量落盘辅助 ──
  void markQuizVisionPersisted() {
    quizVisionDirty = false;
    quizVisionLastPersistedAt = DateTime.now();
  }

  /// 限频合并写：脏了就排一个 60s 后的 flush（期间再次置脏不重复排队）。
  /// 并发保护：单 isolate 事件循环内 schedule/cancel 原子。
  void scheduleQuizVisionFlush() {
    if (quizVisionFlushTimer != null) return;
    quizVisionFlushTimer = Timer(const Duration(seconds: 60), () async {
      quizVisionFlushTimer = null;
      if (!quizVisionDirty) return;
      await save();
      markQuizVisionPersisted();
    });
  }

  void quizVisionRecordUpstreamFailure(String accountId, String dayKey) {
    final perDay = quizVisionUpstreamFailures.putIfAbsent(
      accountId,
      () => <String, int>{},
    );
    perDay[dayKey] = (perDay[dayKey] ?? 0) + 1;
    scheduleQuizVisionFlush();
  }

  /// A3：滑动窗口突发限流。窗口 60s、上限 quizVisionBurstCap，
  /// 调大=更宽松；拒绝的请求不记窗口（不惩罚重试者）。
  bool quizVisionBurstRejected(String accountId, DateTime now) {
    final windowStart = now.subtract(const Duration(minutes: 1));
    final hits = quizVisionBurstHits.putIfAbsent(
      accountId,
      () => <DateTime>[],
    );
    hits.removeWhere((t) => t.isBefore(windowStart));
    if (hits.length >= quizVisionBurstCap) return true;
    hits.add(now);
    return false;
  }

  Future<void> save() async {
    final file = File(path);
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    // 原子写：先写临时文件并 flush，再 rename 覆盖正式文件。
    // 避免进程在写入中途被 kill / 磁盘写满时，把状态文件截断成损坏的 JSON
    // （该文件是全部账号、题库、用量的唯一存储）。
    final tmp = File('$path.tmp');
    await tmp.writeAsString(encoder.convert(toJson()), flush: true);
    await tmp.rename(path);
  }
}

// ── 云端书源 / 公告 模型（新增） ──

/// 云端下发的书源条目。全员同一份，云端为准。
class CloudBookSource {
  CloudBookSource({
    required this.id,
    required this.name,
    required this.url,
    required this.group,
    required this.rawJson,
    required this.enabled,
    required this.weight,
    required this.sort,
    required this.updatedAt,
    this.removed = false,
  });

  factory CloudBookSource.fromJson(Map<String, dynamic> json) {
    return CloudBookSource(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      group: json['group']?.toString() ?? '',
      rawJson: json['rawJson']?.toString() ?? '',
      enabled: json['enabled'] != false,
      weight: asInt(json['weight'], 0),
      sort: asInt(json['sort'], 0),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
      removed: json['removed'] == true,
    );
  }

  final String id;
  final String name;
  final String url;
  final String group;

  /// 完整书源规则 JSON 字符串（客户端 BookSourceModel.fromJson 直接吃）。
  final String rawJson;
  final bool enabled;
  final int weight;
  final int sort;
  final DateTime updatedAt;

  /// 软删除标记：客户端拉到 removed=true 时把本地对应书源删掉。
  final bool removed;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'group': group,
        'rawJson': rawJson,
        'enabled': enabled,
        'weight': weight,
        'sort': sort,
        'updatedAt': updatedAt.toIso8601String(),
        'removed': removed,
      };

  /// 下发给客户端的形态。removed 条目只带 id + removed，省流量。
  Map<String, dynamic> toClientJson() {
    if (removed) {
      return {'id': id, 'removed': true};
    }
    return {
      'id': id,
      'name': name,
      'url': url,
      'group': group,
      'rawJson': rawJson,
      'enabled': enabled,
      'weight': weight,
      'sort': sort,
      'updatedAt': updatedAt.toIso8601String(),
      'removed': false,
    };
  }
}

/// 站内公告。用户端在「我的」页以红点 + 可回看列表呈现。
class Announcement {
  Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.level,
    required this.publishedAt,
    required this.updatedAt,
    this.pinned = false,
    this.linkUrl = '',
    this.published = true,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    final published = DateTime.tryParse(
          json['publishedAt']?.toString() ?? '',
        ) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return Announcement(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      level: normalizeAnnouncementLevel(json['level']?.toString()),
      publishedAt: published,
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? published,
      pinned: json['pinned'] == true,
      linkUrl: json['linkUrl']?.toString() ?? '',
      published: json['published'] != false,
    );
  }

  final String id;
  final String title;
  final String body;

  /// info / notice / warning
  final String level;
  final DateTime publishedAt;
  final DateTime updatedAt;
  final bool pinned;
  final String linkUrl;
  final bool published;

  Announcement copyWith({
    String? title,
    String? body,
    String? level,
    bool? pinned,
    String? linkUrl,
    bool? published,
    DateTime? updatedAt,
  }) {
    return Announcement(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      level: level == null ? this.level : normalizeAnnouncementLevel(level),
      publishedAt: publishedAt,
      updatedAt: updatedAt ?? DateTime.now(),
      pinned: pinned ?? this.pinned,
      linkUrl: linkUrl ?? this.linkUrl,
      published: published ?? this.published,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'level': level,
        'publishedAt': publishedAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'pinned': pinned,
        'linkUrl': linkUrl,
        'published': published,
      };

  Map<String, dynamic> toClientJson() => {
        'id': id,
        'title': title,
        'body': body,
        'level': level,
        'publishedAt': publishedAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'pinned': pinned,
        'linkUrl': linkUrl,
      };
}

const announcementLevels = <String>{'info', 'notice', 'warning'};

String normalizeAnnouncementLevel(String? raw) {
  final value = (raw ?? '').trim().toLowerCase();
  return announcementLevels.contains(value) ? value : 'info';
}

class QuizQuestion {
  QuizQuestion({
    required this.id,
    required this.identityKey,
    required this.question,
    required this.type,
    required this.options,
    required this.correctAnswer,
    required this.analysis,
    required this.category,
    required this.source,
    required this.status,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    this.image = '',
    this.imageSha256 = '',
    this.imagePerceptualHash = '',
    this.imageRegionHash = '',
    this.imageStatus = '',
    this.issueReason = '',
  });

  factory QuizQuestion.fromRequest(
    Map<String, dynamic> json, {
    required String id,
    required String status,
    int revision = 1,
    DateTime? createdAt,
  }) {
    final optionsRaw = json['options'];
    final options = optionsRaw is List
        ? optionsRaw
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : <String>[];
    final question = json['question']?.toString().trim() ?? '';
    final correctAnswer = json['correctAnswer']?.toString().trim() ??
        json['answer']?.toString().trim() ??
        '';
    return QuizQuestion(
      id: id,
      identityKey: quizIdentityKey(question, options, correctAnswer),
      question: question,
      type: json['type']?.toString() == 'true_false'
          ? 'true_false'
          : 'single_choice',
      options: options,
      correctAnswer: correctAnswer,
      analysis: json['analysis']?.toString().trim() ?? '',
      category: json['category']?.toString().trim() ?? '',
      source: json['source']?.toString().trim().isNotEmpty == true
          ? json['source'].toString().trim()
          : '管理员录入',
      status: status,
      revision: revision,
      createdAt: createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      image: json['image']?.toString().trim() ?? '',
      imageSha256: json['imageSha256']?.toString().trim() ?? '',
      imagePerceptualHash:
          json['imagePerceptualHash']?.toString().trim() ?? '',
      imageRegionHash: json['imageRegionHash']?.toString().trim() ?? '',
      imageStatus: json['imageStatus']?.toString().trim() ?? '',
      issueReason: json['issueReason']?.toString().trim() ?? '',
    );
  }

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    final created = DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now();
    final options =
        (json['options'] is List ? json['options'] as List : const [])
            .map((e) => e.toString())
            .toList();
    // identityKey 一律按当前算法重算，不复用磁盘上的旧值。
    // 算法变更（如把 correctAnswer 纳入指纹）必须对存量数据同样生效，否则旧格式
    // 的 key 会被原样读回，查重仍按老规则走，改动等于没做。重算是纯函数，
    // 幂等且无副作用。
    return QuizQuestion(
      id: json['id']?.toString() ?? '',
      identityKey: quizIdentityKey(
        json['question']?.toString() ?? '',
        options,
        json['correctAnswer']?.toString() ?? '',
      ),
      question: json['question']?.toString() ?? '',
      type: json['type']?.toString() ?? 'single_choice',
      options: options,
      correctAnswer: json['correctAnswer']?.toString() ?? '',
      analysis: json['analysis']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      status: json['status']?.toString() ?? 'published',
      revision: asInt(json['revision'], 1),
      createdAt: created,
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? created,
      image: json['image']?.toString() ?? '',
      imageSha256: json['imageSha256']?.toString() ?? '',
      imagePerceptualHash: json['imagePerceptualHash']?.toString() ?? '',
      imageRegionHash: json['imageRegionHash']?.toString() ?? '',
      imageStatus: json['imageStatus']?.toString() ?? '',
      issueReason: json['issueReason']?.toString() ?? '',
    );
  }

  final String id;
  final String identityKey;
  final String question;
  final String type;
  final List<String> options;
  final String correctAnswer;
  final String analysis;
  String category;
  final String source;
  String status;
  int revision;
  final DateTime createdAt;
  DateTime updatedAt;
  String image;
  final String imageSha256;
  final String imagePerceptualHash;
  final String imageRegionHash;
  final String imageStatus;
  /// 人工标记为问题题时填写的说明（仅 status=incomplete 时有意义）。
  final String issueReason;
  String? get validationError {
    if (question.isEmpty) return '题干不能为空';
    if (type == 'single_choice' && options.length < 2) return '单选题至少需要两个选项';
    if (correctAnswer.isEmpty) return '正确答案不能为空';
    if (correctAnswer.length > 200) return '正确答案过长';
    return null;
  }

  QuizQuestion copyWith({
    String? id,
    String? status,
    String? image,
    String? imageSha256,
    String? imagePerceptualHash,
    String? imageRegionHash,
    String? imageStatus,
    String? issueReason,
  }) =>
      QuizQuestion(
        id: id ?? this.id,
        identityKey: identityKey,
        question: question,
        type: type,
        options: options,
        correctAnswer: correctAnswer,
        analysis: analysis,
        category: category,
        source: source,
        status: status ?? this.status,
        revision: revision,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        image: image ?? this.image,
        imageSha256: imageSha256 ?? this.imageSha256,
        imagePerceptualHash:
            imagePerceptualHash ?? this.imagePerceptualHash,
        imageRegionHash: imageRegionHash ?? this.imageRegionHash,
        imageStatus: imageStatus ?? this.imageStatus,
        issueReason: issueReason ?? this.issueReason,
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'identityKey': identityKey,
        'question': question,
        'type': type,
        'options': options,
        'correctAnswer': correctAnswer,
        if (analysis.isNotEmpty) 'analysis': analysis,
        if (category.isNotEmpty) 'category': category,
        if (image.isNotEmpty) 'image': image,
        if (imageSha256.isNotEmpty) 'imageSha256': imageSha256,
        if (imagePerceptualHash.isNotEmpty)
          'imagePerceptualHash': imagePerceptualHash,
        if (imageRegionHash.isNotEmpty) 'imageRegionHash': imageRegionHash,
        if (imageStatus.isNotEmpty) 'imageStatus': imageStatus,
        if (issueReason.isNotEmpty) 'issueReason': issueReason,
        'source': source,
        'status': status,
        'revision': revision,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}

class QuizSubmission {
  QuizSubmission({
    required this.id,
    required this.question,
    required this.submitterUserId,
    required this.status,
    required this.submittedAt,
    this.reviewNote = '',
    this.linkedQuestionId,
    this.reviewedAt,
  });
  factory QuizSubmission.fromJson(Map<String, dynamic> json) => QuizSubmission(
        id: json['id']?.toString() ?? '',
        question: QuizQuestion.fromJson(
          Map<String, dynamic>.from(json['question'] as Map? ?? const {}),
        ),
        submitterUserId: json['submitterUserId']?.toString() ?? '',
        status: json['status']?.toString() ?? 'pending',
        submittedAt: DateTime.tryParse(json['submittedAt']?.toString() ?? '') ??
            DateTime.now(),
        reviewNote: json['reviewNote']?.toString() ?? '',
        linkedQuestionId: json['linkedQuestionId']?.toString(),
        reviewedAt: DateTime.tryParse(json['reviewedAt']?.toString() ?? ''),
      );
  final String id;
  final QuizQuestion question;
  final String submitterUserId;
  String status;
  final DateTime submittedAt;
  String reviewNote;
  String? linkedQuestionId;
  DateTime? reviewedAt;
  Map<String, dynamic> toJson() => {
        'id': id,
        'question': question.toJson(),
        'submitterUserId': submitterUserId,
        'status': status,
        'submittedAt': submittedAt.toIso8601String(),
        'reviewNote': reviewNote,
        if (linkedQuestionId != null) 'linkedQuestionId': linkedQuestionId,
        if (reviewedAt != null) 'reviewedAt': reviewedAt!.toIso8601String(),
      };
}

class QuizImportRecord {
  const QuizImportRecord({
    required this.id,
    required this.importedAt,
    required this.mode,
    required this.total,
    required this.inserted,
    required this.duplicateSkipped,
    required this.invalid,
  });
  factory QuizImportRecord.fromJson(Map<String, dynamic> json) =>
      QuizImportRecord(
        id: json['id']?.toString() ?? '',
        importedAt: DateTime.tryParse(json['importedAt']?.toString() ?? '') ??
            DateTime.now(),
        mode: json['mode']?.toString() ?? '',
        total: asInt(json['total'], 0),
        inserted: asInt(json['inserted'], 0),
        duplicateSkipped: asInt(json['duplicateSkipped'], 0),
        invalid: asInt(json['invalid'], 0),
      );
  final String id;
  final DateTime importedAt;
  final String mode;
  final int total;
  final int inserted;
  final int duplicateSkipped;
  final int invalid;
  Map<String, dynamic> toJson() => {
        'id': id,
        'importedAt': importedAt.toIso8601String(),
        'mode': mode,
        'total': total,
        'inserted': inserted,
        'duplicateSkipped': duplicateSkipped,
        'invalid': invalid,
      };
}

class QuizIncompleteRecord {
  const QuizIncompleteRecord({
    required this.id,
    required this.importId,
    required this.sourceIndex,
    required this.question,
    required this.type,
    required this.options,
    required this.correctAnswer,
    required this.analysis,
    required this.source,
    required this.reason,
    required this.createdAt,
    this.category = '',
    this.questionId = '',
  });
  factory QuizIncompleteRecord.fromJson(Map<String, dynamic> json) =>
      QuizIncompleteRecord(
        id: json['id']?.toString() ?? '',
        importId: json['importId']?.toString() ?? '',
        sourceIndex: asInt(json['sourceIndex'], 0),
        question: json['question']?.toString() ?? '',
        type: json['type']?.toString() ?? 'single_choice',
        options: (json['options'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        correctAnswer: json['correctAnswer']?.toString() ?? '',
        analysis: json['analysis']?.toString() ?? '',
        source: json['source']?.toString() ?? '',
        reason: json['reason']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        category: json['category']?.toString() ?? '',
        questionId: json['questionId']?.toString() ?? '',
      );
  final String id;
  final String importId;
  final int sourceIndex;
  /// 非空表示这条残缺记录对应题库里一道真实题目（人工标记为问题题）。
  /// 为空表示导入时校验失败的临时记录（还没进题库）。
  final String questionId;
  final String question;
  final String type;
  final List<String> options;
  final String correctAnswer;
  final String analysis;
  final String source;
  final String reason;
  final DateTime createdAt;
  final String category;

  QuizIncompleteRecord copyWith({String? category}) => QuizIncompleteRecord(
        id: id,
        importId: importId,
        sourceIndex: sourceIndex,
        question: question,
        type: type,
        options: options,
        correctAnswer: correctAnswer,
        analysis: analysis,
        source: source,
        reason: reason,
        createdAt: createdAt,
        category: category ?? this.category,
        questionId: questionId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'importId': importId,
        'sourceIndex': sourceIndex,
        'question': question,
        'type': type,
        'options': options,
        'correctAnswer': correctAnswer,
        'analysis': analysis,
        'source': source,
        'reason': reason,
        'createdAt': createdAt.toIso8601String(),
        if (category.isNotEmpty) 'category': category,
        if (questionId.isNotEmpty) 'questionId': questionId,
      };
}

class QuizChange {
  const QuizChange({
    required this.sequence,
    required this.questionId,
    required this.operation,
    required this.changedAt,
  });
  factory QuizChange.fromJson(Map<String, dynamic> json) => QuizChange(
        sequence: asInt(json['sequence'], 0),
        questionId: json['questionId']?.toString() ?? '',
        operation: json['operation']?.toString() ?? 'upsert',
        changedAt: DateTime.tryParse(json['changedAt']?.toString() ?? '') ??
            DateTime.now(),
      );
  final int sequence;
  final String questionId;
  final String operation;
  final DateTime changedAt;
  Map<String, dynamic> toJson(QuizQuestion? question) => {
        'sequence': sequence,
        'questionId': questionId,
        'operation': operation,
        'changedAt': changedAt.toIso8601String(),
        if (question != null && operation == 'upsert')
          'question': question.toJson(),
      };
}

bool quizHasKnownImage(QuizQuestion question) =>
    question.image.trim().isNotEmpty ||
    question.imageSha256.trim().isNotEmpty ||
    question.imagePerceptualHash.trim().isNotEmpty ||
    question.imageRegionHash.trim().isNotEmpty;

bool quizImagesMatch(QuizQuestion a, QuizQuestion b) {
  final aSha = a.imageSha256.trim().toLowerCase();
  final bSha = b.imageSha256.trim().toLowerCase();
  if (aSha.isNotEmpty && bSha.isNotEmpty) return aSha == bSha;
  final aPhash = a.imagePerceptualHash.trim().toLowerCase();
  final bPhash = b.imagePerceptualHash.trim().toLowerCase();
  if (aPhash.isNotEmpty && bPhash.isNotEmpty) return aPhash == bPhash;
  final aRegion = a.imageRegionHash.trim().toLowerCase();
  final bRegion = b.imageRegionHash.trim().toLowerCase();
  if (aRegion.isNotEmpty && bRegion.isNotEmpty) return aRegion == bRegion;
  // Legacy image-only rows cannot prove exact equality; keep old merge behavior.
  return !quizHasKnownImage(a) && !quizHasKnownImage(b);
}

/// 题目内容指纹，用于查重。
///
/// 必须带上正确答案：看图题（「这个标志是何含义？」「这是什么交通标志？」）题干
/// 不含任何区分信息，同一批题的选项集又往往完全一致，只有答案不同。若只用
/// 题干+选项，这些本来不同的题会被误判成重复，导致给其中一道补图时撞上另一道。
/// 加入答案后它们各自独立，而真正的重复题（内容答案全同）依然能被识别。
String quizIdentityKey(
  String question,
  List<String> options, [
  String correctAnswer = '',
]) {
  String clean(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'^[a-dＡ-Ｄ][.．、:：]'), '');
  final normalized = options.map(clean).where((e) => e.isNotEmpty).toList()
    ..sort();
  return '${clean(question)}|${normalized.join('|')}|${clean(correctAnswer)}';
}

enum AccountRole {
  user,
  admin;

  static AccountRole fromWire(String value) =>
      value == 'admin' ? AccountRole.admin : AccountRole.user;

  String get wireName => name;
}

class PluginAuditEvent {
  PluginAuditEvent({
    required this.id,
    required this.action,
    required this.actorUserId,
    required this.actorName,
    required this.pluginId,
    required this.submissionId,
    required this.note,
    required this.createdAt,
  });

  final String id;
  final String action;
  final String actorUserId;
  final String actorName;
  final String pluginId;
  final String submissionId;
  final String note;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'action': action,
        'actorUserId': actorUserId,
        'actorName': actorName,
        'pluginId': pluginId,
        'submissionId': submissionId,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PluginAuditEvent.fromJson(Map<String, dynamic> json) {
    return PluginAuditEvent(
      id: json['id']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      actorUserId: json['actorUserId']?.toString() ?? '',
      actorName: json['actorName']?.toString() ?? '',
      pluginId: json['pluginId']?.toString() ?? '',
      submissionId: json['submissionId']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class PluginSubmission {
  PluginSubmission({
    required this.id,
    required this.pluginId,
    required this.authorUserId,
    required this.authorName,
    required this.title,
    required this.subtitle,
    required this.version,
    required this.minAppVersion,
    required this.areaCode,
    required this.actionCode,
    required this.payload,
    required this.payloadData,
    required this.permissions,
    required this.tags,
    required this.changelog,
    required this.status,
    required this.reviewNote,
    required this.reviewerId,
    required this.createdAt,
    required this.reviewedAt,
    required this.colorValue,
    required this.iconName,
    required this.sort,
    required this.beta,
    this.packagePath = '',
    this.packageSha256 = '',
    this.packageSize = 0,
    this.packageFormat = '',
    this.packageJson = '',
  });

  final String id;
  final String pluginId;
  final String authorUserId;
  final String authorName;
  final String title;
  final String subtitle;
  final String version;
  final String minAppVersion;
  final String areaCode;
  final String actionCode;
  final String payload;
  final Map<String, dynamic> payloadData;
  final List<String> permissions;
  final List<String> tags;
  final String changelog;
  final String status;
  final String reviewNote;
  final String reviewerId;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final int colorValue;
  final String iconName;
  final int sort;
  final bool beta;
  final String packagePath;
  final String packageSha256;
  final int packageSize;
  final String packageFormat;
  final String packageJson;

  PluginSubmission copyWith({
    String? status,
    String? reviewNote,
    String? reviewerId,
    DateTime? reviewedAt,
    String? packagePath,
    String? packageSha256,
    int? packageSize,
    String? packageFormat,
    String? packageJson,
  }) {
    return PluginSubmission(
      id: id,
      pluginId: pluginId,
      authorUserId: authorUserId,
      authorName: authorName,
      title: title,
      subtitle: subtitle,
      version: version,
      minAppVersion: minAppVersion,
      areaCode: areaCode,
      actionCode: actionCode,
      payload: payload,
      payloadData: payloadData,
      permissions: permissions,
      tags: tags,
      changelog: changelog,
      status: status ?? this.status,
      reviewNote: reviewNote ?? this.reviewNote,
      reviewerId: reviewerId ?? this.reviewerId,
      createdAt: createdAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      colorValue: colorValue,
      iconName: iconName,
      sort: sort,
      beta: beta,
      packagePath: packagePath ?? this.packagePath,
      packageSha256: packageSha256 ?? this.packageSha256,
      packageSize: packageSize ?? this.packageSize,
      packageFormat: packageFormat ?? this.packageFormat,
      packageJson: packageJson ?? this.packageJson,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'pluginId': pluginId,
        'authorUserId': authorUserId,
        'authorName': authorName,
        'title': title,
        'subtitle': subtitle,
        'version': version,
        'minAppVersion': minAppVersion,
        'areaCode': areaCode,
        'actionCode': actionCode,
        'payload': payloadData.isEmpty ? payload : payloadData,
        'permissions': permissions,
        'tags': tags,
        'changelog': changelog,
        'status': status,
        'reviewNote': reviewNote,
        'reviewerId': reviewerId,
        'createdAt': createdAt.toIso8601String(),
        'reviewedAt': reviewedAt?.toIso8601String(),
        'colorValue': colorValue,
        'iconName': iconName,
        'sort': sort,
        'beta': beta,
        'packagePath': packagePath,
        'packageSha256': packageSha256,
        'packageSize': packageSize,
        'packageFormat': packageFormat,
        'hasPackage': packagePath.isNotEmpty || packageJson.isNotEmpty,
      };

  factory PluginSubmission.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    final Map<String, dynamic> payloadData;
    final String payload;
    if (rawPayload is Map) {
      payloadData = Map<String, dynamic>.from(rawPayload);
      payload = '';
    } else {
      payloadData = const {};
      payload = rawPayload?.toString() ?? '';
    }
    return PluginSubmission(
      id: json['id']?.toString() ?? '',
      pluginId: json['pluginId']?.toString() ?? '',
      authorUserId: json['authorUserId']?.toString() ?? '',
      authorName: json['authorName']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      version: json['version']?.toString() ?? '1.0.0',
      minAppVersion: json['minAppVersion']?.toString() ?? '',
      areaCode: json['areaCode']?.toString() ?? 'recommend',
      actionCode: json['actionCode']?.toString() ?? 'toast',
      payload: payload,
      payloadData: payloadData,
      permissions: (json['permissions'] is List)
          ? (json['permissions'] as List).map((e) => e.toString()).toList()
          : const <String>[],
      tags: (json['tags'] is List)
          ? (json['tags'] as List).map((e) => e.toString()).toList()
          : const <String>[],
      changelog: json['changelog']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending_review',
      reviewNote: json['reviewNote']?.toString() ?? '',
      reviewerId: json['reviewerId']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      reviewedAt: DateTime.tryParse(json['reviewedAt']?.toString() ?? ''),
      colorValue: asInt(json['colorValue'], 0xFF4F46E5),
      iconName: json['iconName']?.toString() ?? '',
      sort: asInt(json['sort'], 5000),
      beta: json['beta'] == true,
      packagePath: json['packagePath']?.toString() ?? '',
      packageSha256: json['packageSha256']?.toString() ?? '',
      packageSize: asInt(json['packageSize'], 0),
      packageFormat: json['packageFormat']?.toString() ?? '',
      packageJson: json['packageJson']?.toString() ?? '',
    );
  }
}

class MultipartForm {
  MultipartForm({required this.fields, required this.files});
  final Map<String, String> fields;
  final Map<String, List<int>> files;
}

class PluginRelease {
  PluginRelease({
    required this.pluginId,
    required this.version,
    required this.title,
    required this.subtitle,
    required this.authorUserId,
    required this.authorName,
    required this.areaCode,
    required this.actionCode,
    required this.payload,
    required this.payloadData,
    required this.permissions,
    required this.tags,
    required this.changelog,
    required this.minAppVersion,
    required this.status,
    required this.featured,
    required this.beta,
    required this.sort,
    required this.colorValue,
    required this.iconName,
    required this.downloadCount,
    required this.publishedAt,
    required this.submissionId,
    this.yankNote = '',
    this.packageJson = '',
    this.packageSha256 = '',
    this.previousVersions = const [],
    this.packagePath = '',
    this.packageFormat = '',
    this.packageSize = 0,
    this.forceUninstall = false,
  });

  final String pluginId;
  final String version;
  final String title;
  final String subtitle;
  final String authorUserId;
  final String authorName;
  final String areaCode;
  final String actionCode;
  final String payload;
  final Map<String, dynamic> payloadData;
  final List<String> permissions;
  final List<String> tags;
  final String changelog;
  final String minAppVersion;
  final String status;
  final bool featured;
  final bool beta;
  final int sort;
  final int colorValue;
  final String iconName;
  final int downloadCount;
  final DateTime publishedAt;
  final String submissionId;
  final String yankNote;
  final String packageJson;
  final String packageSha256;
  final List<String> previousVersions;
  final String packagePath;
  final String packageFormat;
  final int packageSize;
  final bool forceUninstall;

  PluginRelease copyWith({
    String? status,
    bool? featured,
    String? yankNote,
    int? downloadCount,
    String? packageJson,
    String? packageSha256,
    List<String>? previousVersions,
    String? packagePath,
    String? packageFormat,
    int? packageSize,
    bool? forceUninstall,
  }) {
    return PluginRelease(
      pluginId: pluginId,
      version: version,
      title: title,
      subtitle: subtitle,
      authorUserId: authorUserId,
      authorName: authorName,
      areaCode: areaCode,
      actionCode: actionCode,
      payload: payload,
      payloadData: payloadData,
      permissions: permissions,
      tags: tags,
      changelog: changelog,
      minAppVersion: minAppVersion,
      status: status ?? this.status,
      featured: featured ?? this.featured,
      beta: beta,
      sort: sort,
      colorValue: colorValue,
      iconName: iconName,
      downloadCount: downloadCount ?? this.downloadCount,
      publishedAt: publishedAt,
      submissionId: submissionId,
      yankNote: yankNote ?? this.yankNote,
      packageJson: packageJson ?? this.packageJson,
      packageSha256: packageSha256 ?? this.packageSha256,
      previousVersions: previousVersions ?? this.previousVersions,
      packagePath: packagePath ?? this.packagePath,
      packageFormat: packageFormat ?? this.packageFormat,
      packageSize: packageSize ?? this.packageSize,
      forceUninstall: forceUninstall ?? this.forceUninstall,
    );
  }

  Map<String, dynamic> toMarketJson() => {
        'id': pluginId,
        'title': title,
        'subtitle': subtitle.isEmpty ? '用户投稿 · $authorName' : subtitle,
        'areaCode': areaCode,
        'actionCode': actionCode,
        'payload': payloadData.isEmpty ? payload : payloadData,
        'version': version,
        'minAppVersion': minAppVersion,
        'author': authorName,
        'authorUserId': authorUserId,
        'tags': tags.isEmpty ? ['用户投稿'] : tags,
        'permissions': permissions,
        'deprecated': false,
        'changelog': changelog,
        'sort': featured ? 0 : sort,
        'featured': featured,
        'colorValue': colorValue,
        if (iconName.isNotEmpty) 'iconName': iconName,
        'downloadCount': downloadCount,
        'publishedAt': publishedAt.toIso8601String(),
        'origin': 'user_market',
        'reviewStatus': 'published',
        'packageSha256': packageSha256,
        'previousVersions': previousVersions,
        'packageFormat': packageFormat.isEmpty
            ? (packagePath.isNotEmpty ? 'zip' : 'json')
            : packageFormat,
        'packageSize': packageSize,
        if (packagePath.isNotEmpty)
          'packageUrl': '/api/plugin-market/$pluginId/package',
        'forceUninstall': forceUninstall,
      };

  Map<String, dynamic> toAdminJson() => {
        ...toMarketJson(),
        'status': status,
        'submissionId': submissionId,
        'publishedAt': publishedAt.toIso8601String(),
        'yankNote': yankNote,
        'beta': beta,
        'packageJson': packageJson,
        'packagePath': packagePath,
        'forceUninstall': forceUninstall,
      };

  Map<String, dynamic> toJson() => {
        'pluginId': pluginId,
        'version': version,
        'title': title,
        'subtitle': subtitle,
        'authorUserId': authorUserId,
        'authorName': authorName,
        'areaCode': areaCode,
        'actionCode': actionCode,
        'payload': payloadData.isEmpty ? payload : payloadData,
        'permissions': permissions,
        'tags': tags,
        'changelog': changelog,
        'minAppVersion': minAppVersion,
        'status': status,
        'featured': featured,
        'beta': beta,
        'sort': sort,
        'colorValue': colorValue,
        'iconName': iconName,
        'downloadCount': downloadCount,
        'publishedAt': publishedAt.toIso8601String(),
        'submissionId': submissionId,
        'yankNote': yankNote,
        'packageJson': packageJson,
        'packageSha256': packageSha256,
        'previousVersions': previousVersions,
        'packagePath': packagePath,
        'packageFormat': packageFormat,
        'packageSize': packageSize,
        'forceUninstall': forceUninstall,
      };

  factory PluginRelease.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    final Map<String, dynamic> payloadData;
    final String payload;
    if (rawPayload is Map) {
      payloadData = Map<String, dynamic>.from(rawPayload);
      payload = '';
    } else {
      payloadData = const {};
      payload = rawPayload?.toString() ?? '';
    }
    return PluginRelease(
      pluginId: json['pluginId']?.toString() ?? json['id']?.toString() ?? '',
      version: json['version']?.toString() ?? '1.0.0',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      authorUserId: json['authorUserId']?.toString() ?? '',
      authorName: json['authorName']?.toString() ?? '',
      areaCode: json['areaCode']?.toString() ?? 'recommend',
      actionCode: json['actionCode']?.toString() ?? 'toast',
      payload: payload,
      payloadData: payloadData,
      permissions: (json['permissions'] is List)
          ? (json['permissions'] as List).map((e) => e.toString()).toList()
          : const <String>[],
      tags: (json['tags'] is List)
          ? (json['tags'] as List).map((e) => e.toString()).toList()
          : const <String>[],
      changelog: json['changelog']?.toString() ?? '',
      minAppVersion: json['minAppVersion']?.toString() ?? '',
      status: json['status']?.toString() ?? 'published',
      featured: json['featured'] == true,
      beta: json['beta'] == true,
      sort: asInt(json['sort'], 5000),
      colorValue: asInt(json['colorValue'], 0xFF4F46E5),
      iconName: json['iconName']?.toString() ?? '',
      downloadCount: asInt(json['downloadCount'], 0),
      publishedAt: DateTime.tryParse(json['publishedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      submissionId: json['submissionId']?.toString() ?? '',
      yankNote: json['yankNote']?.toString() ?? '',
      packageJson: json['packageJson']?.toString() ?? '',
      packageSha256: json['packageSha256']?.toString() ?? '',
      previousVersions: (json['previousVersions'] is List)
          ? (json['previousVersions'] as List).map((e) => e.toString()).toList()
          : const <String>[],
      packagePath: json['packagePath']?.toString() ?? '',
      packageFormat: json['packageFormat']?.toString() ?? '',
      packageSize: asInt(json['packageSize'], 0),
      forceUninstall: json['forceUninstall'] == true,
    );
  }
}

class PluginReport {
  PluginReport({
    required this.id,
    required this.pluginId,
    required this.reporterUserId,
    required this.reporterName,
    required this.reason,
    required this.createdAt,
    required this.status,
  });

  final String id;
  final String pluginId;
  final String reporterUserId;
  final String reporterName;
  final String reason;
  final DateTime createdAt;
  final String status;

  Map<String, dynamic> toJson() => {
        'id': id,
        'pluginId': pluginId,
        'reporterUserId': reporterUserId,
        'reporterName': reporterName,
        'reason': reason,
        'createdAt': createdAt.toIso8601String(),
        'status': status,
      };

  factory PluginReport.fromJson(Map<String, dynamic> json) {
    return PluginReport(
      id: json['id']?.toString() ?? '',
      pluginId: json['pluginId']?.toString() ?? '',
      reporterUserId: json['reporterUserId']?.toString() ?? '',
      reporterName: json['reporterName']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      status: json['status']?.toString() ?? 'open',
    );
  }
}

class PluginPolicyState {
  PluginPolicyState({
    required this.version,
    required this.pluginsAllowed,
    required this.globalMessage,
    required this.ttlSec,
    required this.minAppVersion,
    required this.forceLogout,
    required this.plugins,
    required this.userOverrides,
  });

  factory PluginPolicyState.defaults() => PluginPolicyState(
        version: 1,
        pluginsAllowed: true,
        globalMessage: '',
        ttlSec: 300,
        minAppVersion: '',
        forceLogout: false,
        plugins: {
          for (final id in defaultPluginIds)
            id: PluginPolicyItem(
              id: id,
              allowed: true,
              message: '',
              features: defaultFeaturesFor(id),
            ),
        },
        userOverrides: {},
      );

  factory PluginPolicyState.fromJson(Map<String, dynamic> json) {
    final plugins = <String, PluginPolicyItem>{};
    final rawPlugins = json['plugins'];
    if (rawPlugins is Map) {
      rawPlugins.forEach((key, value) {
        if (value is Map) {
          plugins[key.toString()] = PluginPolicyItem.fromJson(
            key.toString(),
            Map<String, dynamic>.from(value),
          );
        }
      });
    }
    for (final id in defaultPluginIds) {
      plugins.putIfAbsent(
        id,
        () => PluginPolicyItem(
          id: id,
          allowed: true,
          message: '',
          features: defaultFeaturesFor(id),
        ),
      );
    }
    final userOverrides = <String, UserPluginOverride>{};
    final rawUsers = json['userOverrides'] ?? json['users'];
    if (rawUsers is Map) {
      rawUsers.forEach((key, value) {
        if (value is Map) {
          userOverrides[key.toString()] = UserPluginOverride.fromJson(
            Map<String, dynamic>.from(value),
          );
        }
      });
    }
    return PluginPolicyState(
      version: asInt(json['version'], 1),
      pluginsAllowed: json['pluginsAllowed'] != false,
      globalMessage: json['globalMessage']?.toString() ??
          json['message']?.toString() ??
          '',
      ttlSec: asInt(json['ttlSec'], 300).clamp(30, 86400),
      minAppVersion: json['minAppVersion']?.toString() ?? '',
      forceLogout: json['forceLogout'] == true,
      plugins: plugins,
      userOverrides: userOverrides,
    );
  }

  static const defaultPluginIds = [
    'builtin_quiz_plugin',
    'builtin_quiz_entry',
    'builtin_quiz_bank_view',
  ];

  static Map<String, bool> defaultFeaturesFor(String pluginId) {
    switch (pluginId) {
      case 'builtin_quiz_plugin':
        return {
          'overlay': true,
          'probe': true,
          'ocr': true,
          'search': true,
        };
      case 'builtin_quiz_entry':
        return {
          'entry': true,
          'probe': true,
          'ocr': true,
        };
      case 'builtin_quiz_bank_view':
        return {
          'view': true,
          'cloud_push': true,
          'cloud_pull': true,
        };
      default:
        return {'use': true};
    }
  }

  int version;
  bool pluginsAllowed;
  String globalMessage;
  int ttlSec;
  String minAppVersion;
  bool forceLogout;
  final Map<String, PluginPolicyItem> plugins;
  final Map<String, UserPluginOverride> userOverrides;

  void bump() => version++;

  void applyAdminPatch(Map<String, dynamic> body) {
    if (body.containsKey('pluginsAllowed')) {
      pluginsAllowed = body['pluginsAllowed'] == true;
    }
    if (body.containsKey('globalMessage') || body.containsKey('message')) {
      globalMessage =
          (body['globalMessage'] ?? body['message'])?.toString() ?? '';
    }
    if (body.containsKey('ttlSec')) {
      ttlSec = asInt(body['ttlSec'], ttlSec).clamp(30, 86400);
    }
    if (body.containsKey('minAppVersion')) {
      minAppVersion = body['minAppVersion']?.toString() ?? '';
    }
    if (body.containsKey('forceLogout')) {
      forceLogout = body['forceLogout'] == true;
    }
    final rawPlugins = body['plugins'];
    if (rawPlugins is Map) {
      rawPlugins.forEach((key, value) {
        final id = key.toString();
        if (value is! Map) return;
        final existing = plugins[id] ??
            PluginPolicyItem(
              id: id,
              allowed: true,
              message: '',
              features: defaultFeaturesFor(id),
            );
        plugins[id] = existing.merged(Map<String, dynamic>.from(value));
      });
    }
    bump();
  }

  void applyUserPatch(String userId, Map<String, dynamic> body) {
    final current = userOverrides[userId] ?? UserPluginOverride.empty();
    userOverrides[userId] = current.merged(body);
    if (userOverrides[userId]!.isEmpty) {
      userOverrides.remove(userId);
    }
    bump();
  }

  String? denialFor({
    required String? userId,
    required String pluginId,
    String? feature,
  }) {
    if (forceLogout) {
      return globalMessage.isNotEmpty ? globalMessage : '需要重新登录';
    }
    if (!pluginsAllowed) {
      return globalMessage.isNotEmpty ? globalMessage : '管理员已禁止使用插件';
    }
    if (userId != null && userId.isNotEmpty) {
      final u = userOverrides[userId];
      if (u != null) {
        if (!u.pluginsAllowed) {
          return u.message.isNotEmpty ? u.message : '账号未授权使用插件';
        }
        if (u.deniedPluginIds.contains(pluginId)) {
          return u.message.isNotEmpty ? u.message : '账号未授权使用该插件';
        }
      }
    }
    final item = plugins[pluginId];
    if (item != null) {
      if (!item.allowed) {
        return item.message.isNotEmpty ? item.message : '该插件已被管理员停用';
      }
      if (feature != null &&
          feature.isNotEmpty &&
          item.features.containsKey(feature) &&
          item.features[feature] == false) {
        return item.message.isNotEmpty ? item.message : '该功能已被管理员停用';
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'pluginsAllowed': pluginsAllowed,
        'globalMessage': globalMessage,
        'ttlSec': ttlSec,
        'minAppVersion': minAppVersion,
        'forceLogout': forceLogout,
        'plugins': plugins.map((k, v) => MapEntry(k, v.toJson())),
        'userOverrides': userOverrides.map((k, v) => MapEntry(k, v.toJson())),
      };

  Map<String, dynamic> toClientJson(String? userId) {
    final u = (userId == null || userId.isEmpty) ? null : userOverrides[userId];
    return {
      'version': version,
      'ttlSec': ttlSec,
      'minAppVersion': minAppVersion,
      'forceLogout': forceLogout,
      'global': {
        'pluginsAllowed': pluginsAllowed,
        'message': globalMessage,
      },
      'plugins': {
        for (final e in plugins.entries)
          e.key: {
            'allowed': e.value.allowed,
            'message': e.value.message,
            'features': e.value.features,
          },
      },
      'user': {
        'pluginsAllowed': u?.pluginsAllowed ?? true,
        'deniedPluginIds': u?.deniedPluginIds.toList() ?? <String>[],
        'message': u?.message ?? '',
      },
      'serverTime': DateTime.now().toIso8601String(),
    };
  }

  Map<String, dynamic> toAdminJson(Map<String, Account> accounts) {
    return {
      ...toJson(),
      'userOverridesDetailed': userOverrides.map((userId, value) {
        final acc = accounts[userId];
        return MapEntry(userId, {
          ...value.toJson(),
          'username': acc?.username ?? '',
        });
      }),
    };
  }

  Map<String, dynamic> userOverrideJson(String userId) =>
      (userOverrides[userId] ?? UserPluginOverride.empty()).toJson();
}

class PluginPolicyItem {
  PluginPolicyItem({
    required this.id,
    required this.allowed,
    required this.message,
    required this.features,
  });

  factory PluginPolicyItem.fromJson(String id, Map<String, dynamic> json) {
    final features = <String, bool>{
      ...PluginPolicyState.defaultFeaturesFor(id),
    };
    final rawFeatures = json['features'];
    if (rawFeatures is Map) {
      rawFeatures.forEach((key, value) {
        features[key.toString()] = value == true;
      });
    }
    return PluginPolicyItem(
      id: id,
      allowed: json['allowed'] != false,
      message: json['message']?.toString() ?? '',
      features: features,
    );
  }

  final String id;
  bool allowed;
  String message;
  Map<String, bool> features;

  PluginPolicyItem merged(Map<String, dynamic> patch) {
    if (patch.containsKey('allowed')) {
      allowed = patch['allowed'] == true;
    }
    if (patch.containsKey('message')) {
      message = patch['message']?.toString() ?? '';
    }
    final rawFeatures = patch['features'];
    if (rawFeatures is Map) {
      rawFeatures.forEach((key, value) {
        features[key.toString()] = value == true;
      });
    }
    return this;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'allowed': allowed,
        'message': message,
        'features': features,
      };
}

class UserPluginOverride {
  UserPluginOverride({
    required this.pluginsAllowed,
    required this.deniedPluginIds,
    required this.message,
  });

  factory UserPluginOverride.empty() => UserPluginOverride(
        pluginsAllowed: true,
        deniedPluginIds: {},
        message: '',
      );

  factory UserPluginOverride.fromJson(Map<String, dynamic> json) {
    final denied = <String>{};
    final raw = json['deniedPluginIds'] ?? json['denied'];
    if (raw is List) {
      for (final item in raw) {
        final id = item.toString().trim();
        if (id.isNotEmpty) denied.add(id);
      }
    }
    return UserPluginOverride(
      pluginsAllowed: json['pluginsAllowed'] != false,
      deniedPluginIds: denied,
      message: json['message']?.toString() ?? '',
    );
  }

  bool pluginsAllowed;
  Set<String> deniedPluginIds;
  String message;

  bool get isEmpty =>
      pluginsAllowed && deniedPluginIds.isEmpty && message.trim().isEmpty;

  UserPluginOverride merged(Map<String, dynamic> patch) {
    if (patch.containsKey('pluginsAllowed')) {
      pluginsAllowed = patch['pluginsAllowed'] == true;
    }
    if (patch.containsKey('message')) {
      message = patch['message']?.toString() ?? '';
    }
    if (patch.containsKey('deniedPluginIds') || patch.containsKey('denied')) {
      deniedPluginIds = {};
      final raw = patch['deniedPluginIds'] ?? patch['denied'];
      if (raw is List) {
        for (final item in raw) {
          final id = item.toString().trim();
          if (id.isNotEmpty) deniedPluginIds.add(id);
        }
      }
    }
    return this;
  }

  Map<String, dynamic> toJson() => {
        'pluginsAllowed': pluginsAllowed,
        'deniedPluginIds': deniedPluginIds.toList()..sort(),
        'message': message,
      };
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
    this.nickname,
  });

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: json['id']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        passwordHash: json['passwordHash']?.toString() ?? '',
        role: AccountRole.fromWire(json['role']?.toString() ?? 'user'),
        status: json['status']?.toString() ?? 'normal',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        lastLoginAt: DateTime.tryParse(json['lastLoginAt']?.toString() ?? ''),
        nickname: json['nickname']?.toString(),
      );

  final String id;
  final String username;
  String? nickname;
  String passwordHash;
  AccountRole role;
  String status;
  final DateTime createdAt;
  DateTime? lastLoginAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        if (nickname != null) 'nickname': nickname,
        'passwordHash': passwordHash,
        'role': role.wireName,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
        'lastLoginAt': lastLoginAt?.toIso8601String(),
      };

  Map<String, dynamic> toPublicJson() => {
        'id': id,
        'username': username,
        'nickname': nickname ?? username,
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
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? '') ??
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
  ) =>
      UsageRecord(
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
  ) =>
      UsageRecord(
        createdAt: DateTime.now(),
        userId: userId,
        model: model,
        cost: cost,
        success: false,
        statusCode: statusCode,
        errorPreview: preview,
      );

  factory UsageRecord.fromJson(Map<String, dynamic> json) => UsageRecord(
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
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
        baseUrl:
            (json['baseUrl']?.toString() ?? '').replaceAll(RegExp(r'/+$'), ''),
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

// ── AI 读屏代理（新增） ──

/// 每账号每日读屏代理请求上限（防滥用；内存计数重启清零，作启发式足够）。
/// 调小=更防白嫖但易误伤；调大=更宽松。
const int quizVisionDailyCap = 100;

/// A3 突发限流：每账号每分钟允许的读屏请求数（滑动窗口）。
/// 读屏单次 3–16s，正常使用远低于此；调大=更宽松。
const int quizVisionBurstCap = 20;

class QuizVisionProviderConfig {
  const QuizVisionProviderConfig({
    required this.baseUrl,
    required this.apiKeyCipher,
    required this.model,
    required this.enabled,
    required this.updatedAt,
  });

  factory QuizVisionProviderConfig.fromJson(Map<String, dynamic> json) =>
      QuizVisionProviderConfig(
        baseUrl:
            (json['baseUrl']?.toString() ?? '').replaceAll(RegExp(r'/+$'), ''),
        apiKeyCipher: json['apiKeyCipher']?.toString() ?? '',
        model: json['model']?.toString() ?? '',
        enabled: json['enabled'] == true,
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      );

  final String baseUrl;
  final String apiKeyCipher;
  final String model;
  final bool enabled;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'apiKeyCipher': apiKeyCipher,
        'model': model,
        'enabled': enabled,
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

/// 取请求的真实客户端 IP。
///
/// 安全要点：仅当 TCP 对端是回环地址（即请求来自本机 Nginx 反代）时才读取
/// X-Forwarded-For，且必须取**最右边**的值。因为 Nginx 的
/// `$proxy_add_x_forwarded_for` 展开为 "$http_x_forwarded_for, $remote_addr"，
/// 最左边的值是客户端自己塞进来的、可任意伪造，只有最右边那个是 Nginx
/// 亲自追加的真实 remote_addr。取最左边会导致限速被伪造头绕过。
String clientIp(HttpRequest request) {
  final peer = request.connectionInfo?.remoteAddress;
  final peerHost = peer?.address ?? 'unknown';
  final isLoopback = peer?.isLoopback ?? false;
  if (isLoopback) {
    final xff = request.headers.value('x-forwarded-for');
    if (xff != null && xff.trim().isNotEmpty) {
      final parts = xff
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (parts.isNotEmpty) return parts.last;
    }
  }
  return peerHost;
}

/// 登录失败节流：按「用户名」和「来源 IP」两个维度分别计数并临时锁定。
///
/// 之所以两个维度都要：只按 IP 挡不住分布式撞库，只按用户名会被人拿来
/// 恶意锁死他人账号。任一维度触发即拒绝，锁定期用 429 + Retry-After 返回。
class LoginThrottle {
  LoginThrottle({
    this.maxFailures = 8,
    this.windowSeconds = 600,
    this.lockoutSeconds = 900,
  });

  final int maxFailures;
  final int windowSeconds;
  final int lockoutSeconds;

  final Map<String, List<DateTime>> _failures = {};
  final Map<String, DateTime> _lockedUntil = {};

  void _prune(String key, DateTime now) {
    final list = _failures[key];
    if (list == null) return;
    list.removeWhere(
      (t) => now.difference(t).inSeconds > windowSeconds,
    );
    if (list.isEmpty) _failures.remove(key);
  }

  /// 返回剩余锁定秒数；未锁定返回 null。
  int? retryAfterSeconds(List<String> keys) {
    final now = DateTime.now();
    var worst = 0;
    for (final key in keys) {
      final until = _lockedUntil[key];
      if (until == null) continue;
      if (until.isAfter(now)) {
        final remain = until.difference(now).inSeconds + 1;
        if (remain > worst) worst = remain;
      } else {
        _lockedUntil.remove(key);
      }
    }
    return worst > 0 ? worst : null;
  }

  void registerFailure(List<String> keys) {
    final now = DateTime.now();
    for (final key in keys) {
      _prune(key, now);
      final list = _failures.putIfAbsent(key, () => <DateTime>[]);
      list.add(now);
      if (list.length >= maxFailures) {
        _lockedUntil[key] = now.add(Duration(seconds: lockoutSeconds));
        _failures.remove(key);
      }
    }
  }

  void registerSuccess(List<String> keys) {
    for (final key in keys) {
      _failures.remove(key);
      _lockedUntil.remove(key);
    }
  }
}

/// PBKDF2-HMAC-SHA256 实现（纯 Dart，不加外部依赖）。
///
/// 参数：100_000 轮、32 字节输出，与 OWASP 2023 推荐最低值对齐。
/// 格式：`pbkdf2:<hex-salt-16B>:<hex-dk-32B>`，与旧 `sha256:` 格式共存，
/// 由 verifyPassword 自动识别。
List<int> _pbkdf2(List<int> password, List<int> salt,
    {int iterations = 100000, int dkLen = 32}) {
  final hmac = Hmac(sha256, password);
  // PRF(P, S || INT(i))，i=1（dkLen≤32 只需一个 block）
  final u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final t = List<int>.from(u);
  var prev = u;
  for (var c = 1; c < iterations; c++) {
    final next = hmac.convert(prev).bytes;
    for (var j = 0; j < dkLen; j++) {
      t[j] ^= next[j];
    }
    prev = next;
  }
  return t.sublist(0, dkLen);
}

String hashPassword(String password) {
  final saltBytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  final dk = _pbkdf2(utf8.encode(password), saltBytes);
  final saltHex =
      saltBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final dkHex = dk.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return 'pbkdf2:$saltHex:$dkHex';
}

bool verifyPassword(String password, String stored) {
  final parts = stored.split(':');
  if (parts.length != 3) return false;

  if (parts[0] == 'pbkdf2') {
    // 新格式
    final saltBytes = List<int>.generate(
      parts[1].length ~/ 2,
      (i) => int.parse(parts[1].substring(i * 2, i * 2 + 2), radix: 16),
    );
    final dk = _pbkdf2(utf8.encode(password), saltBytes);
    final dkHex = dk.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    // constant-time 比较，防止时序攻击
    return _constantTimeEquals(dkHex, parts[2]);
  }

  if (parts[0] == 'sha256') {
    // 旧格式：验证通过后调用方负责迁移（见 login() 中的 migrateHash）
    final digest =
        sha256.convert(utf8.encode('${parts[1]}:$password')).toString();
    return digest == parts[2];
  }

  return false;
}

/// constant-time 字符串比较，防止时序侧信道泄露哈希前缀。
bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
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
) =>
    {
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
  final needsQuotes = text.contains(',') ||
      text.contains('"') ||
      text.contains('\n') ||
      text.contains('\r');
  final escaped = text.replaceAll('"', '""');
  return needsQuotes ? '"$escaped"' : escaped;
}

/// 书源身份键：忽略协议、大小写与末尾斜杠，同一站点视为同一书源。
String bookSourceUrlKey(String url) {
  var value = url.trim().toLowerCase();
  value = value.replaceFirst(RegExp(r'^https?://'), '');
  while (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
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
  final result = raw
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
  final models = data
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
  response.headers
      .set('Access-Control-Allow-Origin', 'https://background.hpa888.top');
  response.headers.set(
    'Access-Control-Allow-Headers',
    'Content-Type, Authorization, X-User-Id, X-Admin-Token',
  );
  response.headers.set(
    'Access-Control-Allow-Methods',
    'GET, POST, PUT, DELETE, OPTIONS',
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
