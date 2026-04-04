import 'dart:convert';

class UpdateManifest {
  final int schemaVersion;
  final String appId;
  final String platform;
  final String channel;
  final String packageName;

  final int latestVersionCode;
  final String latestVersionName;
  final int minSupportedVersionCode;
  final List<int> blockedVersionCodes;
  final bool forceUpdate;

  final String? title;
  final String? notice;
  final List<String> changelog;

  final String downloadUrl;
  final String? backupDownloadUrl;
  final String? sha256;
  final int? fileSize;
  final String? publishedAt;
  final String? supportUrl;

  final String? signatureAlgorithm;
  final String? signature;

  UpdateManifest({
    required this.schemaVersion,
    required this.appId,
    required this.platform,
    required this.channel,
    required this.packageName,
    required this.latestVersionCode,
    required this.latestVersionName,
    required this.minSupportedVersionCode,
    required this.blockedVersionCodes,
    required this.forceUpdate,
    required this.title,
    required this.notice,
    required this.changelog,
    required this.downloadUrl,
    required this.backupDownloadUrl,
    required this.sha256,
    required this.fileSize,
    required this.publishedAt,
    required this.supportUrl,
    required this.signatureAlgorithm,
    required this.signature,
  });

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    return UpdateManifest(
      schemaVersion: int.tryParse(json['schemaVersion']?.toString() ?? '1') ?? 1,
      appId: json['appId']?.toString() ?? '',
      platform: json['platform']?.toString() ?? '',
      channel: json['channel']?.toString() ?? 'release',
      packageName: json['packageName']?.toString() ?? '',
      latestVersionCode: int.tryParse(json['latestVersionCode']?.toString() ?? '0') ?? 0,
      latestVersionName: json['latestVersionName']?.toString() ?? '',
      minSupportedVersionCode:
          int.tryParse(json['minSupportedVersionCode']?.toString() ?? '0') ?? 0,
      blockedVersionCodes: (json['blockedVersionCodes'] as List<dynamic>? ?? [])
          .map((e) => int.tryParse(e.toString()) ?? 0)
          .where((e) => e > 0)
          .toList(),
      forceUpdate: json['forceUpdate'] == true || json['forceUpdate'] == 1,
      title: json['title']?.toString(),
      notice: json['notice']?.toString(),
      changelog: (json['changelog'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      downloadUrl: json['downloadUrl']?.toString() ?? '',
      backupDownloadUrl: json['backupDownloadUrl']?.toString(),
      sha256: json['sha256']?.toString(),
      fileSize: json['fileSize'] == null
          ? null
          : int.tryParse(json['fileSize'].toString()),
      publishedAt: json['publishedAt']?.toString(),
      supportUrl: json['supportUrl']?.toString(),
      signatureAlgorithm: json['signatureAlgorithm']?.toString(),
      signature: json['signature']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'appId': appId,
      'platform': platform,
      'channel': channel,
      'packageName': packageName,
      'latestVersionCode': latestVersionCode,
      'latestVersionName': latestVersionName,
      'minSupportedVersionCode': minSupportedVersionCode,
      'blockedVersionCodes': blockedVersionCodes,
      'forceUpdate': forceUpdate,
      'title': title,
      'notice': notice,
      'changelog': changelog,
      'downloadUrl': downloadUrl,
      'backupDownloadUrl': backupDownloadUrl,
      'sha256': sha256,
      'fileSize': fileSize,
      'publishedAt': publishedAt,
      'supportUrl': supportUrl,
      'signatureAlgorithm': signatureAlgorithm,
      'signature': signature,
    };
  }
/// 只有“确实存在新版本”的情况下，强制更新才生效。
  bool needForceUpdate(int currentVersionCode) {
    // 【核心拦截】：如果服务端的版本号 <= 手机现在的版本号，
    // 说明根本没新版本！管后台怎么勾【强制更新】，一律当做 false 处理！
    if (latestVersionCode <= currentVersionCode) {
      return false;
    }

    // 只有在【真有新版本】的前提下，才去看后台是不是要求强更
    return forceUpdate ||
        currentVersionCode < minSupportedVersionCode ||
        blockedVersionCodes.contains(currentVersionCode);
  }

  /// 判断是否有新版本
  bool hasNewVersion(int currentVersionCode) {
    return currentVersionCode < latestVersionCode;
  }

  String prettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}