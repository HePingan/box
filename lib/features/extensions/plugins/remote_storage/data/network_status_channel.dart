import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/network_policy.dart';

/// 网络类型通道（287 P1）。原生只上报"现在是什么网"，不替 Dart 做决定。
///
/// 两档失败立场，刻意分开：
/// - **完全读不到**（通道不存在、原生抛错）→ 返回 null = "没有情报"，队列**不拦**。
///   否则 web/桌面等没有这个通道的平台会把传输静默停死。
/// - **读到了但不认识**（VPN、原生报了个没见过的值）→ [NetworkKind.other]，
///   策略里按移动网络对待（保守拦），最坏情况是多问用户一句。
class NetworkStatusChannel {
  NetworkStatusChannel({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  static const String channelName = 'top.hpa888.box/network_status';

  final MethodChannel _channel;
  final StreamController<NetworkKind> _changes =
      StreamController<NetworkKind>.broadcast();

  /// 原生推来的网络变化（Wi-Fi 断/连、移动网络开关）。
  Stream<NetworkKind> get changes => _changes.stream;

  /// 主动问一次当前网络类型；**拿不到情报时返回 null**（调用方据此不拦传输）。
  Future<NetworkKind?> current() async {
    try {
      final raw = await _channel.invokeMethod<String>('currentNetworkType');
      if (raw == null) return null;
      return networkKindFromName(raw);
    } catch (_) {
      // 通道没实现（web/桌面、老版本原生侧、测试替身）或原生抛错 → 没有情报。
      return null;
    }
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method == 'networkChanged') {
      _changes.add(networkKindFromName(call.arguments as String?));
    }
    return null;
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    unawaited(_changes.close());
  }
}
