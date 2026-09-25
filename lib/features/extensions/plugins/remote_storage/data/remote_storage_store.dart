// 远程存储账户的本地持久化：用户名/密码仅以密文形态落 SharedPreferences。
//
// C1（279）：算法由"固定盐 AES-CBC"升级为"每安装随机密钥 + AES-GCM"，
// 见 lib/utils/local_secret_codec.dart 顶部的说明。旧密文（固定盐 CBC）
// **仍可读**：读到时用旧密钥解出来，随即按新格式重写（懒迁移），
// 用户升级后不需要重新输入应用密码。

import 'dart:convert';

import 'package:box/utils/app_logger.dart';
import 'package:box/utils/local_secret_codec.dart';
import 'package:box/utils/log_channels.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/network_policy.dart';
import '../domain/remote_storage_models.dart';

/// 旧格式（固定盐 AES-CBC）的盐，仅用于迁移读取。
const String kRemoteStorageLegacySalt = 'box-remote-storage-v1';

/// 模块 context：决定本插件用的密钥（与账号存储不共用）。
const String kRemoteStorageCodecContext = 'remote-storage';

/// 账户仓库（SharedPreferences 单键密文）。
class RemoteStorageStore {
  static const String accountsKey = 'remoteStorage.accountsEnc';

  Future<List<RemoteStorageAccount>> loadAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(accountsKey);
      if (raw == null || raw.isEmpty) return <RemoteStorageAccount>[];

      final codec = await LocalSecretCodec.openWithPrefs(
        prefs,
        kRemoteStorageCodecContext,
      );
      var plain = codec.decrypt(raw);
      var needsMigration = false;
      if (plain == null && LocalSecretCodec.looksLegacy(raw)) {
        // 旧格式：解出来就按新格式重写一次，避免每次启动都走兼容分支。
        plain = LocalSecretCodec.decryptLegacy(raw, kRemoteStorageLegacySalt);
        needsMigration = plain != null;
      }
      if (plain == null || plain.isEmpty) return <RemoteStorageAccount>[];

