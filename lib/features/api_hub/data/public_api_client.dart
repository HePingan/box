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

  /// 随机一言。免密钥、无 quota；本轮实测 5/5 成功。
  Future<HitokotoResult> randomHitokoto() async {
    final uri = Uri.https('v1.hitokoto.cn', '/');
    final json = await _getJson(uri);
    return HitokotoResult(
      text: _string(json['hitokoto']),
      from: _string(json['from']),
      fromWho: _string(json['from_who']),
      type: _string(json['type']),
    );
  }

  /// 今日诗词。免密钥；本轮实测 5/5 成功，响应 0.1~0.3s。
  ///
  /// 这个接口把状态放在 body 的 `status` 字段里，HTTP 码仍是 200，
  /// 所以失败要单独判 —— 只看 status code 会把错误当成功。
  Future<PoetryResult> randomPoetry() async {
    final uri = Uri.https('v2.jinrishici.com', '/one.json');
    final json = await _getJson(uri);

    final status = _string(json['status']);
    if (status.isNotEmpty && status != 'success') {
      throw ApiHubException(_string(json['errMessage'], '诗词接口返回失败：$status'));
    }

    final data = json['data'];
    if (data is! Map) {
      throw const ApiHubException('诗词接口返回格式异常');
    }
    final origin = data['origin'];
    final originMap = origin is Map ? origin : const {};

    return PoetryResult(
      content: _string(data['content']),
      title: _string(originMap['title']),
      dynasty: _string(originMap['dynasty']),
      author: _string(originMap['author']),
      fullPoem: _stringList(originMap['content']),
      translation: _stringList(originMap['translate']),
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final decoded = await _getDecoded(uri);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const ApiHubException('接口返回格式不是 JSON 对象');
  }

  // ——————————————————————————————————————————————————————————
  // A-1 本轮接线：以下接口全部经 tool/probe_60s.sh 实测（间隔 4s × 3 次，均 3/3）。
  // 60s.viki.moe/v2 系列统一外壳 { code, msg, data }，成功码 200。
  // ——————————————————————————————————————————————————————————

  /// 60s 系列公共解析：校验外壳码并取出 `data`。
  ///
  /// 这个接口失败时 HTTP 仍可能是 200，把错误放在 body 的 `code` 里
  /// （例如限流），只看 status code 会把错误当成功。
  Map<String, dynamic> _unwrap60s(Map<String, dynamic> json) {
    final code = json['code'];
    if (code is int && code != 200) {
      final msg = _string(json['msg'], '接口返回失败：code=$code');
      throw ApiHubException(msg);
    }
    final data = json['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const ApiHubException('接口返回格式异常：缺少 data 对象');
  }

  List<dynamic> _unwrap60sList(Map<String, dynamic> json) {
    final code = json['code'];
    if (code is int && code != 200) {
      final msg = _string(json['msg'], '接口返回失败：code=$code');
      throw ApiHubException(msg);
    }
    final data = json['data'];
    if (data is List) return data;
    throw const ApiHubException('接口返回格式异常：缺少 data 列表');
  }

  /// 每日英语（金山词霸 dsapi）。免密钥，实测 3/3。
  Future<DailyEnglishResult> dailyEnglish() async {
    final uri = Uri.https('open.iciba.com', '/dsapi/');
    final json = await _getJson(uri);
    return DailyEnglishResult(
      content: _string(json['content']),
      note: _string(json['note']),
      picture: _string(json['picture']),
      picture2: _string(json['picture2']),
      translation: _string(json['translation']),
    );
  }

  /// 每日 60 秒资讯。免密钥，实测 3/3。
  Future<News60sResult> news60s() async {
    final uri = Uri.https('60s.viki.moe', '/v2/60s');
    final data = _unwrap60s(await _getJson(uri));
    final rawNews = data['news'];
    final items = <String>[];
    if (rawNews is List) {
      for (final item in rawNews) {
        if (item is Map) {
          final title = _string(item['title']);
          if (title.isNotEmpty) items.add(title);
        } else if (item is String && item.isNotEmpty) {
          items.add(item);
        }
      }
    }
    final tip = data['tip'];
    final tips = <String>[];
    if (tip is List) {
      for (final t in tip) {
        final s = _string(t);
        if (s.isNotEmpty) tips.add(s);
      }
    }
    return News60sResult(
      date: _string(data['date']),
      items: items,
      tips: tips,
      dayOfWeek: _string(data['day_of_week']),
      lunarDate: _string(data['lunar_date']),
    );
  }

  /// 历史上的今天。免密钥，实测 3/3（当天返回 15 条）。
  Future<List<HistoryEventResult>> todayInHistory() async {
    final uri = Uri.https('60s.viki.moe', '/v2/today_in_history');
    final data = _unwrap60s(await _getJson(uri));
    final items = data['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((raw) {
          return HistoryEventResult(
            year: _string(raw['year']),
            title: _string(raw['title']),
            description: _string(raw['description']),
            link: _string(raw['link']),
          );
        })
        .where((e) => e.title.isNotEmpty)
        .toList();
  }

  /// 老黄历（宜忌 / 干支 / 农历）。免密钥。
  ///
  /// **两个源拼起来**，因为没有任何单一免费源同时给全：
  /// - 60s `/v2/luck`：只给 luck_desc / luck_rank / luck_tip（无量化的宜忌）；
  /// - 万年历 `wannianrili.bmcx.com`：给干支、生肖、宜忌、节日，但只有 HTML。
  ///
  /// 万年历是 HTML 抓取（整月返回 ~200KB），所以**失败不影响主流程**：
  /// 抓不动就退回 60s 那部分，面板不会整块空掉。
  Future<LuckResult> dailyLuck({String? date}) async {
    final uri = Uri.https('60s.viki.moe', '/v2/luck', {
      if (date != null && date.isNotEmpty) 'date': date,
    });
    final data = _unwrap60s(await _getJson(uri));

    // 万年历补宜忌/干支。失败静默降级，只保留 60s 的部分。
    LuckAlmanacDetail? detail;
    try {
      detail = await _fetchAlmanacDetail(date ?? _string(data['date']));
    } catch (_) {
      detail = null;
    }

    return LuckResult(
      date: _string(data['date']),
      lunarDate: _string(data['lunar_date']),
      luckDesc: _string(data['luck_desc']),
      // 实测 /v2/luck 只有 luck_desc / luck_rank / luck_tip / luck_tip_index，
      // **没有 luck_level / suit / avoid / ganzhi_year / zodiac** ——
      // 等级真身是 luck_rank(int)；宜忌/干支改由万年历源补，见上。
      luckLevel: _string(data['luck_rank'] ?? data['luck_level']),
      suit: detail?.suit ?? const <String>[],
      avoid: detail?.avoid ?? const <String>[],
      ganZhiYear: detail?.ganZhiYear ?? _string(data['ganzhi_year']),
      zodiac: detail?.zodiac ?? _string(data['zodiac']),
      luckTip: _string(data['luck_tip']),
      festival: detail?.festival ?? '',
    );
  }

  /// 万年历 HTML 抓取：定位指定日期那一段，取出干支/生肖/宜/忌/节日。
  ///
  /// 页面结构（每月的每一天一段）：
  /// `2026年 09月 (小) 星期二|12|八月初二|丙午年 【马年】 丁酉月 己丑日|宜|A| |B| |忌|C|...`
  /// 页面把标签全去掉后就是这种 `|` 分隔的长串，所以解析前先做一次
  /// 「剥标签 → 压竖线」，再按段正则切。
  ///
  /// 传 [date]（yyyy-MM-dd）取哪一天；不给就用今天。
  Future<LuckAlmanacDetail?> _fetchAlmanacDetail(String? date) async {
    final target = (date != null && date.isNotEmpty) ? date : _todayIso();
    final uri = Uri.parse('https://wannianrili.bmcx.com/ajax/?q=$target&v=2');
    final html = await _getHtml(uri);

    final flat = html
        .replaceAll(RegExp(r'<script.*?</script>', dotAll: true), '')
        .replaceAll(RegExp(r'<style.*?</style>', dotAll: true), '')
        .replaceAll(RegExp('<[^>]+>'), '|')
        .replaceAll(RegExp(r'\|+'), '|')
        .replaceAll(RegExp(r'[ \t]+'), ' ');

    final parts = target.split('-');
    if (parts.length != 3) return null;
    final y = parts[0];
    final mo = parts[1];
    final d = parts[2];

    // 从「YYYY年 MM月 (大|小) 星期X|DD|」开始，截到宜/忌结束。
    final head = RegExp('$y年 $mo月 \\(.\\) 星期.\\|$d\\|').firstMatch(flat);
    if (head == null) return null;

    final rest = flat.substring(head.end);
    // 干支段：形如「丙午年 【马年】 丁酉月 己丑日」。
    final gz = RegExp(r'([^|]*年[^|]*日)').firstMatch(rest);
    final ganZhi = (gz?.group(1) ?? '').trim();
    final zodiac = RegExp(r'【(.*?)】').firstMatch(ganZhi)?.group(1) ?? '';

    String pick(String label) {
      // 注意两点，都是踩过的坑：
      // 1) Dart 字符串里 `\\|` 才是正则的字面竖线 `\|`（写 `\\\\|` 会多转一层，
      //    正则去找「反斜杠+竖线」，永远切不出来）；
      // 2) **Dart 的 RegExp 不支持 `\Z`** —— 它会当成字面量 Z。用 `$`。
      //    最初用 `\Z` 时「忌」永远 NO MATCH，而「宜」靠别的分支侥幸命中，
      //    表现成「宜显示、忌空白」，很容易误判成面板问题。
      final m = RegExp(
        '\\|$label\\|(.*?)(?=\\|$label\\||\\|宜\\||\\|忌\\||\\|\\d{4}年 |\$)',
        dotAll: true,
      ).firstMatch(rest);
      return m?.group(1) ?? '';
    }

    List<String> splitList(String raw) {
      final items = raw
          .split('|')
          .map((e) => e.trim())
          // 页面用 `&nbsp;` 占位（剥标签后是空格），不是真实条目。
          .where((e) => e.isNotEmpty && e != '&nbsp;')
          .toList();
      // 真实站点用「无」表示当天没有这项（实测 2026-09-12 忌 = 无）。
      // 不滤掉的话面板会显示「忌 无」，像是个真忌项。
      if (items.length == 1 && (items.first == '无' || items.first == '诸事不宜')) {
        return items.first == '诸事不宜' ? items : const <String>[];
      }
      return items;
    }

    // 节日在干支段之后、宜之前，形如 `节日|名称|`。
    final festival =
        RegExp(r'\|节日\|([^|]*)\|').firstMatch(rest)?.group(1) ?? '';

    return LuckAlmanacDetail(
      ganZhiYear: ganZhi,
      zodiac: zodiac,
      suit: splitList(pick('宜')),
      avoid: splitList(pick('忌')),
      festival: festival.trim(),
    );
  }

  String _todayIso() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  /// 必应每日壁纸。免密钥，实测 3/3。
  Future<BingWallpaperResult> bingWallpaper() async {
    final uri = Uri.https('60s.viki.moe', '/v2/bing');
    final data = _unwrap60s(await _getJson(uri));
    return BingWallpaperResult(
      title: _string(data['title'] ?? data['headline']),
      // 实测：图片地址在 cover / cover_4k，**没有 url 字段** ——
      // 原先读 url 导致图片恒为空、面板加载不出壁纸。
      url: _string(data['cover'] ?? data['cover_4k'] ?? data['url']),
      copyright: _string(data['copyright']),
      date: _string(data['update_date'] ?? data['date']),
      description: _string(data['description'] ?? data['main_text']),
    );
  }

  /// 百度实时热搜。免密钥，实测 3/3（返回 50 条）。
  Future<List<HotSearchResult>> baiduHotSearch({int limit = 30}) async {
    final uri = Uri.https('60s.viki.moe', '/v2/baidu/realtime');
    final list = _unwrap60sList(await _getJson(uri));
    final results = <HotSearchResult>[];
    for (final item in list) {
      if (item is! Map) continue;
      final title = _string(item['title'] ?? item['word'] ?? item['query']);
      if (title.isEmpty) continue;
      results.add(
        HotSearchResult(
          title: title,
          // 热度字段各平台不一，顺序有讲究：
          // - baidu: score_desc 是「780.88w」这类可读值；**desc 是新闻摘要，绝不能当热度**；
          // - 60s 其他热榜: hot_value(int) / hot / hotValue；
          // - 知乎: hot_value_desc 优先（「773 万热度」）。
          hot: _string(
            item['hot_value_desc'] ??
                item['hot'] ??
                item['hotValue'] ??
                item['score_desc'] ??
                item['hot_value'],
          ),
          url: _string(item['url'] ?? item['link']),
        ),
      );
      if (results.length >= limit) break;
    }
    return results;
  }

  /// 实时汇率（对指定基准币）。免密钥，实测 3/3。
  Future<ExchangeRateResult> exchangeRates({String currency = 'CNY'}) async {
    final uri = Uri.https('60s.viki.moe', '/v2/exchange_rate', {
      'currency': currency,
    });
    final data = _unwrap60s(await _getJson(uri));
    final rawRates = data['rates'] ?? data['exchange_rate'];
    final rates = <String, double>{};
    if (rawRates is Map) {
      rawRates.forEach((key, value) {
        final parsed = _double(value);
        if (parsed != null) rates[key.toString()] = parsed;
      });
    }
    return ExchangeRateResult(
      base: _string(data['base'] ?? data['currency'], currency),
      updated: _string(data['updated'] ?? data['update_time'] ?? data['time']),
      rates: rates,
    );
  }

  /// IP 归属查询。免密钥，实测 3/3。
  Future<IpQueryResult> queryIp({String? ip}) async {
    final uri = Uri.https('60s.viki.moe', '/v2/ip', {
      if (ip != null && ip.isNotEmpty) 'ip': ip,
    });
    final data = _unwrap60s(await _getJson(uri));
    return IpQueryResult(
      ip: _string(data['ip']),
      country: _string(data['country']),
      province: _string(data['province'] ?? data['region']),
      city: _string(data['city']),
      isp: _string(data['isp']),
    );
  }

  /// 手机号归属地（360）。免密钥，实测 3/3。
  Future<PhoneAreaResult> phoneArea(String number) async {
    final uri = Uri.https('cx.shouji.360.cn', '/phonearea.php', {
      'number': number,
    });
    final json = await _getJson(uri);
    final data = json['data'];
    final map = data is Map ? Map<String, dynamic>.from(data) : json;
    return PhoneAreaResult(
      province: _string(map['province']),
      city: _string(map['city']),
      sp: _string(map['sp']),
      cardType: _string(map['cardtype']),
    );
  }

  /// 中英互译（MyMemory）。免密钥，实测 3/3。
  Future<TranslateResult> translate({
    required String text,
    String from = 'en',
    String to = 'zh',
  }) async {
    final uri = Uri.https('api.mymemory.translated.net', '/get', {
      'q': text,
      'langpair': '$from|$to',
    });
    final json = await _getJson(uri);
    final data = json['responseData'];
    final map = data is Map ? Map<String, dynamic>.from(data) : const {};
    final translated = _string(map['translatedText']);
    if (translated.isEmpty) {
      throw const ApiHubException('翻译接口没有返回结果');
    }
    return TranslateResult(
      translatedText: translated,
      match: _double(map['match']),
    );
  }

  // A-2 本轮接线：以下接口全部经 tool/probe_public_apis.sh 实测
  // （间隔 4s × 3 次，并通过内容级假成功校验：HTTP 200 但 body 是错误文案的
  // 一律判失败，shadiao 的 jt / nmsl 两条就是这样被剔除的）。
  // ——————————————————————————————————————————————————————————

  /// 微博热搜。免密钥，实测 3/3。
  Future<List<HotSearchResult>> weiboHotSearch({int limit = 30}) async {
    final uri = Uri.https('60s.viki.moe', '/v2/weibo');
    final list = _unwrap60sList(await _getJson(uri));
    return _mapHotList(list, limit);
  }

  /// 知乎热榜。免密钥，实测 3/3。
  Future<List<HotSearchResult>> zhihuHotSearch({int limit = 30}) async {
    final uri = Uri.https('60s.viki.moe', '/v2/zhihu');
    final list = _unwrap60sList(await _getJson(uri));
    return _mapHotList(list, limit);
  }

  /// 抖音热点。免密钥，实测 3/3。
  Future<List<HotSearchResult>> douyinHotSearch({int limit = 30}) async {
    final uri = Uri.https('60s.viki.moe', '/v2/douyin');
    final list = _unwrap60sList(await _getJson(uri));
    return _mapHotList(list, limit);
  }

  /// 今日头条热榜。免密钥，实测 3/3。
  Future<List<HotSearchResult>> toutiaoHotSearch({int limit = 30}) async {
    final uri = Uri.https('60s.viki.moe', '/v2/toutiao');
    final list = _unwrap60sList(await _getJson(uri));
    return _mapHotList(list, limit);
  }

  /// 热榜类公共映射：各平台字段名不一，按优先级逐个探测。
  ///
  /// 实测（curl 各平台取首条）字段差异：
  /// - weibo / douyin / toutiao：`hot_value` 是 **int**，无描述字段；
  /// - zhihu：除 `hot_value` 外还给 `hot_value_desc`（如「773 万热度」），
  ///   可读性远好于裸数字，优先取它。
  /// 曾漏掉 `hot_value` 这个名字，导致四个平台热度全部显示为空。
  List<HotSearchResult> _mapHotList(List<dynamic> list, int limit) {
    final results = <HotSearchResult>[];
    for (final item in list) {
      if (item is! Map) continue;
      final title = _string(item['title'] ?? item['word'] ?? item['query']);
      if (title.isEmpty) continue;
      results.add(
        HotSearchResult(
          title: title,
          hot: _string(
            item['hot_value_desc'] ??
                item['hot'] ??
                item['hotValue'] ??
                item['hot_value'] ??
                item['desc'],
          ),
          url: _string(item['url'] ?? item['link'] ?? item['mobileUrl']),
        ),
      );
      if (results.length >= limit) break;
    }
    return results;
  }

  /// 今日运势。免密钥，实测 3/3。
  ///
  /// 与 [dailyLuck] 同源（60s /v2/luck），但抽的是运程字段而非宜忌，
  /// 面板上呈现为「等级 + 提示」，与老黄历区分开。
  Future<FortuneResult> dailyFortune({String? date}) async {
    final uri = Uri.https('60s.viki.moe', '/v2/luck', {
      if (date != null && date.isNotEmpty) 'date': date,
    });
    final data = _unwrap60s(await _getJson(uri));
    return FortuneResult(
      date: _string(data['date']),
      luckDesc: _string(data['luck_desc']),
      luckLevel: _string(data['luck_level']),
      luckTip: _string(data['luck_tip']),
      zodiac: _string(data['zodiac']),
    );
  }

  /// 摸鱼日历。免密钥，实测 3/3。
  Future<MoyuResult> moyuCalendar() async {
    final uri = Uri.https('60s.viki.moe', '/v2/moyu');
    final data = _unwrap60s(await _getJson(uri));
    final date = data['date'];
    final dateMap = date is Map ? Map<String, dynamic>.from(date) : const {};
    final next = data['next_holiday'];
    final nextMap = next is Map ? Map<String, dynamic>.from(next) : const {};
    return MoyuResult(
      gregorianDate: _string(dateMap['gregorian'] ?? data['gregorian']),
      lunarDate: _string(dateMap['lunar'] ?? data['lunar']),
      weekday: _string(dateMap['week'] ?? data['week']),
      nextHolidayName: _string(nextMap['name'] ?? data['next_holiday_name']),
      nextHolidayDate: _string(nextMap['date'] ?? data['next_holiday_date']),
      daysLeft: _int(data['days_left'] ?? nextMap['days_left']),
      description: _string(data['desc'] ?? data['description']),
    );
  }

  /// 毒鸡汤。免密钥，实测 3/3。
  ///
  /// 注意域名是 shadiao.pro：文档里写的 .app 会 301 跳转，其中 chp 一类
  /// 跳到 .pro 后是 404，直连 .pro 才稳定。
  Future<QuoteResult> dujitang() async {
    final uri = Uri.https('api.shadiao.pro', '/du');
    return _textQuote(uri);
  }

  /// 随机彩虹屁。免密钥，实测 3/3。
  Future<QuoteResult> rainbowFart() async {
    final uri = Uri.https('api.shadiao.pro', '/chp');
    return _textQuote(uri);
  }

  // —— A-3 批次3接线 ——

  /// 猫眼票房总榜（60s /v2/maoyan）。
  Future<List<BoxOfficeItem>> boxOfficeRank({int limit = 30}) async {
    final uri = Uri.https('60s.viki.moe', '/v2/maoyan');
    final data = _unwrap60s(await _getJson(uri));
    final rawList = data['list'];
    final results = <BoxOfficeItem>[];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is! Map) continue;
        final name = _string(item['movie_name'] ?? item['title']);
        if (name.isEmpty) continue;
        results.add(
          BoxOfficeItem(
            rank: _int(item['rank'], results.length + 1),
            movieName: name,
            releaseYear: _string(item['release_year']),
            boxOfficeDesc: _string(item['box_office_desc']),
          ),
        );
        if (results.length >= limit) break;
      }
    }
    return results;
  }

  /// Epic 每周免费游戏（60s /v2/epic）。
  Future<List<EpicFreeGame>> epicFreeGames() async {
    final uri = Uri.https('60s.viki.moe', '/v2/epic');
    final list = _unwrap60sList(await _getJson(uri));
    final results = <EpicFreeGame>[];
    for (final item in list) {
      if (item is! Map) continue;
      final title = _string(item['title']);
      if (title.isEmpty) continue;
      results.add(
        EpicFreeGame(
          title: title,
          originalPriceDesc: _string(item['original_price_desc']),
          seller: _string(item['seller']),
          freeEnd: _string(item['free_end']),
          cover: _string(item['cover']),
          link: _string(item['link']),
          isFreeNow: item['is_free_now'] == true,
        ),
      );
    }
    return results;
  }

  /// shadiao 系列解析：外壳 { data: { type, text } }。
  /// body 里的 text 可能是「404 Not Found.」这类伪成功，需显式拦掉。
  Future<QuoteResult> _textQuote(Uri uri) async {
    final json = await _getJson(uri);
    final data = json['data'];
    final map = data is Map ? Map<String, dynamic>.from(data) : const {};
    final text = _string(map['text']);
    if (text.isEmpty || text.contains('Not Found')) {
      throw const ApiHubException('接口没有返回有效内容');
    }
    return QuoteResult(type: _string(map['type']), text: text);
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

  /// 抓取 HTML 页面（非 JSON 源用）。
  ///
  /// 万年历这类站点没有开放 API，只能抓 HTML。与 [_getDecoded] 的区别是
  /// 不 jsonDecode，直接返回解码后的字符串。
  Future<String> _getHtml(Uri uri) async {
    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiHubException('接口请求失败：HTTP ${response.statusCode}');
      }
      return utf8.decode(response.bodyBytes);
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

  /// 把接口返回的数组安全转成字符串列表。
  ///
  /// 免费接口偶发把数组给成 null、字符串或混合类型，裸 `List<String>.from`
  /// 会抛。这里统一退化成空列表 / 逐项 toString，保住调用方不崩。
  List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .where((e) => e != null)
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  /// 安全取整数；免费接口有时给字符串数字或 null。
  int _int(dynamic value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
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
