/// 壁纸清单的获取与保存到相册。
///
/// 两个可注入点（[WallpaperApi] 的 httpClient、[saveWallpaperToGallery] 的
/// [WallpaperSaver]）都是为了 widget 测试能跑完整流程而不真的联网/碰相册。
library;

import 'dart:convert';
import 'dart:io';

import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../domain/wallpaper_item.dart';

/// 壁纸清单地址（自托管，与 App 更新同域）。
const String kWallpaperManifestUrl =
    'https://box.hpa888.top/updates/box/media/wallpapers/manifest.json';

abstract class WallpaperSource {
  Future<WallpaperManifest> load();
}

class WallpaperApi implements WallpaperSource {
  WallpaperApi({http.Client? httpClient, Uri? manifestUrl})
      : _http = httpClient ?? http.Client(),
        _url = manifestUrl ?? Uri.parse(kWallpaperManifestUrl);

  final http.Client _http;
  final Uri _url;

  @override
  Future<WallpaperManifest> load() async {
    http.Response res;
    try {
      res = await _http.get(
        _url,
        headers: const {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 20));
    } catch (e) {
      throw WallpaperManifestException('壁纸清单拉取失败：$e');
    }
    if (res.statusCode != 200) {
      throw WallpaperManifestException('壁纸清单返回 HTTP ${res.statusCode}');
    }
    // 服务端是 UTF-8；用 bodyBytes 解，避免中文标题被按 latin1 解成乱码。
    return parseWallpaperManifest(utf8.decode(res.bodyBytes, allowMalformed: true));
  }
}

typedef WallpaperSaver = Future<void> Function(WallpaperItem item);

/// 默认保存动作：下载全图 → 写临时文件 → 进系统相册。
///
/// `Gal.putImage` 是**复制**进相册，所以临时文件用完就删（不留垃圾）。
Future<void> saveWallpaperToGallery(
  WallpaperItem item,
  String baseUrl, {
  http.Client? httpClient,
}) async {
  final uri = item.fullUrl(baseUrl);
  if (uri.isEmpty) {
    throw const WallpaperManifestException('这张壁纸没有下载地址');
  }
  final client = httpClient ?? http.Client();
  final res = await client.get(Uri.parse(uri)).timeout(
        const Duration(seconds: 60),
      );
  if (res.statusCode != 200) {
    throw WallpaperManifestException('下载失败：HTTP ${res.statusCode}');
  }
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/box-wallpaper-${item.id}.jpg');
  await file.writeAsBytes(res.bodyBytes, flush: true);
  try {
    await Gal.putImage(file.path);
  } finally {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 删不掉也不影响相册里的那份
    }
  }
}
