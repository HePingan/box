import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'apk_digest.dart';

/// 一条「已下载但可能还没装上」的更新包记录。
class PendingUpdateApk {
  const PendingUpdateApk({
    required this.versionCode,
    required this.path,
    required this.sha256,
  });

  final int versionCode;
  final String path;
  final String sha256;
}

/// 记住已经下载好的更新包，避免「下完了没装上 → 只能从头再下一遍」。
///
/// 为什么需要：用户把 App 放后台，下载到 100% 时系统会把后台发起的安装界面静默
/// 丢掉（见 `AppInstaller.downloadApk` 的注释），界面看着卡死在 100%，而唯一的出路
/// 是**重新下载 27MB**（2026-09-29 用户报的）。记下 {版本号, 路径, 哈希} 之后，再进来
/// 先认这个包：文件还在、哈希还对得上，就直接进「立即安装」。
///
/// 只认**同一版本 + 同一哈希**：服务端用同一个 versionCode 重发了新包（哈希变了）
/// 会自然失效，绝不会把旧包当成新包装上去。文件被系统清掉同样自然失效。
class PendingUpdateApkStore {
  PendingUpdateApkStore._();

  static final PendingUpdateApkStore instance = PendingUpdateApkStore._();

  static const String _keyVersionCode = 'update_pending_apk_version_code_v1';
  static const String _keyPath = 'update_pending_apk_path_v1';
  static const String _keySha256 = 'update_pending_apk_sha256_v1';

  /// 读写上限，理由同 `UpdateIgnoreStore`：缺少 platform channel 的环境里
  /// `SharedPreferences.getInstance()` **既不返回也不抛异常**，只 catch 挡不住。
  /// 认包只是"省一次下载"，读不到就当没有，绝不能因此卡住更新。
  static const Duration ioTimeout = Duration(seconds: 2);

  // ---- 仅测试注入：内存态 ----
  bool _useMemory = false;
  PendingUpdateApk? _memory;

  void debugUseInMemory() {
    _useMemory = true;
    _memory = null;
  }

  void debugReset() {
    _useMemory = false;
    _memory = null;
  }

  Future<void> save({
    required int versionCode,
    required String path,
    required String sha256,
  }) async {
    if (versionCode <= 0 || path.isEmpty || sha256.isEmpty) return;
    final record = PendingUpdateApk(
      versionCode: versionCode,
      path: path,
      sha256: sha256,
    );
    if (_useMemory) {
      _memory = record;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance().timeout(ioTimeout);
      await prefs.setInt(_keyVersionCode, versionCode).timeout(ioTimeout);
      await prefs.setString(_keyPath, path).timeout(ioTimeout);
      await prefs.setString(_keySha256, sha256).timeout(ioTimeout);
    } catch (_) {
      // 存不下只是下次要重下，不影响这一次的安装，不打扰用户。
    }
  }

  Future<PendingUpdateApk?> read() async {
    if (_useMemory) return _memory;
    try {
      final prefs = await SharedPreferences.getInstance().timeout(ioTimeout);
      final code = prefs.getInt(_keyVersionCode);
      final path = prefs.getString(_keyPath);
      final sha = prefs.getString(_keySha256);
      if (code == null || path == null || sha == null) return null;
      return PendingUpdateApk(versionCode: code, path: path, sha256: sha);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    if (_useMemory) {
      _memory = null;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance().timeout(ioTimeout);
      await prefs.remove(_keyVersionCode).timeout(ioTimeout);
      await prefs.remove(_keyPath).timeout(ioTimeout);
      await prefs.remove(_keySha256).timeout(ioTimeout);
    } catch (_) {}
  }

  /// 找一个**现在就能装**的包：同版本、文件还在、哈希对得上。
  ///
  /// 对不上（版本换了、文件被清了、哈希变了）就把记录清掉，免得反复认一个用不了的包。
  /// 校验是流式的（64KB 峰值），27MB 的包在手机上约一秒，只在点更新时发生一次。
  Future<String?> reusablePath({
    required int versionCode,
    required String expectedSha256,
  }) async {
    if (versionCode <= 0 || expectedSha256.isEmpty) return null;

    final record = await read();
    if (record == null) return null;

    final sameVersion = record.versionCode == versionCode;
    final sameSha =
        record.sha256.toLowerCase() == expectedSha256.toLowerCase();
    if (!sameVersion || !sameSha) {
      // 别的版本：这条记录没用了，清掉；同一版本但哈希变了（服务端重发了包），
      // 也清掉 —— 两者都只能重新下载。
      await clear();
      return null;
    }

    final file = File(record.path);
    try {
      if (!await file.exists()) {
        await clear();
        return null;
      }
      final digest = await sha256OfFile(file);
      if (digest.toLowerCase() != expectedSha256.toLowerCase()) {
        await clear();
        return null;
      }
      return record.path;
    } catch (_) {
      // 读不动就当没有：重新下载比报错给用户看更合理。
      return null;
    }
  }
}
