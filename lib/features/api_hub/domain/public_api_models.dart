class PublicBookResult {
  const PublicBookResult({
    required this.title,
    required this.author,
    required this.year,
    required this.coverId,
    required this.key,
  });

  final String title;
  final String author;
  final int? year;
  final int? coverId;
  final String key;

  String? get coverUrl => coverId == null
      ? null
      : 'https://covers.openlibrary.org/b/id/$coverId-M.jpg';
}

class HolidayResult {
  const HolidayResult({
    required this.date,
    required this.localName,
    required this.name,
    required this.countryCode,
  });

  final String date;
  final String localName;
  final String name;
  final String countryCode;
}

class WeatherForecastResult {
  const WeatherForecastResult({
    required this.latitude,
    required this.longitude,
    required this.timezone,
    required this.currentTemperature,
    required this.currentWindSpeed,
    required this.daily,
  });

  final double latitude;
  final double longitude;
  final String timezone;
  final double? currentTemperature;
  final double? currentWindSpeed;
  final List<WeatherDailyResult> daily;
}

class WeatherDailyResult {
  const WeatherDailyResult({
    required this.date,
    required this.maxTemperature,
    required this.minTemperature,
    required this.weatherCode,
  });

  final String date;
  final double? maxTemperature;
  final double? minTemperature;
  final int? weatherCode;
}

class DictionaryResult {
  const DictionaryResult({
    required this.word,
    required this.phonetic,
    required this.meanings,
  });

  final String word;
  final String phonetic;
  final List<DictionaryMeaningResult> meanings;
}

class DictionaryMeaningResult {
  const DictionaryMeaningResult({
    required this.partOfSpeech,
    required this.definition,
    required this.example,
  });

  final String partOfSpeech;
  final String definition;
  final String example;
}

class MockUserResult {
  const MockUserResult({
    required this.fullName,
    required this.username,
    required this.email,
    required this.phone,
    required this.city,
    required this.company,
    required this.image,
  });

  final String fullName;
  final String username;
  final String email;
  final String phone;
  final String city;
  final String company;
  final String image;

  String get copyText => [
    fullName,
    if (username.isNotEmpty) '@$username',
    if (email.isNotEmpty) email,
    if (phone.isNotEmpty) phone,
    if (city.isNotEmpty) city,
    if (company.isNotEmpty) company,
  ].join(' · ');
}

class QrCodeResult {
  const QrCodeResult({
    required this.url,
    required this.size,
    required this.text,
  });

  final String url;
  final String size;
  final String text;
}

class AvatarResult {
  const AvatarResult({
    required this.url,
    required this.name,
    required this.background,
    required this.foreground,
    required this.size,
  });

  final String url;
  final String name;
  final String background;
  final String foreground;
  final int size;
}

class CoverImageResult {
  const CoverImageResult({
    required this.url,
    required this.width,
    required this.height,
    required this.seed,
  });

  final String url;
  final int width;
  final int height;
  final String seed;
}

class ShortLinkResult {
  const ShortLinkResult({required this.originalUrl, required this.shortUrl});

  final String originalUrl;
  final String shortUrl;
}

class MockProductResult {
  const MockProductResult({
    required this.title,
    required this.brand,
    required this.price,
    required this.category,
    required this.thumbnail,
  });

  final String title;
  final String brand;
  final double price;
  final String category;
  final String thumbnail;
}

class SpaceflightNewsResult {
  const SpaceflightNewsResult({
    required this.title,
    required this.summary,
    required this.url,
    required this.publishedAt,
  });

  final String title;
  final String summary;
  final String url;
  final String publishedAt;
}

class IpInfoResult {
  const IpInfoResult({
    required this.ip,
    required this.city,
    required this.region,
    required this.country,
    required this.org,
    required this.timezone,
  });

  final String ip;
  final String city;
  final String region;
  final String country;
  final String org;
  final String timezone;
}

class DummyImageResult {
  const DummyImageResult({
    required this.url,
    required this.size,
    required this.background,
    required this.foreground,
    required this.text,
  });

