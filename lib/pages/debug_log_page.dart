import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_system/widgets/app_back_button.dart';
import '../design_system/widgets/app_page_scaffold.dart';
import 'package:share_plus/share_plus.dart';

import '../utils/app_logger.dart';
import '../utils/diagnostic_report.dart';
import '../utils/log_channels.dart';

/// 统一调试日志页。
///
/// 改造前这里是一整块 `SelectableText`，把 1000 行日志一次性铺出来，
/// 用户报障时得自己在里面翻找。现在按频道 + 级别筛选：
/// 报「视频卡」筛「播放」，报「继续阅读跳错位置」筛「阅读」，
/// 只想看出错的就点「仅错误」。
///
/// 再加一层**关键字搜索**：频道筛选解决「知道是哪个模块」的场景，
/// 但真实报障常常只知道一个字符串——题目 ID（`q_7gZgweMXMRQd`）、
/// 一个数字（`cursor=4900`）、一段接口名（`/api/quiz/sync`）。
/// 1000 行里靠肉眼翻这些是找不到的，这也正是用户说的「我找不到那个」。
/// 搜索按**整行原文**匹配（大小写不敏感），所以行内任意片段都能搜到，
/// 且能与频道、级别筛选叠加，三者取交集。
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

  /// 关键字搜索。空串表示不筛。
  ///
  /// 用 controller 而不是裸 String，是为了让「清空」按钮与输入框同步，
  /// 也让系统键盘的清除键能正常回写状态。
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// 当前搜索词（已 trim）。空串 = 不按关键字筛。
  String get _query => _search.text.trim();

  List<LogEntry> _visible(List<String> raw) {
    final entries = raw.map((e) => LogEntry.parse(e));
    // 搜索大小写不敏感：用户敲的是 `hasmore`，日志里是 `hasMore`。
    final needle = _query.toLowerCase();
    return entries
        .where((e) {
          if (_channel != null && e.channel != _channel) return false;
          if (_errorsOnly &&
              e.level != LogLevel.error &&
              e.level != LogLevel.warn &&
              // 频道兜底：升级前记下的崩溃行没有级别段（解析成 info），
              // 只按级别过滤会把最关键的崩溃现场筛掉。
              e.channel != LogChannel.error) {
            return false;
          }
          // 匹配整行原文而不是 message：时间戳、tag、级别段也都能搜，
          // 报障的人可能只想找某个时间点或某个频道标签。
          if (needle.isNotEmpty && !e.raw.toLowerCase().contains(needle)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  String get _scopeLabel {
    final channel = _channel?.label ?? '全部';
    final base = _errorsOnly ? '$channel · 仅警告与错误' : channel;
    return _query.isEmpty ? base : '$base · 搜索「$_query」';
  }

  /// 组装带设备上下文的诊断报告。
  ///
  /// 报障的人多半没有 adb，只能手动复制。裸日志缺机型和版本号，
  /// 每次都要再追问一轮，所以这里直接把上下文打进报告头部。
  ///
  /// 头部走**启动时预取的缓存**、同步读取：复制是报障的核心动作，
  /// 不能为了一个可选的版本号去等 platform channel。
  String _buildReport(List<LogEntry> visible) {
    return DiagnosticReport.compose(
      header: DiagnosticHeader.cachedOrPlaceholder,
      entries: visible,
      scopeLabel: _scopeLabel,
    );
  }

  Future<void> _copyVisible(List<LogEntry> visible) async {
    // 复制当前可见内容，而不是无脑全量——见类文档说明。
    final report = _buildReport(visible);
    await Clipboard.setData(ClipboardData(text: report));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制${visible.length}行（$_scopeLabel）')),
    );
  }

  /// 直接调起系统分享，省掉「复制 → 切到聊天 → 粘贴」这几步。
  Future<void> _shareVisible(List<LogEntry> visible) async {
    final report = _buildReport(visible);

    try {
      await SharePlus.instance.share(
        ShareParams(text: report, subject: 'Box 诊断报告（$_scopeLabel）'),
      );
    } catch (e) {
      if (!mounted) return;
      // 分享失败不能让日志发不出去——退回剪贴板。
      await Clipboard.setData(ClipboardData(text: report));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('分享不可用，已复制到剪贴板')));
    }
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
                tooltip: '分享诊断报告',
                icon: const Icon(Icons.ios_share_rounded),
                onPressed: visible.isEmpty
                    ? null
                    : () => _shareVisible(visible),
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
                _SearchField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                ),
                _ChannelBar(
                  raw: raw,
                  selected: _channel,
                  onSelect: (c) => setState(() => _channel = c),
                ),
                const Divider(height: 1),
                if (visible.isNotEmpty)
                  _ResultCountBar(shown: visible.length, total: raw.length),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _emptyHint(raw),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      // 倒序展示：最新的在最上面。
                      //
                      // 日志是 1000 行环形缓冲，正序铺开时用户打开这一页看到的
                      // 是几小时前的启动日志，要报障得先手动滚到底。而报障场景
                      // 恰恰是「刚出问题、马上来复制」，最新几十行才是现场。
                      //
                      // 注意只有**展示**倒序，[DiagnosticReport] 正文仍是时间
                      // 正序 —— 报告给开发者顺着读，正序才能看出因果。
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            return _LogLine(
                              entry: visible[visible.length - 1 - index],
                            );
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

  /// 空状态文案。要说清楚**是哪一层**把日志筛没了，否则用户只会觉得
  /// 「日志丢了」——这正是搜索功能要解决的困惑来源。
  String _emptyHint(List<String> raw) {
    if (raw.isEmpty) return '暂无日志';
    if (_query.isNotEmpty) {
      return '没有包含「$_query」的日志\n共 ${raw.length} 行，换个关键字或清空搜索看看';
    }
    return '当前筛选没有匹配的日志\n共 ${raw.length} 行，换个分类看看';
  }
}

/// 关键字搜索框。
///
/// 放在频道条**上方**：真实报障往往是先知道一个字符串（题目 ID、接口名、
/// 报错片段）才反推模块，而不是先知道模块再找字符串。把搜索放第一位
/// 对应这个顺序。
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final hasText = controller.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: TextField(
        key: const ValueKey('log_search_field'),
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          hintText: '搜索日志（题干ID、接口名、报错片段…）',
          hintStyle: TextStyle(
            fontSize: 13,
            color: Theme.of(context).hintColor,
          ),
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: hasText
              ? IconButton(
                  key: const ValueKey('log_search_clear'),
                  tooltip: '清空搜索',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        ),
      ),
    );
  }
}

/// 「显示 N / 共 M 行」。
///
/// 用户筛完看不到东西时，最怕的是「日志没了」。这一行始终说明
/// 全量还在，只是被条件挡了一部分。
class _ResultCountBar extends StatelessWidget {
  const _ResultCountBar({required this.shown, required this.total});

  final int shown;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = shown != total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: [
          Text(
            filtered ? '显示 $shown / 共 $total 行' : '共 $total 行',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.hintColor,
            ),
          ),
        ],
      ),
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
