import 'dart:convert';

/// JSON 解析与配置解析
class JsonParser {
  const JsonParser();

  dynamic tryDecodeJson(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  Map<String, String> parseHeader(dynamic raw) {
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
    }

    final s = raw?.toString().trim() ?? '';
    if (s.isEmpty) return <String, String>{};

    try {
      final decoded = jsonDecode(s);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}

    try {
      final normalized = s.replaceAll("'", '"');
      final decoded = jsonDecode(normalized);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}

    final out = <String, String>{};
    final matches =
        RegExp(r'([A-Za-z0-9_\-]+)\s*:\s*([^,\n]+)').allMatches(s);
    for (final m in matches) {
      final key = m.group(1)?.trim();
      final value = m.group(2)?.trim();
      if (key != null && key.isNotEmpty && value != null && value.isNotEmpty) {
        out[key] = value.replaceAll(RegExp(r'''^['"]|['"]$'''), '');
      }
    }
    return out;
  }
}
