// 分享接收闸门（286 P3）：挂在 home 之下、Navigator 之上，
// 这样热启动（App 正在别的页面）收到分享也能把面板盖在当前页面之上。
//
// 两个来源都要收：
//   * 冷启动：[markReady] → [takePending]（原生在 Dart 就绪前先攒着）；
//   * 热启动：监听 `onSharedFiles`。
// 面板一次只弹一个：连收两次分享时后面那次并入当前面板，避免盖两层。
library;

import 'dart:async';

import 'package:box/features/extensions/plugins/remote_storage/data/share_inbox_channel.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/share_inbox_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/presentation/share_inbox_sheet.dart';
import 'package:flutter/material.dart';

class ShareInboxGate extends StatefulWidget {
  const ShareInboxGate({super.key, required this.child, this.channel});

  final Widget child;

  /// 测试可注入；默认用真实通道（非 Android 上静默降级）。
  final ShareInboxChannel? channel;

  @override
  State<ShareInboxGate> createState() => _ShareInboxGateState();
}

class _ShareInboxGateState extends State<ShareInboxGate> {
  late final ShareInboxChannel _channel = widget.channel ?? ShareInboxChannel();
  StreamSubscription<List<SharedInboxFile>>? _subscription;
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    _subscription = _channel.onSharedFiles.listen(_show);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _channel.markReady();
    final pending = await _channel.takePending();
    if (pending.isNotEmpty) _show(pending);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    // 只有自己建的通道才需要销毁（注入的由调用方管）。
    if (widget.channel == null) unawaited(_channel.dispose());
    super.dispose();
  }

  void _show(List<SharedInboxFile> files) {
    if (!mounted || files.isEmpty) return;
    if (_sheetOpen) {
      // 面板已经开着：先把旧的收掉，再弹新的（用户看到的是"又收到一次"）。
      Navigator.of(context, rootNavigator: true).pop();
      _sheetOpen = false;
    }
    _sheetOpen = true;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ShareInboxSheet(files: files),
    ).whenComplete(() => _sheetOpen = false);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