  final String url;
  final String size;
  final String background;
  final String foreground;
  final String text;
}

class PublicApiDirectoryEntry {
  const PublicApiDirectoryEntry({
    required this.name,
    required this.category,
    required this.description,
    required this.url,
    required this.auth,
    required this.https,
    required this.cors,
    required this.latencyMs,
    required this.httpStatus,
    required this.method,
  });

  factory PublicApiDirectoryEntry.fromJson(Map<String, dynamic> json) {
    return PublicApiDirectoryEntry(
      name: _string(json['name']),
      category: _string(json['category']),
      description: _string(json['description']),
      url: _string(json['url']),
      auth: _string(json['auth'], 'Unknown'),
      https: json['https'] == true,
      cors: _string(json['cors'], 'Unknown'),
      latencyMs: json['latency_ms'] is num
          ? (json['latency_ms'] as num).toInt()
          : null,
      httpStatus: json['http_status'] is num
          ? (json['http_status'] as num).toInt()
          : null,
      method: _string(json['method']),
    );
  }

  final String name;
  final String category;
  final String description;
  final String url;
  final String auth;
  final bool https;
  final String cors;
  final int? latencyMs;
  final int? httpStatus;
  final String method;

  bool get noAuth => auth.toLowerCase() == 'no';

  bool get isIntegrated {
    final lower = name.toLowerCase();
    return lower.contains('open-meteo') ||
        lower.contains('ipify') ||
        lower.contains('ipinfo') ||
        lower.contains('dummyimage') ||
        lower.contains('dummyjson') ||
        lower.contains('frankfurter') ||
        lower.contains('nager') ||
        lower.contains('free dictionary');
  }

  bool get isRecommended {
    final usefulCategories = {
      'Weather',
      'Development',
      'Geocoding',
      'Art & Design',
      'Food & Drink',
      'Environment',
    };
    return isIntegrated || usefulCategories.contains(category);
  }

  bool matches(String keyword) {
    final query = keyword.trim().toLowerCase();
    if (query.isEmpty) return true;
    return name.toLowerCase().contains(query) ||
        category.toLowerCase().contains(query) ||
        description.toLowerCase().contains(query) ||
        url.toLowerCase().contains(query) ||
        auth.toLowerCase().contains(query);
  }

  static String _string(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }
}

/// 一条随机语录（hitokoto 一言）。
///
/// 免费接口偶发返回 `null` 或数字字段，所以全部字段都用 String 存并在解析层
/// 做退化，不在这里做非空断言 —— 面板宁可显示空白，也不该整页崩掉。
class HitokotoResult {
  const HitokotoResult({
    required this.text,
    required this.from,
    required this.fromWho,
    required this.type,
  });

  /// 正文（`hitokoto` 字段）。缺失时为空串。
  final String text;

  /// 出处作品，例如「葬送的芙莉莲」。
  final String from;

  /// 出处人物，例如「辛美尔」。可能为空。
  final String fromWho;

  /// 分类代码（a=动画 b=漫画 c=游戏 d=文学 i=诗词 …）。
  final String type;

  /// 展示用的出处串：优先「作品 · 人物」，都没有时返回空串。
  String get sourceLabel {
    if (from.isEmpty && fromWho.isEmpty) return '';
    if (fromWho.isEmpty) return from;
    if (from.isEmpty) return fromWho;
    return '$from · $fromWho';
  }
}

/// 一条今日诗词（jinrishici）。
class PoetryResult {
  const PoetryResult({
    required this.content,
    required this.title,
    required this.dynasty,
    required this.author,
    required this.fullPoem,
    required this.translation,
  });

  /// 摘出的那一句（接口的 `data.content`）。
  final String content;

  /// 诗名，例如「春江花月夜」。
  final String title;

  /// 朝代，例如「唐代」。
  final String dynasty;

  /// 作者，例如「张若虚」。
  final String author;

  /// 全诗各句。接口给的是数组，这里原样保留顺序。
  final List<String> fullPoem;

