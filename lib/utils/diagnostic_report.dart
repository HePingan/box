import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_logger.dart';
import 'log_channels.dart';

/// 诊断报告的头部信息。
///
/// 为什么需要它：报障的人常是没有 adb 的普通用户，只能手动复制日志发过来。
/// 而裸日志里没有机型、系统版本、App 版本——恰恰是分屏、播放器这类问题
/// 最先要问的三样。以前每次都要来回追问一轮，现在复制即自带。
@immutable
class DiagnosticHeader {
  const DiagnosticHeader({
    required this.appVersion,
    required this.buildNumber,
    required this.packageName,
    required this.osVersion,
    required this.generatedAt,
  });

  final String appVersion;
  final String buildNumber;
  final String packageName;
  final String osVersion;
  final DateTime generatedAt;

  /// 收集真实设备信息。
  ///
  /// 每一项都单独兜底：拿不到版本号也要把日志发出去，不能因为
  /// package_info 失败就让整个报障流程断掉。
  /// [timeout] 是硬上限：`PackageInfo` 要跨一次 platform channel，
  /// 插件没注册或 ROM 异常时这个调用可能迟迟不返回。报障流程本身绝不能卡住
  /// ——拿不到版本号就写「未知」继续，日志比版本号重要得多。
  static Future<DiagnosticHeader> collect({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    String appVersion = '未知';
    String buildNumber = '未知';
    String packageName = '未知';

    try {
      final info = await PackageInfo.fromPlatform().timeout(timeout);
      appVersion = info.version;
      buildNumber = info.buildNumber;
      packageName = info.packageName;
    } catch (_) {
      // MissingPluginException / TimeoutException 都走这里：
      // 保持「未知」，不阻断报告生成。
    }

    return DiagnosticHeader(
      appVersion: appVersion,
      buildNumber: buildNumber,
      packageName: packageName,
      osVersion: _osVersion(),
      generatedAt: DateTime.now(),
    );
  }

  /// 启动时预取到的头部信息。
  ///
  /// 为什么要缓存：复制/分享日志是报障的**核心动作**，不该为了一个可选的
  /// 版本号去等 platform channel。插件没注册或 ROM 异常时那次 await 可能
  /// 迟迟不返回，用户点复制却毫无反应——报障流程自己失效，最不该发生。
  /// 启动时取一次存下来，之后复制路径全程同步。
  static DiagnosticHeader? _cached;

  /// 同步读取头部信息。取不到缓存就返回一份「未知」占位，绝不阻塞。
  static DiagnosticHeader get cachedOrPlaceholder =>
      _cached ??
      DiagnosticHeader(
        appVersion: '未知',
        buildNumber: '未知',
        packageName: '未知',
        osVersion: _osVersion(),
        generatedAt: DateTime.now(),
      );

  /// 应用启动时调用一次，把版本信息缓存下来。失败不抛，只是后续显示「未知」。
  static Future<void> prime() async {
    try {
      _cached = await collect();
    } catch (_) {
      // 预取失败不影响任何功能，复制时会落到占位值。
    }
  }

  @visibleForTesting
  static void resetCacheForTest([DiagnosticHeader? header]) {
    _cached = header;
  }

  static String _osVersion() {
    try {
      return Platform.operatingSystemVersion;
    } catch (_) {
      return '未知';
    }
  }

  List<String> toLines() => [
    'App 版本: $appVersion ($buildNumber)',
    '包名: $packageName',
    '系统: ${Platform.operatingSystem} $osVersion',
    '生成时间: ${generatedAt.toIso8601String()}',
  ];
}

/// 把日志组装成可直接粘贴给开发者的诊断报告。
class DiagnosticReport {
  const DiagnosticReport._();

  /// 生成报告文本。
  ///
  /// [entries] 是**当前筛选后**可见的日志，保持「看到的就是发出去的」这个约定。
  /// [scopeLabel] 写进头部，让接收方一眼知道这是全量还是某个分类。
  static String compose({
    required DiagnosticHeader header,
    required List<LogEntry> entries,
    required String scopeLabel,
  }) {
    final buffer = StringBuffer()
      ..writeln('===== Box 诊断报告 =====')
      ..writeln('日志范围: $scopeLabel')
      ..writeln('日志行数: ${entries.length}');

    for (final line in header.toLines()) {
      buffer.writeln(line);
    }

    // 分频道计数放在头部：接收方不用翻完全文就知道错误有几条。
    final counts = channelCounts(entries);
    if (counts.isNotEmpty) {
      final summary = counts.entries
          .map((e) => '${e.key.label}${e.value}')
          .join(' / ');
      buffer.writeln('分类统计: $summary');
    }

    buffer
      ..writeln('===== 日志正文 =====')
      ..writeln(entries.map((e) => e.raw).join('\n'));

    if (entries.isEmpty) {
      buffer.writeln('(当前筛选下没有日志)');
    }

    return buffer.toString();
  }

  /// 按频道统计条数，只返回真有日志的频道，顺序跟随枚举定义。
  static Map<LogChannel, int> channelCounts(List<LogEntry> entries) {
    final counts = <LogChannel, int>{};
    for (final entry in entries) {
      counts[entry.channel] = (counts[entry.channel] ?? 0) + 1;
    }
    return {
      for (final channel in LogChannel.values)
        if ((counts[channel] ?? 0) > 0) channel: counts[channel]!,
    };
  }

  /// 便捷入口：取全量日志生成报告。
  static Future<String> composeAll() async {
    final header = await DiagnosticHeader.collect();
    final entries = AppLogger.instance.lines.value
        .map(LogEntry.parse)
        .toList(growable: false);
    return compose(header: header, entries: entries, scopeLabel: '全部');
  }
}
