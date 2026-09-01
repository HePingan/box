import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/public_api_models.dart';

class ApiHubException implements Exception {
  const ApiHubException(this.message);
  final String message;

  @override
  String toString() => message;
}

class PublicApiClient {
  PublicApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  void dispose() => _client.close();

  Future<List<PublicBookResult>> searchOpenLibrary(String query) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return const [];

    final uri = Uri.https('openlibrary.org', '/search.json', {
      'q': keyword,
      'limit': '12',
      'fields': 'key,title,author_name,first_publish_year,cover_i',
    });
    final json = await _getJson(uri);
    final docs = json['docs'];
    if (docs is! List) return const [];

    return docs.whereType<Map>().map((raw) {
      final authors = raw['author_name'];
      return PublicBookResult(
        title: _string(raw['title'], '未命名书籍'),
        author: authors is List && authors.isNotEmpty
            ? authors.take(2).join(' / ')
            : '作者未知',
        year: raw['first_publish_year'] is num
            ? (raw['first_publish_year'] as num).toInt()
            : null,
        coverId: raw['cover_i'] is num ? (raw['cover_i'] as num).toInt() : null,
        key: _string(raw['key']),
      );
    }).toList();
  }

  Future<Map<String, double>> latestRates({
    String base = 'USD',
    List<String> symbols = const ['CNY', 'EUR', 'JPY', 'HKD'],
  }) async {
    final uri = Uri.https('api.frankfurter.app', '/latest', {
      'from': base.toUpperCase(),
      'to': symbols.map((e) => e.toUpperCase()).join(','),
    });
    final json = await _getJson(uri);
    final rates = json['rates'];
    if (rates is! Map) return const {};
    // 逐币种判型：免费接口偶发把某个币种返回成 null 或字符串，
    // 裸 `as num` 会让整张汇率表连带失败。这里跳过坏字段，保住其余币种。
    final result = <String, double>{};
    rates.forEach((key, value) {
      if (value is num) {
        result[key.toString()] = value.toDouble();
      }
    });
    return result;
  }

  Future<double?> convertCurrency({
    required double amount,
    required String from,
    required String to,
  }) async {
    if (from.toUpperCase() == to.toUpperCase()) return amount;
    final uri = Uri.https('api.frankfurter.app', '/latest', {
      'amount': amount.toString(),
      'from': from.toUpperCase(),
      'to': to.toUpperCase(),
    });
    final json = await _getJson(uri);
    final rates = json['rates'];
    if (rates is Map && rates[to.toUpperCase()] is num) {
      return (rates[to.toUpperCase()] as num).toDouble();
    }
    return null;
  }

  Future<List<HolidayResult>> publicHolidays({
    required int year,
    String countryCode = 'CN',
  }) async {
    final uri = Uri.https(
      'date.nager.at',
      '/api/v3/PublicHolidays/$year/${countryCode.toUpperCase()}',
    );
    final decoded = await _getDecoded(uri);
    if (decoded is! List) return const [];
    return decoded.whereType<Map>().map((raw) {
      return HolidayResult(
        date: _string(raw['date']),
        localName: _string(raw['localName']),
        name: _string(raw['name']),
        countryCode: _string(raw['countryCode'], countryCode.toUpperCase()),
      );
    }).toList();
  }

  Future<WeatherForecastResult> weatherForecast({
    required double latitude,
    required double longitude,
    int days = 3,
  }) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toStringAsFixed(4),
      'longitude': longitude.toStringAsFixed(4),
      'current': 'temperature_2m,wind_speed_10m',
      'daily': 'weather_code,temperature_2m_max,temperature_2m_min',
      'forecast_days': days.clamp(1, 7).toString(),
      'timezone': 'auto',
    });
    final json = await _getJson(uri);
    final current = json['current'];
    final daily = json['daily'];
    final times = daily is Map && daily['time'] is List
        ? daily['time'] as List
        : [];
    final maxValues = daily is Map && daily['temperature_2m_max'] is List
        ? daily['temperature_2m_max'] as List
        : [];
    final minValues = daily is Map && daily['temperature_2m_min'] is List
        ? daily['temperature_2m_min'] as List
        : [];
    final codes = daily is Map && daily['weather_code'] is List
        ? daily['weather_code'] as List
        : [];

    return WeatherForecastResult(
      latitude: _double(json['latitude']) ?? latitude,
      longitude: _double(json['longitude']) ?? longitude,
      timezone: _string(json['timezone'], 'auto'),
      currentTemperature: current is Map
          ? _double(current['temperature_2m'])
          : null,
      currentWindSpeed: current is Map
          ? _double(current['wind_speed_10m'])
          : null,
      daily: List.generate(times.length.clamp(0, 7), (index) {
        return WeatherDailyResult(
          date: _string(times[index]),
          maxTemperature: index < maxValues.length
              ? _double(maxValues[index])
              : null,
          minTemperature: index < minValues.length
              ? _double(minValues[index])
              : null,
          weatherCode: index < codes.length && codes[index] is num
              ? (codes[index] as num).toInt()
              : null,
        );
      }),
    );
  }

  Future<DictionaryResult?> dictionaryLookup(String word) async {
    final keyword = word.trim();
    if (keyword.isEmpty) return null;
    final uri = Uri.https(
      'api.dictionaryapi.dev',
      '/api/v2/entries/en/$keyword',
    );
    final decoded = await _getDecoded(uri);
    if (decoded is! List || decoded.isEmpty || decoded.first is! Map) {
      return null;
    }
    final raw = decoded.first as Map;
    final meanings = raw['meanings'];
    return DictionaryResult(
      word: _string(raw['word'], keyword),
      phonetic: _string(raw['phonetic']),
      meanings: meanings is List
          ? meanings
                .whereType<Map>()
                .expand((meaning) {
                  final definitions = meaning['definitions'];
                  if (definitions is! List) {
                    return const <DictionaryMeaningResult>[];
                  }
                  return definitions.whereType<Map>().take(2).map((definition) {
                    return DictionaryMeaningResult(
                      partOfSpeech: _string(meaning['partOfSpeech']),
                      definition: _string(definition['definition']),
                      example: _string(definition['example']),
                    );
                  });
                })
                .take(6)
                .toList()
          : const [],
    );
  }

  Future<IpInfoResult> currentIpInfo() async {
    final uri = Uri.https('ipinfo.io', '/json');
    final json = await _getJson(uri);
    return IpInfoResult(
      ip: _string(json['ip'], '未知 IP'),
      city: _string(json['city']),
      region: _string(json['region']),
      country: _string(json['country']),
      org: _string(json['org']),
      timezone: _string(json['timezone']),
    );
  }

  Future<ShortLinkResult> shortenUrl(String url) async {
    final original = url.trim();
    if (original.isEmpty || Uri.tryParse(original)?.hasAbsolutePath != true) {
      throw const ApiHubException('请输入完整 URL，例如 https://example.com');
    }
    final uri = Uri.https('cleanuri.com', '/api/v1/shorten');
    final decoded = await _postDecoded(uri, {'url': original});
    if (decoded is! Map) {
      throw const ApiHubException('短链接接口返回格式异常');
    }
    final shortUrl = _string(decoded['result_url']);
    if (shortUrl.isEmpty) {
      throw ApiHubException(_string(decoded['error'], '短链接生成失败'));
    }
    return ShortLinkResult(originalUrl: original, shortUrl: shortUrl);
  }

  QrCodeResult buildQrCode({required String text, required String size}) {
    final label = text.trim().isEmpty ? 'https://example.com' : text.trim();
    final normalizedSize = RegExp(r'^\d{2,4}x\d{2,4}$').hasMatch(size.trim())
        ? size.trim()
        : '220x220';
    return QrCodeResult(
      url: Uri.https('api.qrserver.com', '/v1/create-qr-code/', {
        'size': normalizedSize,
        'data': label,
      }).toString(),
      size: normalizedSize,
      text: label,
    );
  }

  AvatarResult buildAvatar({
    required String name,
    required String background,
    required String foreground,
    required String size,
  }) {
    final label = name.trim().isEmpty ? 'Box API' : name.trim();
    final parsedSize = int.tryParse(size.trim())?.clamp(64, 512) ?? 256;
    final bg = _hex(background, fallback: '2563eb');
    final fg = _hex(foreground, fallback: 'ffffff');
    return AvatarResult(
      url: Uri.https('ui-avatars.com', '/api/', {
        'name': label,
        'background': bg,
        'color': fg,
        'size': parsedSize.toString(),
        'bold': 'true',
        'format': 'png',
      }).toString(),
      name: label,
      background: bg,
      foreground: fg,
      size: parsedSize,
    );
  }

  CoverImageResult buildCoverImage({
    required String width,
    required String height,
    required String seed,
  }) {
    final parsedWidth = int.tryParse(width.trim())?.clamp(120, 1920) ?? 640;
    final parsedHeight = int.tryParse(height.trim())?.clamp(120, 1920) ?? 360;
    final cleanSeed = seed.trim().isEmpty
        ? DateTime.now().millisecondsSinceEpoch.toString()
        : seed.trim();
    return CoverImageResult(
      url: Uri.https(
        'picsum.photos',
        '/seed/$cleanSeed/$parsedWidth/$parsedHeight',
      ).toString(),
      width: parsedWidth,
      height: parsedHeight,
      seed: cleanSeed,
    );
  }

  DummyImageResult buildDummyImage({
    required String size,
    required String background,
    required String foreground,
    required String text,
  }) {
    final normalizedSize = RegExp(r'^\d{2,4}x\d{2,4}$').hasMatch(size.trim())
        ? size.trim()
        : '600x360';
    final bg = _hex(background, fallback: '2563eb');
    final fg = _hex(foreground, fallback: 'ffffff');
    final label = text.trim().isEmpty ? 'Box API Hub' : text.trim();
    final encodedText = Uri.encodeComponent(label).replaceAll('%20', '+');
    return DummyImageResult(
      url:
          'https://dummyimage.com/$normalizedSize/$bg/$fg.png&text=$encodedText',
      size: normalizedSize,
      background: bg,
      foreground: fg,
      text: label,
    );
  }

  Future<List<MockUserResult>> mockUsers({int limit = 8}) async {
    final uri = Uri.https('dummyjson.com', '/users', {
      'limit': limit.clamp(1, 20).toString(),
      'select': 'firstName,lastName,username,email,phone,address,company,image',
    });
    final json = await _getJson(uri);
    final users = json['users'];
    if (users is! List) return const [];
    return users.whereType<Map>().map((raw) {
      final address = raw['address'];
      final company = raw['company'];
      final firstName = _string(raw['firstName']);
      final lastName = _string(raw['lastName']);
      return MockUserResult(
        fullName: [
          firstName,
          lastName,
        ].where((e) => e.isNotEmpty).join(' ').trim(),
        username: _string(raw['username']),
        email: _string(raw['email']),
        phone: _string(raw['phone']),
        city: address is Map ? _string(address['city']) : '',
        company: company is Map ? _string(company['name']) : '',
        image: _string(raw['image']),
      );
    }).toList();
  }

  Future<List<MockProductResult>> mockProducts({int limit = 8}) async {
    final uri = Uri.https('dummyjson.com', '/products', {
      'limit': limit.clamp(1, 20).toString(),
      'select': 'title,brand,price,category,thumbnail',
    });
    final json = await _getJson(uri);
    final products = json['products'];
    if (products is! List) return const [];
    return products.whereType<Map>().map((raw) {
      return MockProductResult(
        title: _string(raw['title'], 'Untitled'),
        brand: _string(raw['brand'], 'No brand'),
        price: _double(raw['price']) ?? 0,
        category: _string(raw['category']),
        thumbnail: _string(raw['thumbnail']),
      );
    }).toList();
  }

  Future<List<SpaceflightNewsResult>> spaceflightNews({int limit = 6}) async {
    final uri = Uri.https('api.spaceflightnewsapi.net', '/v4/articles', {
      'limit': limit.clamp(1, 20).toString(),
    });
    final json = await _getJson(uri);
    final results = json['results'];
    if (results is! List) return const [];
    return results.whereType<Map>().map((raw) {
      return SpaceflightNewsResult(
        title: _string(raw['title'], 'Untitled'),
        summary: _string(raw['summary']),
        url: _string(raw['url']),
        publishedAt: _string(raw['published_at']),
      );
    }).toList();
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final decoded = await _getDecoded(uri);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const ApiHubException('接口返回格式不是 JSON 对象');
  }

  Future<dynamic> _getDecoded(Uri uri) async {
    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiHubException('接口请求失败：HTTP ${response.statusCode}');
      }
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (e) {
      if (e is ApiHubException) rethrow;
      throw ApiHubException('网络请求失败：$e');
    }
  }

  Future<dynamic> _postDecoded(Uri uri, Map<String, String> body) async {
    try {
      final response = await _client
          .post(uri, body: body)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiHubException('接口请求失败：HTTP ${response.statusCode}');
      }
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (e) {
      if (e is ApiHubException) rethrow;
      throw ApiHubException('网络请求失败：$e');
    }
  }

  String _string(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  String _hex(String value, {required String fallback}) {
    final cleaned = value.replaceAll('#', '').trim().toLowerCase();
    if (RegExp(r'^[0-9a-f]{3}([0-9a-f]{3})?$').hasMatch(cleaned)) {
      return cleaned;
    }
    return fallback;
  }

  double? _double(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