  /// 白话翻译各句。不少诗没有翻译，此时为空列表。
  final List<String> translation;

  /// 展示用署名：「唐代 · 张若虚」。
  String get attribution {
    if (dynasty.isEmpty) return author;
    if (author.isEmpty) return dynasty;
    return '$dynasty · $author';
  }
}

// ══════════════════════════════════════════════════════════════════
// A-1 本轮接线引入的模型。字段全部按 tool/probe_60s.sh 抓到的真实响应定义。
// ══════════════════════════════════════════════════════════════════

/// 每日英语（金山词霸 dsapi）。
class DailyEnglishResult {
  const DailyEnglishResult({
    required this.content,
    this.note = '',
    this.picture = '',
    this.picture2 = '',
    this.translation = '',
  });

  /// 英文原句。
  final String content;

  /// 中文翻译。
  final String note;

  /// 配图地址（宽版）。
  final String picture;

  /// 配图地址（竖版）。
  final String picture2;

  /// 备用的中文译文字段，部分日期只有这个。
  final String translation;

  /// 展示用译文：优先 note，退回 translation。
  String get displayTranslation => note.isNotEmpty ? note : translation;
}

/// 每日 60 秒资讯。
class News60sResult {
  const News60sResult({
    required this.date,
    required this.items,
    this.tips = const [],
    this.dayOfWeek = '',
    this.lunarDate = '',
  });

  final String date;

  /// 15 条要闻标题。
  final List<String> items;

  /// 附带的每日一句 / 小贴士。
  final List<String> tips;

  final String dayOfWeek;
  final String lunarDate;
}

/// 历史上今天的一条事件。
class HistoryEventResult {
  const HistoryEventResult({
    required this.year,
    required this.title,
    this.description = '',
    this.link = '',
  });

  final String year;
  final String title;
  final String description;
  final String link;
}

/// 老黄历。
class LuckResult {
  const LuckResult({
    required this.date,
    this.lunarDate = '',
    this.luckDesc = '',
    this.luckLevel = '',
    this.suit = const [],
    this.avoid = const [],
    this.ganZhiYear = '',
    this.zodiac = '',
    this.luckTip = '',
    this.festival = '',
  });

  final String date;
  final String lunarDate;
  final String luckDesc;
  final String luckLevel;

  /// 宜。
  final List<String> suit;

  /// 忌。
  final List<String> avoid;

  final String ganZhiYear;
  final String zodiac;

  /// 60s `/v2/luck` 给的一句运程提示。
  final String luckTip;

  /// 当日节日（万年历源，可能为空）。
  final String festival;
}

/// 万年历源（wannianrili.bmcx.com）解析出的宜忌明细。
///
/// 单独一个类是因为它是**独立的第二个数据源**：60s 只给运程描述，
/// 宜忌/干支得靠 HTML 抓取补。抓取失败时整块为 null，面板退回 60s 部分。
class LuckAlmanacDetail {
  const LuckAlmanacDetail({
    this.ganZhiYear = '',
    this.zodiac = '',
    this.suit = const [],
    this.avoid = const [],
    this.festival = '',
  });

  /// 干支全串，如「丙午年 【马年】 丁酉月 己丑日」。
  final String ganZhiYear;

  /// 生肖，如「马年」。
  final String zodiac;

  final List<String> suit;
  final List<String> avoid;
  final String festival;
}

/// 必应每日壁纸。
class BingWallpaperResult {
  const BingWallpaperResult({
    required this.title,
    required this.url,
    this.copyright = '',
    this.date = '',
    this.description = '',
  });

  final String title;
  final String url;
  final String copyright;
  final String date;
  final String description;
}

/// 一条热搜。
class HotSearchResult {
  const HotSearchResult({required this.title, this.hot = '', this.url = ''});

  final String title;
  final String hot;
  final String url;
}

/// 汇率表。
class ExchangeRateResult {
  const ExchangeRateResult({
    required this.base,
    required this.rates,
    this.updated = '',
  });

