import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 阅读器调试日志服务（仅用于诊断继续阅读bug）
class ReaderDebugLog {
  static const _kLogKey = 'reader_debug_log';
  static const _kMaxLines = 200;
  
  static final _logs = <String>[];
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final saved = _prefs?.getString(_kLogKey);
    if (saved != null && saved.isNotEmpty) {
      _logs.addAll(saved.split('\n'));
    }
  }

  static void log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 23);
    final line = '[$timestamp] $message';
    _logs.add(line);
    
    // 限制日志行数
    if (_logs.length > _kMaxLines) {
      _logs.removeRange(0, _logs.length - _kMaxLines);
    }
    
    // 持久化
    _prefs?.setString(_kLogKey, _logs.join('\n'));
    
    // 同时打印到控制台
    debugPrint('[DEBUG_LOG] $line');
  }

  static void clear() {
    _logs.clear();
    _prefs?.remove(_kLogKey);
  }

  static List<String> getLogs() => List.unmodifiable(_logs);
}

/// 浮动日志按钮 + 日志查看器
class ReaderDebugLogButton extends StatefulWidget {
  const ReaderDebugLogButton({
    super.key,
    required this.textColor,
  });

  final Color textColor;

  @override
  State<ReaderDebugLogButton> createState() => _ReaderDebugLogButtonState();
}

class _ReaderDebugLogButtonState extends State<ReaderDebugLogButton> {
  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 120,
      child: FloatingActionButton(
        mini: true,
        backgroundColor: Colors.orange.withValues(alpha: 0.9),
        onPressed: _showLogViewer,
        child: const Icon(Icons.bug_report, size: 18),
      ),
    );
  }

  void _showLogViewer() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bug_report, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      '阅读进度调试日志',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        setState(() => ReaderDebugLog.clear());
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.delete_outline, size: 16, color: Colors.orange),
                      label: const Text('清空', style: TextStyle(color: Colors.orange)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _buildLogList(scrollController),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogList(ScrollController scrollController) {
    final logs = ReaderDebugLog.getLogs();
    
    if (logs.isEmpty) {
      return const Center(
        child: Text(
          '暂无日志\n\n翻页或切换章节会产生日志',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54, fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        Color lineColor = Colors.white70;
        
        if (log.contains('ERROR') || log.contains('null')) {
          lineColor = Colors.redAccent;
        } else if (log.contains('SAVE') || log.contains('charOffset=')) {
          lineColor = Colors.greenAccent;
        } else if (log.contains('RESTORE') || log.contains('located')) {
          lineColor = Colors.cyanAccent;
        } else if (log.contains('SKIP')) {
          lineColor = Colors.yellowAccent;
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            log,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: lineColor,
              height: 1.4,
            ),
          ),
        );
      },
    );
  }
}
