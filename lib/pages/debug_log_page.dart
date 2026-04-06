import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/app_logger.dart';

class DebugLogPage extends StatelessWidget {
  const DebugLogPage({super.key});

  Future<void> _copyAll(BuildContext context) async {
    final text = await AppLogger.instance.exportText();
    await Clipboard.setData(ClipboardData(text: text));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('日志已复制到剪贴板')),
      );
    }
  }

  Future<void> _clearAll(BuildContext context) async {
    await AppLogger.instance.clear();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('日志已清空')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('调试日志'),
        actions: [
          IconButton(
            tooltip: '复制全部',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () => _copyAll(context),
          ),
          IconButton(
            tooltip: '清空日志',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _clearAll(context),
          ),
        ],
      ),
      body: SafeArea(
        child: ValueListenableBuilder<List<String>>(
          valueListenable: AppLogger.instance.lines,
          builder: (context, lines, _) {
            if (lines.isEmpty) {
              return const Center(
                child: Text('暂无日志'),
              );
            }

            final text = lines.join('\n');

            return SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                text,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  fontFamily: 'monospace',
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}