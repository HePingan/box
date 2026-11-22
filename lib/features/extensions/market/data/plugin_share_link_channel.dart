// 插件分享码深链通道（boxapp://plugin?c=CODE）。
//
// 只在 Android 有实现（见 DeepLinkReceiver.kt）。其它平台/测试环境没有这个通道
// → `MissingPluginException` → 当成"没有深链"，绝不影响其它功能。
//
// 两种启动路径，与分享接收完全同构：
//   * 冷启动：Intent 在 Dart handler 挂上之前就到了，原生先攒着 → [takePendingCode]。
//   * 热启动：Dart 已就绪，原生直接推过来 → [onCode]。
// 冷启动前必须先 [markReady]（告诉原生"handler 挂了、可以推了"）。
import 'dart:async';

import 'package:box/utils/app_logger.dart';
import 'package:box/utils/log_channels.dart';
import 'package:flutter/services.dart';

class PluginShareLinkChannel {
  PluginShareLinkChannel({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'top.hpa888.box/plugin_deeplink';

  /// 深链 scheme/host：`boxapp://plugin?c=CODE`。
  static const String scheme = 'boxapp';
  static const String host = 'plugin';

  /// 码长度上限，与服务端 6 位留余量。超长的一律当无效。
  static const int maxCodeLength = 32;

  final MethodChannel _channel;

  final StreamController<String> _incoming = StreamController<String>.broadcast();

  /// 热启动时原生推过来的码。
  Stream<String> get onCode => _incoming.stream;

  bool _listening = false;

  /// 从任意字符串里认出分享码。
  ///
  /// 接受三种形状，因为用户可能从不同地方粘过来：
  ///   * 完整深链 `boxapp://plugin?c=7K2M9Q`（扫码/点链接的原文）
  ///   * 裸码 `7K2M9Q`
  ///   * 一段话里夹着深链（分享文案常带前后缀）
  ///
  /// 认不出就返回空串 —— 调用方据此提示"这不是分享码"，而不是拿垃圾去请求。
  static String parseShareCode(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return '';

    // 1) 整串就是深链或其中一段
    final match = RegExp(
      r'boxapp://plugin\?[^\s]*?\bc=([0-9A-Za-z]{4,32})',
      caseSensitive: false,
    ).firstMatch(text);
    if (match != null) return _normalize(match.group(1)!);

    // 2) 整串就是裸码（中间带空格的"7K2M 9Q"也认：分享码被排版折断是常事）
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    if (compact.length <= maxCodeLength &&
        RegExp(r'^[0-9A-Za-z]+$').hasMatch(compact)) {
      return _normalize(compact);
    }
    return '';
  }

  /// 生成给二维码用的深链。
  static String buildLink(String code) => '$scheme://$host?c=${_normalize(code)}';

  static String _normalize(String code) => code.trim().toUpperCase();

  /// 挂上 handler 并告诉原生"可以推了"。重复调用无副作用。
  Future<void> markReady() async {
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onPluginCode') {
          final args = call.arguments;
          final raw = args is Map ? args['code']?.toString() : args?.toString();
          final code = parseShareCode(raw);
          if (code.isNotEmpty) _incoming.add(code);
        }
        return null;
      });
    }
    try {
      await _channel.invokeMethod<bool>('ready');
    } on MissingPluginException {
      // 非 Android：没有实现，什么都不做。
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '深链通道就绪通知失败: $e',
        level: LogLevel.debug,
      );
    }
  }

  /// 取走冷启动时攒下的码（取完原生侧即清空，不会重复提示）。
  Future<String> takePendingCode() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('takePending');
      return parseShareCode(raw?.toString());
    } on MissingPluginException {
      return '';
    } catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '读取深链暂存失败: $e',
        level: LogLevel.debug,
      );
      return '';
    }
  }

  Future<void> dispose() async {
    _listening = false;
    _channel.setMethodCallHandler(null);
    await _incoming.close();
  }
}