  final String base;

  /// 币种代码 → 汇率。
  final Map<String, double> rates;

  final String updated;

  /// 按币种代码取汇率，取不到返回 null（不做兜底，避免悄悄显示错的数）。
  double? rateOf(String code) => rates[code.toUpperCase()];
}

/// IP 归属信息。
class IpQueryResult {
  const IpQueryResult({
    required this.ip,
    this.country = '',
    this.province = '',
    this.city = '',
    this.isp = '',
  });

  final String ip;
  final String country;
  final String province;
  final String city;
  final String isp;

  /// 展示用归属地：「中国 北京」。
  String get location {
    final parts = [country, province, city].where((e) => e.isNotEmpty);
    return parts.join(' ');
  }
}

/// 手机号归属地。
class PhoneAreaResult {
  const PhoneAreaResult({
    this.province = '',
    this.city = '',
    this.sp = '',
    this.cardType = '',
  });

  final String province;
  final String city;
  final String sp;
  final String cardType;

  /// 运营商简称。
  String get carrier => sp.isNotEmpty ? sp : cardType;
}

/// 翻译结果。
class TranslateResult {
  const TranslateResult({required this.translatedText, this.match});

  final String translatedText;

  /// 接口给的匹配置信度，0~1；不保证存在。
  final double? match;
}

/// 今日运势（60s /v2/luck 的运程视角）。
///
/// 与 [LuckResult] 同源但用途不同：那个面是宜忌黄历，这个面只取等级与提示。
class FortuneResult {
  const FortuneResult({
    required this.date,
    this.luckDesc = '',
    this.luckLevel = '',
    this.luckTip = '',
    this.zodiac = '',
  });

  final String date;

  /// 运程描述，例如「大凶」「大吉」。
  final String luckDesc;

  /// 等级字样，接口另给的一份措辞。
  final String luckLevel;

  /// 一句运程提示。
  final String luckTip;

  final String zodiac;
}

/// 摸鱼日历（60s /v2/moyu）：今天是什么日子 + 离放假还有几天。
class MoyuResult {
  const MoyuResult({
    this.gregorianDate = '',
    this.lunarDate = '',
    this.weekday = '',
    this.nextHolidayName = '',
    this.nextHolidayDate = '',
    this.daysLeft = 0,
    this.description = '',
  });

  final String gregorianDate;
  final String lunarDate;
  final String weekday;

  /// 下一个节假日名称。
  final String nextHolidayName;
  final String nextHolidayDate;

  /// 距下一个节假日还有几天。
  final int daysLeft;

  /// 当日的一句吐槽文案。
  final String description;
}

/// 短文案类接口（毒鸡汤 / 彩虹屁）的统一结果。
class QuoteResult {
  const QuoteResult({this.type = '', required this.text});

  /// 接口自报的类型，例如「毒鸡汤」「彩虹屁」。
  final String type;

  final String text;
}

/// 猫眼票房榜的一条（60s /v2/maoyan）。
class BoxOfficeItem {
  const BoxOfficeItem({
    required this.rank,
    required this.movieName,
    this.releaseYear = '',
    this.boxOfficeDesc = '',
  });

  final int rank;
  final String movieName;
  final String releaseYear;

  /// 接口给的中文描述，例如「212.01亿元」；比原始整数可读。
  final String boxOfficeDesc;
}

/// Epic 免费游戏一条（60s /v2/epic）。
class EpicFreeGame {
  const EpicFreeGame({
    required this.title,
    this.originalPriceDesc = '',
    this.seller = '',
    this.freeEnd = '',
    this.cover = '',
    this.link = '',
    this.isFreeNow = false,
  });

  final String title;

  /// 原价描述，例如「¥68.00」。
  final String originalPriceDesc;
  final String seller;

  /// 免费截止时间，接口给的是字符串原样（含时区语义不明，不做解析）。
  final String freeEnd;
  final String cover;
  final String link;
  final bool isFreeNow;
}
