import 'dart:convert';

Map<String, dynamic> extractUpdateDataMap(dynamic data) {
  if (data is String) {
    final decoded = jsonDecode(data);
    if (decoded is Map<String, dynamic>) {
      return normalizeUpdateResponse(decoded);
    }
    if (decoded is Map) {
      return normalizeUpdateResponse(Map<String, dynamic>.from(decoded));
    }
    throw Exception('接口返回不是 Map');
  }

  if (data is Map<String, dynamic>) {
    return normalizeUpdateResponse(data);
  }

  if (data is Map) {
    return normalizeUpdateResponse(Map<String, dynamic>.from(data));
  }

  throw Exception('不支持的返回类型：${data.runtimeType}');
}

Map<String, dynamic> normalizeUpdateResponse(Map<String, dynamic> raw) {
  // 兼容 {code:0, message:"ok", data:{...}}
  final data = raw['data'];
  if (data is Map<String, dynamic>) {
    return _validateUpdateManifestMap(Map<String, dynamic>.from(data));
  }
  if (data is Map) {
    return _validateUpdateManifestMap(Map<String, dynamic>.from(data));
  }
  return _validateUpdateManifestMap(raw);
}

Map<String, dynamic> _validateUpdateManifestMap(Map<String, dynamic> map) {
  if (map.isEmpty) {
    throw Exception('更新接口返回为空');
  }

  final downloadUrl = map['downloadUrl']?.toString().trim() ?? '';
  if (downloadUrl.isEmpty) {
    throw Exception('更新接口缺少 downloadUrl');
  }

  return map;
}
