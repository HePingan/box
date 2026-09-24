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
}
