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
