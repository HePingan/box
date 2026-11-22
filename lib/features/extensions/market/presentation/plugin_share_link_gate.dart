// 深链闸门：处理 `boxapp://plugin?c=CODE`（扫码/点链接进来的分享码）。
//
// 挂在 home 之下、Navigator 之上（与 ShareInboxGate 同一位置、同一理由）：
//   * 放在 MaterialApp.builder 里拿不到 Navigator，弹不出确认框；
//   * 放在 BoxApp 之外又会被用户切页绕过。
//
// 为什么必须先问用户再导入：这个码是**别人**给的。静默把别人的配置合并进用户
// 现有插件列表，等于允许外部链接改本机配置 —— 哪怕内容过了校验也一样。
library;

import 'dart:async';
import 'dart:convert';

import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:box/features/extensions/market/data/plugin_market_api.dart';
import 'package:box/features/extensions/market/data/plugin_share_link_channel.dart';
import 'package:flutter/material.dart';

class PluginShareLinkGate extends StatefulWidget {
  const PluginShareLinkGate({
    super.key,
    required this.child,
    this.channel,
    this.api,
    this.host,
  });

  final Widget child;

  /// 以下三个都可注入，便于单测；默认走真实实现。
  final PluginShareLinkChannel? channel;
  final PluginMarketApi? api;
  final HomePluginHost? host;

  @override
  State<PluginShareLinkGate> createState() => _PluginShareLinkGateState();
}

class _PluginShareLinkGateState extends State<PluginShareLinkGate> {
  late final PluginShareLinkChannel _channel =
      widget.channel ?? PluginShareLinkChannel();
  late final PluginMarketApi _api = widget.api ?? PluginMarketApi();
  late final HomePluginHost _host = widget.host ?? HomePluginHost.instance;

  StreamSubscription<String>? _subscription;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _subscription = _channel.onCode.listen(_handleCode);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _channel.markReady();
    final pending = await _channel.takePendingCode();
    if (pending.isNotEmpty) await _handleCode(pending);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    // 只有自己建的通道才销毁（注入的由调用方管）。
    if (widget.channel == null) unawaited(_channel.dispose());
    super.dispose();
  }

  Future<void> _handleCode(String code) async {
    if (!mounted || code.isEmpty) return;
    // 连点两个分享链接时只处理第一个：两个确认框叠在一起没人看得懂。
    // 丢掉的码用户再点一次链接就行，不值得为此排队。
    if (_busy) return;
    _busy = true;
    try {
      String payload;
      try {
        payload = await _api.fetchSharePayload(code);
      } catch (e) {
        _snack('分享码 $code 取不到内容：$e');
        return;
      }
      if (!mounted) return;

      final summary = _summarize(payload);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('收到插件分享'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('分享码：$code'),
              const SizedBox(height: 8),
              Text(summary),
              const SizedBox(height: 12),
              const Text(
                '导入会把里面的插件合并到现有配置（不会删掉你已有的插件）。',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('导入'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      final result = await _host.importSnapshotJson(payload, merge: true);
      final snap = _host.snapshot();
      final rejectText = result.hasRejects
          ? '；已跳过 ${result.rejected.length} 个（${result.rejected.take(2).join('；')}）'
          : '';
      _snack('已导入 ${result.imported} 个插件$rejectText；当前自定义插件 ${snap.customPlugins.length} 个');
    } catch (e) {
      _snack('导入失败：$e');
    } finally {
      _busy = false;
    }
  }

  /// 给确认框看的摘要：几个插件、叫什么。解析不了就诚实说"内容无法识别"。
  String _summarize(String payload) {
    try {
      final decoded = jsonDecode(payload);
      final plugins = (decoded is Map) ? decoded['customPlugins'] : null;
      if (plugins is! List || plugins.isEmpty) return '分享内容里没有插件';
      final names = plugins
          .whereType<Map>()
          .map((p) {
            final title = (p['title'] ?? '').toString().trim();
            final id = (p['id'] ?? '').toString();
            return title.isEmpty ? id : title;
          })
          .where((s) => s.isNotEmpty)
          .take(5)
          .toList();
      final more = plugins.length > names.length ? ' 等 ${plugins.length} 个' : '';
      return '含 ${plugins.length} 个插件：${names.join('、')}$more';
    } catch (_) {
      return '分享内容无法识别';
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
