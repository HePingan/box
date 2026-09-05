import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_system/widgets/app_back_button.dart';
import '../design_system/widgets/app_page_scaffold.dart';
import '../utils/app_logger.dart';
import '../utils/log_channels.dart';

/// 统一调试日志页。
///
/// 改造前这里是一整块 `SelectableText`，把 1000 行日志一次性铺出来，
/// 用户报障时得自己在里面翻找。现在按频道 + 级别筛选：
/// 报「视频卡」筛「播放」，报「继续阅读跳错位置」筛「阅读」，
/// 只想看出错的就点「仅错误」。
///
/// 复制行为跟随当前筛选——用户看到的就是复制走的，避免他以为只发了播放日志
/// 结果糊了 1000 行过来，也避免他筛了错误却复制到全量。
class DebugLogPage extends StatefulWidget {
  const DebugLogPage({super.key});

  @override
  State<DebugLogPage> createState() => _DebugLogPageState();
}

class _DebugLogPageState extends State<DebugLogPage> {
  /// null 表示「全部频道」。
  LogChannel? _channel;

  /// 只看 warn/error。
  bool _errorsOnly = false;

  List<LogEntry> _visible(List<String> raw) {
    final entries = raw.map((e) => LogEntry.parse(e));
    return entries
        .where((e) {
          if (_channel != null && e.channel != _channel) return false;
          if (_errorsOnly &&
              e.level != LogLevel.error &&
              e.level != LogLevel.warn) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  Future<void> _copyVisible(List<LogEntry> visible) async {
    // 复制当前可见内容，而不是无脑全量——见类文档说明。
    final text = visible.map((e) => e.raw).join('\n');
    await Clipboard.setData(ClipboardData(text: text));

    if (!mounted) return;
    final scope = _channel?.label ?? '全部';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已复制${visible.length}行（$scope）')));
  }

  Future<void> _clearAll() async {
    await AppLogger.instance.clear();

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('日志已清空')));
  }

  @override
  Widget build(BuildContext context) {
    return SafeValueListenableBuilder<List<String>>(
      valueListenable: AppLogger.instance.lines,
      builder: (context, raw, _) {
        final visible = _visible(raw);

        return Scaffold(
          appBar: AppBar(
            title: const Text('调试日志'),
            leading: AppBackButton(onPressed: () => Navigator.pop(context)),
            actions: [
              IconButton(
                tooltip: _errorsOnly ? '显示全部级别' : '仅看警告与错误',
                icon: Icon(
                  _errorsOnly
                      ? Icons.filter_alt_rounded
                      : Icons.filter_alt_outlined,
                ),
                onPressed: () => setState(() => _errorsOnly = !_errorsOnly),
              ),
              IconButton(
                tooltip: '复制当前筛选结果',
                icon: const Icon(Icons.copy_rounded),
                onPressed: visible.isEmpty ? null : () => _copyVisible(visible),
              ),
              IconButton(
                tooltip: '清空日志',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: raw.isEmpty ? null : _clearAll,
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                _ChannelBar(
                  raw: raw,
                  selected: _channel,
                  onSelect: (c) => setState(() => _channel = c),
                ),
                const Divider(height: 1),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Text(
                            raw.isEmpty
                                ? '暂无日志'
                                : '当前筛选没有匹配的日志\n共 ${raw.length} 行，换个分类看看',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            return _LogLine(entry: visible[index]);
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 频道筛选条。只显示**当前真有日志**的频道，避免一排点了全空的空壳按钮。
class _ChannelBar extends StatelessWidget {
  const _ChannelBar({
    required this.raw,
    required this.selected,
    required this.onSelect,
  });

  final List<String> raw;
  final LogChannel? selected;
  final ValueChanged<LogChannel?> onSelect;

  @override
  Widget build(BuildContext context) {
    final counts = <LogChannel, int>{};
    for (final line in raw) {
      final channel = LogEntry.parse(line).channel;
      counts[channel] = (counts[channel] ?? 0) + 1;
    }

    final present = LogChannel.values
        .where((c) => (counts[c] ?? 0) > 0)
        .toList(growable: false);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          ChoiceChip(
            label: Text('全部 ${raw.length}'),
            selected: selected == null,
            onSelected: (_) => onSelect(null),
          ),
          for (final channel in present) ...[
            const SizedBox(width: 8),
            ChoiceChip(
              key: ValueKey('log_channel_${channel.tag}'),
              label: Text('${channel.label} ${counts[channel]}'),
              selected: selected == channel,
              onSelected: (_) => onSelect(channel),
            ),
          ],
        ],
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    // 只给警告和错误上色。全彩会让整屏花掉，反而看不出重点。
    final Color? color = switch (entry.level) {
      LogLevel.error => Colors.red.shade700,
      LogLevel.warn => Colors.orange.shade800,
      _ => null,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SelectableText(
        entry.raw,
        style: TextStyle(
          fontSize: 12,
          height: 1.45,
          fontFamily: 'monospace',
          color: color,
        ),
      ),
    );
  }
}
