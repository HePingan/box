import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const _host = '127.0.0.1';
const _port = 8787;

const _models = [
  'gpt-image-1',
  'dall-e-3',
  'flux-dev',
  'stable-diffusion-xl',
  'text-embedding-3-small',
];

// 1x1 transparent PNG.
const _transparentPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';

Future<void> main(List<String> args) async {
  final port = _readPort(args) ?? _port;
  final server = await HttpServer.bind(_host, port);
  stdout.writeln('AI image platform quota mock server running:');
  stdout.writeln('  http://$_host:$port');
  stdout.writeln('Endpoints:');
  stdout.writeln('  GET  /api/image/quota');
  stdout.writeln('  GET  /api/image/models');
  stdout.writeln('  POST /api/image/generate');

  await for (final request in server) {
    try {
      await _handle(request);
    } catch (error, stackTrace) {
      stderr.writeln('Request failed: $error');
      stderr.writeln(stackTrace);
      await _json(request.response, HttpStatus.internalServerError, {
        'error': {'message': 'Mock server error: $error'},
      });
    }
  }
}

int? _readPort(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--port' && i + 1 < args.length) {
      return int.tryParse(args[i + 1]);
    }
    if (arg.startsWith('--port=')) {
      return int.tryParse(arg.substring('--port='.length));
    }
  }
  final envPort = Platform.environment['PORT'];
  return envPort == null ? null : int.tryParse(envPort);
}

Future<void> _handle(HttpRequest request) async {
  _cors(request.response);
  final path = request.uri.path;
  stdout.writeln('${DateTime.now().toIso8601String()} ${request.method} $path');

  if (request.method == 'OPTIONS') {
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
    return;
  }

  if (request.method == 'GET' && path == '/api/image/quota') {
    await _quota(request.response);
    return;
  }

  if (request.method == 'GET' && path == '/api/image/models') {
    await _modelsResponse(request.response);
    return;
  }

  if (request.method == 'POST' && path == '/api/image/generate') {
    await _generate(request);
    return;
  }

  await _json(request.response, HttpStatus.notFound, {
    'error': {'message': 'Mock endpoint not found: $path'},
  });
}

Future<void> _quota(HttpResponse response) {
  return _json(response, HttpStatus.ok, {
    'remaining': 20,
    'dailyLimit': 30,
    'usedToday': 10,
    'totalLimit': 100,
    'status': 'normal',
    'message': 'Mock：今日剩余 20 次，生成成功后前端会刷新这里。',
  });
}

Future<void> _modelsResponse(HttpResponse response) {
  return _json(response, HttpStatus.ok, {'models': _models});
}

Future<void> _generate(HttpRequest request) async {
  final raw = await utf8.decoder.bind(request).join();
  final decoded = raw.trim().isEmpty ? <String, dynamic>{} : jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    await _json(request.response, HttpStatus.badRequest, {
      'error': {'message': 'Request body must be a JSON object'},
    });
    return;
  }

  final prompt = decoded['prompt']?.toString().trim() ?? '';
  if (prompt.isEmpty) {
    await _json(request.response, HttpStatus.badRequest, {
      'error': {'message': 'Prompt 不能为空'},
    });
    return;
  }

  final model = decoded['model']?.toString().trim().isEmpty ?? true
      ? 'gpt-image-1'
      : decoded['model'].toString().trim();
  final n = _asInt(decoded['n'], 1).clamp(1, 4);
  final data = List.generate(n, (index) {
    return {
      'b64_json': _transparentPngBase64,
      'revised_prompt': 'Mock revised prompt #${index + 1}: $prompt ($model)',
    };
  });

  await Future<void>.delayed(const Duration(milliseconds: 300));
  await _json(request.response, HttpStatus.ok, {'data': data});
}

int _asInt(dynamic value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

void _cors(HttpResponse response) {
  response.headers.set('Access-Control-Allow-Origin', '*');
  response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  response.headers.set(
    'Access-Control-Allow-Headers',
    'Content-Type, Authorization',
  );
}

Future<void> _json(
  HttpResponse response,
  int statusCode,
  Map<String, dynamic> body,
) async {
  _cors(response);
  response.statusCode = statusCode;
  response.headers.contentType = ContentType.json;
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(body)));
  response.contentLength = bytes.length;
  response.add(bytes);
  await response.close();
}
