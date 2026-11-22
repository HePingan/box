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

  /// 网址形式（二维码用）：`https://box.hpa888.top/p/CODE`。
  /// 与服务端 nginx 的 `location ^~ /p/` 和 `.well-known/assetlinks.json` 对齐。
  static const String webHost = 'box.hpa888.top';
  static const String webPath = '/p/';

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

    // 1) 自建 scheme：boxapp://plugin?c=CODE
    final match = RegExp(
      r'boxapp://plugin\?[^\s]*?\bc=([0-9A-Za-z]{4,32})',
      caseSensitive: false,
    ).firstMatch(text);
    if (match != null) return _normalize(match.group(1)!);

    // 2) https 落地页地址：https://box.hpa888.top/p/CODE
    //    二维码扫出来就是这个 —— 扫码器不认自建 scheme，只有 https 能被正常处理。
    final web = RegExp(
      r'https?://box\.hpa888\.top/p/([0-9A-Za-z]{4,32})',
      caseSensitive: false,
    ).firstMatch(text);
    if (web != null) return _normalize(web.group(1)!);

    // 3) 整串就是裸码（中间带空格的"7K2M 9Q"也认：分享码被排版折断是常事）
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    if (compact.length <= maxCodeLength &&
        RegExp(r'^[0-9A-Za-z]+$').hasMatch(compact)) {
      return _normalize(compact);
    }
    return '';
  }

  /// 二维码用的网址链接。
  ///
  /// 为什么不是 `boxapp://`：扫码器把它当地址丢给浏览器 → 未知协议 → 白屏
  /// （用户实测，微信/QQ/系统浏览器都一样）。https 才能被所有扫码器正常处理：
  /// App Links 校验通过时系统直接进 App，没通过就落到落地页，页面里有
  /// 「在 App 里打开」按钮和 6 位码可以手输。
  static String buildLink(String code) =>
      'https://$webHost$webPath${_normalize(code)}';

  /// 自建 scheme 形式，落地页的「在 App 里打开」按钮用它。
  static String schemeLink(String code) =>
      '$scheme://$host?c=${_normalize(code)}';

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

  /// 深链自检：系统是否已认领 [webHost]（App Links）、`boxapp://` 能否解析。
  ///
  /// **静态**：只发一次 method call，不碰任何 handler 状态 —— 从设置页随手调
  /// 不会把 gate 上挂着的 onCode 监听解绑（那样热启动的码就丢了）。
  ///
  /// 非 Android / 通道不可用时返回空 Map —— 调用方按「未知」显示，
  /// 不要把"查不到"误报成"没验证"。
  static Future<Map<String, Object?>> diagnose({MethodChannel? channel}) async {
    final ch = channel ?? const MethodChannel(channelName);
    try {
      final raw = await ch.invokeMethod<Map<Object?, Object?>>('diagnose');
      if (raw == null) return const <String, Object?>{};
      return raw.map((k, v) => MapEntry(k.toString(), v));
    } on MissingPluginException {
      return const <String, Object?>{};
    } catch (e) {
      return <String, Object?>{'error': '$e'};
    }
  }
}
