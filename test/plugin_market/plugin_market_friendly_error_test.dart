// P2-4 回归测试：插件市场的用户可见错误提示必须走单一事实源。
//
// 已修复的真实缺陷：UI 层（市场页 / 投稿页）各自抄了一份弱化版 `_err()`，
// 只识别 PluginMarketApiException，其余一律 `e.toString()`。于是超时/断网时
// 用户看到的是裸的 `SocketException: ...` / `TimeoutException: ...` 而不是
// 可读中文提示（API 层本已有正确实现，UI 层没复用）。
//
// 修复：提升为 `pluginMarketFriendlyError()`（plugin_market_api.dart），
// 所有 UI 委托它。

import 'dart:async';
import 'dart:io';

import 'package:box/features/extensions/market/data/plugin_market_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pluginMarketFriendlyError 必须给出可读中文提示', () {
    test('TimeoutException → 可读提示，且不含裸类名', () {
      final msg = pluginMarketFriendlyError(
        TimeoutException('boom', const Duration(seconds: 1)),
      );
      expect(msg.contains('超时'), isTrue, reason: '应提示超时：$msg');
      expect(msg.contains('TimeoutException'), isFalse,
          reason: '不应向用户暴露裸异常类名：$msg');
    });

    test('SocketException → 可读提示，且不含裸类名', () {
      final msg = pluginMarketFriendlyError(
        const SocketException('Connection refused'),
      );
      expect(msg.contains('网络'), isTrue, reason: '应提示网络问题：$msg');
      expect(msg.contains('SocketException'), isFalse,
          reason: '不应向用户暴露裸异常类名：$msg');
      expect(msg.contains('Connection refused'), isFalse,
          reason: '不应向用户暴露英文 errno 文本：$msg');
    });

    test('PluginMarketApiException → 走 friendlyMessage（含 code 场景）', () {
      final msg = pluginMarketFriendlyError(
        const PluginMarketApiException('原始信息', code: 'daily_limit'),
      );
      expect(msg.contains('今日投稿已达上限'), isTrue, reason: '应按 code 映射：$msg');
    });

    test('未知异常 → 仍给出「操作失败」前缀而非裸 toString', () {
      final msg = pluginMarketFriendlyError(StateError('weird'));
      expect(msg.startsWith('操作失败'), isTrue, reason: '$msg');
    });
  });
}