      final decoded = jsonDecode(plain);
      if (decoded is! List) return <RemoteStorageAccount>[];
      final accounts = decoded
          .map(RemoteStorageAccount.fromJson)
          .whereType<RemoteStorageAccount>()
          .toList();
      if (needsMigration) {
        await saveAccounts(accounts);
        AppLogger.instance.logTo(
          LogChannel.storage,
          '远程存储凭据已迁移到新格式（每安装密钥 + AES-GCM）',
        );
      }
      return accounts;
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '读取账户失败: $e',
        level: LogLevel.error,
      );
      return <RemoteStorageAccount>[];
    }
  }

  Future<void> saveAccounts(List<RemoteStorageAccount> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    final codec = await LocalSecretCodec.openWithPrefs(
      prefs,
      kRemoteStorageCodecContext,
    );
    final plain = jsonEncode(accounts.map((a) => a.toJson()).toList());
    await prefs.setString(accountsKey, codec.encrypt(plain));
  }

  // ------------------------------------------------------ 列表偏好（非敏感）

  static const String thumbnailsEnabledKey =
      'remoteStorage.thumbnailsEnabled';

  /// 列表是否显示图片缩略图。默认**开**——用户要的就是"能看到图"；
  /// 关掉的是少数（流量敏感），所以关这个动作要记下来。
  Future<bool> loadThumbnailsEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(thumbnailsEnabledKey) ?? true;
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '读取缩略图开关失败: $e',
        level: LogLevel.debug,
      );
      return true;
    }
  }

  Future<void> saveThumbnailsEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(thumbnailsEnabledKey, enabled);
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '保存缩略图开关失败: $e',
        level: LogLevel.debug,
      );
    }
  }

  // ------------------------------------------------- 目录快照（284 D7）

  static const String dirSnapshotKeyPrefix = 'remoteStorage.dirSnapshot.';

  String _dirSnapshotKey(String accountId, String path) =>
      '$dirSnapshotKeyPrefix$accountId|${path.isEmpty ? '/' : path}';

  /// 存一个目录的快照。条目数超上限、或发生任何异常 → 静默不存（快照是优化，
  /// 不该因为它失败而影响正常列表）。
  Future<void> saveDirSnapshot(
    String accountId,
    String path,
    List<RemoteStorageEntry> entries,
  ) async {
    if (entries.length > kDirSnapshotMaxEntries) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _dirSnapshotKey(accountId, path);
      await prefs.setString(
        key,
        encodeDirSnapshot(
          DirSnapshot(entries: entries, at: DateTime.now()),
        ),
      );
      await _pruneDirSnapshots(prefs, keepKey: key);
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '保存目录快照失败: $e',
        level: LogLevel.debug,
      );
    }
  }

  /// 只保留最新的 [kDirSnapshotMaxDirs] 个快照（按存的时间戳解析，坏的当最旧）。
  Future<void> _pruneDirSnapshots(
    SharedPreferences prefs, {
    required String keepKey,
  }) async {
    final keys = prefs
        .getKeys()
        .where((k) => k.startsWith(dirSnapshotKeyPrefix))
        .toList();
    if (keys.length <= kDirSnapshotMaxDirs) return;
    DateTime stampOf(String key) {
      final raw = prefs.getString(key);
      final snap = raw == null ? null : decodeDirSnapshot(raw);
      return snap?.at ?? DateTime.fromMillisecondsSinceEpoch(0);
    }

    keys.sort((a, b) => stampOf(a).compareTo(stampOf(b)));
    final drop = keys.length - kDirSnapshotMaxDirs;
    for (var i = 0; i < drop; i++) {
      if (keys[i] == keepKey) continue;
      await prefs.remove(keys[i]);
    }
  }

  Future<DirSnapshot?> loadDirSnapshot(String accountId, String path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_dirSnapshotKey(accountId, path));
      return raw == null ? null : decodeDirSnapshot(raw);
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '读取目录快照失败: $e',
        level: LogLevel.debug,
      );
      return null;
    }
  }

  /// 删账户时清掉该账户的全部快照（284 P1 的同一条原则：账户没了，
  /// 它的目录名/文件名不该留在本机）。
  Future<int> clearAccountSnapshots(String accountId) async {
    var removed = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefix = '$dirSnapshotKeyPrefix$accountId|';
      for (final key in prefs.getKeys().where((k) => k.startsWith(prefix))) {
        await prefs.remove(key);
        removed += 1;
      }
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '清理目录快照失败: $e',
        level: LogLevel.debug,
      );
    }
    return removed;
  }

  // ------------------------------------------------- 浏览页偏好（283 D2）

  static const String playbackSpeedKey = 'remoteStorage.playbackSpeed';

  /// 列表里给视频显示首帧的开关（284 D8）。默认开：用户要的就是"视频也有图"。
  static const String videoThumbnailsEnabledKey =
      'remoteStorage.videoThumbnailsEnabled';

  /// 传输限速（285 P2）：0 = 不限速。单位字节/秒。
  static const String transferRateLimitKey = 'remoteStorage.transferRateLimit';

  Future<int> loadTransferRateLimit() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt(transferRateLimitKey) ?? 0;
      return v < 0 ? 0 : v;
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '读取传输限速失败: $e',
        level: LogLevel.debug,
      );
      return 0;
    }
  }

  Future<void> saveTransferRateLimit(int bytesPerSecond) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        transferRateLimitKey,
        bytesPerSecond < 0 ? 0 : bytesPerSecond,
      );
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '保存传输限速失败: $e',
        level: LogLevel.debug,
      );
    }
  }

  /// 传输的网络条件策略（287 P1）。默认仅 Wi-Fi；坏值/缺值都回默认。
  static const String transferNetworkPolicyKey =
      'remoteStorage.transferNetworkPolicy';

  Future<TransferNetworkPolicy> loadTransferNetworkPolicy() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return networkPolicyFromName(prefs.getString(transferNetworkPolicyKey));
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '读取传输网络策略失败: $e',
        level: LogLevel.debug,
      );
      return TransferNetworkPolicy.wifiOnly;
    }
  }

  Future<void> saveTransferNetworkPolicy(TransferNetworkPolicy policy) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(transferNetworkPolicyKey, networkPolicyName(policy));
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '保存传输网络策略失败: $e',
        level: LogLevel.debug,
      );
    }
  }

  Future<bool> loadVideoThumbnailsEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(videoThumbnailsEnabledKey) ?? true;
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '读取视频首帧开关失败: $e',
        level: LogLevel.debug,
      );
      return true;
    }
  }

  Future<void> saveVideoThumbnailsEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(videoThumbnailsEnabledKey, enabled);
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '保存视频首帧开关失败: $e',
        level: LogLevel.debug,
      );
    }
  }

  static const String browserSortFieldKey = 'remoteStorage.browserSortField';
  static const String browserScrollOffsetsKey =
      'remoteStorage.browserScrollOffsets';

  /// 记住多少个目录的滚动位置；超了丢最早的（Map 是插入序）。
  static const int kMaxRememberedScrollOffsets = 200;

  /// 排序字段名（**枚举名字符串**，不 import presentation 层）。
  ///
  /// 数据层存字符串、由页面做 name↔枚举映射，是为了让这里不依赖 presentation：
  /// 数据层不认识 UI 类型，坏数据也不至于让整个偏好失效。
  Future<String?> loadBrowserSortFieldName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(browserSortFieldKey);
      return raw == null || raw.isEmpty ? null : raw;
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '读取排序偏好失败: $e',
        level: LogLevel.debug,
      );
      return null;
    }
  }

  Future<void> saveBrowserSortFieldName(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(browserSortFieldKey, name);
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '保存排序偏好失败: $e',
        level: LogLevel.debug,
      );
    }
  }

  /// 播放倍速（284 P4）：没存过、坏数据、不在档位表里的一律回落到 1×。
  ///
  /// 校验档位是有必要的：0 或负数会让播放器"卡住不动"，而用户只会觉得播放器坏了。
  Future<double> loadPlaybackSpeed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getDouble(playbackSpeedKey);
      if (raw == null) return 1;
      return kPlaybackSpeeds.contains(raw) ? raw : 1;
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '读取倍速偏好失败: $e',
        level: LogLevel.debug,
      );
      return 1;
    }
  }

  Future<void> savePlaybackSpeed(double speed) async {
    if (!kPlaybackSpeeds.contains(speed)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(playbackSpeedKey, speed);
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '保存倍速偏好失败: $e',
        level: LogLevel.debug,
      );
    }
  }

  /// 账户+目录 → 离开时的滚动偏移。读不到/坏数据一律当空（下次重来即可）。
  Future<Map<String, double>> loadBrowserScrollOffsets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(browserScrollOffsetsKey);
      if (raw == null || raw.isEmpty) return <String, double>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, double>{};
      final result = <String, double>{};
      decoded.forEach((key, value) {
        if (key is String && value is num) {
          final offset = value.toDouble();
          if (offset.isFinite && offset >= 0) result[key] = offset;
        }
      });
      return result;
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '读取滚动位置失败: $e',
        level: LogLevel.debug,
      );
      return <String, double>{};
    }
  }

  /// 删除账户时清掉它的滚动位置（键是 `accountId|path`），返回清掉的条数。
  ///
  /// 留着不清不会有功能问题，但"删了账户还留着它看过哪些目录"既占地方也接近隐私。
  Future<int> clearBrowserScrollOffsetsForAccount(String accountId) async {
    final prefix = '$accountId|';
    final offsets = await loadBrowserScrollOffsets();
    final kept = <String, double>{};
    for (final entry in offsets.entries) {
      if (!entry.key.startsWith(prefix)) kept[entry.key] = entry.value;
    }
    final removed = offsets.length - kept.length;
    if (removed > 0) await saveBrowserScrollOffsets(kept);
    return removed;
  }

  Future<void> saveBrowserScrollOffsets(Map<String, double> offsets) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = offsets.entries
          .where((e) => e.value.isFinite && e.value >= 0)
          .toList();
      final trimmed = entries.length > kMaxRememberedScrollOffsets
          ? entries.sublist(entries.length - kMaxRememberedScrollOffsets)
          : entries;
      await prefs.setString(
        browserScrollOffsetsKey,
        jsonEncode({for (final e in trimmed) e.key: e.value}),
      );
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '保存滚动位置失败: $e',
        level: LogLevel.debug,
      );
    }
  }
}
