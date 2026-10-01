// 答题助手「自检 & 最近日志」。
//
// 为什么要有这一页（2026-10-01 连续三轮真机事故）：
// 读屏卡住时，用户手机上看不到任何现场信息 —— 我只能靠"服务端零请求"这种侧面证据
// 加反复追问「点 AI 有没有反应」来猜。用户只有手机、读不到日志，所以现场信息必须
// **他自己看得到、能一键复制**。
//
// 这一页只做三件事：
//   1) 把读屏依赖的条件逐条列出来（无障碍服务 / 悬浮窗权限 / 悬浮窗可见 / 凭证模式 / 当前阶段）；
//   2) 提供**截图通道自测**：当场跑一次截图，显示耗时与字节数（卡住时这就是证据）；
//   3) 显示最近日志（内存全量 + 落本机的重要事件），并「复制结论」。
//
// 口径：**绝不显示任何令牌/口令**，只显示凭证"模式"；报告文本同样如此（有单测锁）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/app_tokens.dart';
import '../data/quiz_vision_credentials.dart';
import '../domain/quiz_diag.dart';
import 'quiz_plugin_entry.dart';

class QuizPluginSelfCheckPage extends StatefulWidget {
  const QuizPluginSelfCheckPage({super.key});

  /// 拼给用户复制的纯文本结论。
  ///
  /// 做成**纯静态函数**是为了能单测：报告里出现令牌=事故（用户会把它贴到聊天里）。
  static String buildReport({
    required Map<String, String> status,
    required String probe,
    required List<String> recent,
    required List<String> important,
  }) {
    final buffer = StringBuffer()
      ..writeln('【答题助手自检】')
      ..writeln('时间：${DateTime.now().toIso8601String().substring(0, 19)}');
    for (final entry in status.entries) {
      buffer.writeln('· ${entry.key}：${entry.value}');
    }
    buffer
      ..writeln('· 截图自测：$probe')
      ..writeln()
      ..writeln('【最近日志】');
    if (recent.isEmpty) {
      buffer.writeln('（无）');
    } else {
      for (final line in recent) {
        buffer.writeln(line);
      }
    }
    buffer
      ..writeln()
      ..writeln('【重要事件（落本机）】');
    if (important.isEmpty) {
      buffer.writeln('（无）');
    } else {
      for (final line in important) {
        buffer.writeln(line);
      }
    }
    return buffer.toString().trim();
  }

  @override
  State<QuizPluginSelfCheckPage> createState() =>
      _QuizPluginSelfCheckPageState();
}

class _QuizPluginSelfCheckPageState extends State<QuizPluginSelfCheckPage> {
  bool _loading = true;
  Map<String, String> _status = const {};
  List<String> _recent = const [];
  List<String> _important = const [];
  String _probe = '未测试（点上面的「截图自测」当场验一次）';
  bool _probing = false;
  bool _credentialChecking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final status = <String, String>{};

    try {
      status['无障碍服务'] = await QuizPluginEntry.isAccessibilityEnabled()
          ? '已启用'
          : '未启用 —— 读屏拿不到截图，请到「设置 → 无障碍」开启「答题助手」';
    } catch (_) {
      status['无障碍服务'] = '检测失败';
    }
    try {
      status['悬浮窗权限'] = await QuizPluginEntry.hasOverlayPermission()
          ? '已授权'
          : '未授权 —— 悬浮窗不会显示';
    } catch (_) {
      status['悬浮窗权限'] = '检测失败';
    }
    try {
      status['悬浮窗可见'] = await QuizPluginEntry.isOverlayVisible()
          ? '是'
          : '否';
    } catch (_) {
      status['悬浮窗可见'] = '检测失败';
    }
    // 凭证**不在打开页面时**去取：取用会真实消耗一次签发额度（同 IP 每天 5 次），
    // 反复打开自检页反而会把读屏自己顶成 429。改成显式点「检测凭证」。
    status['凭证模式'] = '未检测（点下面的「检测凭证」，会真实取用一次）';
    status['当前阶段'] = QuizPluginEntry.visionPhase;

    final recent = QuizDiag.recent(limit: 20);
    final important = await QuizDiag.important(limit: 20);
    if (!mounted) return;
    setState(() {
      _status = status;
      _recent = recent;
      _important = important;
      _loading = false;
    });
  }

  /// 显式检测凭证（会真实取用一次：已登录用会话、未登录签发匿名设备令牌）。
  Future<void> _probeCredential() async {
    setState(() => _credentialChecking = true);
    String mode;
    try {
      final config = await QuizPluginEntry.loadConfig();
      final endpoint = await quizVisionCredentialResolver.resolve(config);
      mode = endpoint.isUnavailable
          ? '不可用：${endpoint.errorMessage}'
          : '${endpoint.mode.name}${endpoint.viaProxy ? '（平台代理）' : '（直连）'}';
      QuizDiag.log(QuizDiagStage.result, '自检：凭证检测完成', fields: {
        'mode': endpoint.mode.name,
        'proxy': endpoint.viaProxy,
      });
    } catch (_) {
      mode = '解析失败';
    }
    if (!mounted) return;
    setState(() {
      _status = {..._status, '凭证模式': mode};
      _credentialChecking = false;
    });
  }

  Future<void> _probeCapture() async {
    setState(() => _probing = true);
    final watch = Stopwatch()..start();
    Uint8List? bytes;
    try {
      bytes = await QuizPluginEntry.captureRegionScreenshot();
    } catch (_) {
      bytes = null;
    }
    watch.stop();
    final ok = bytes != null && bytes.isNotEmpty;
    final text = ok
        ? '成功：${bytes.length} 字节，耗时 ${watch.elapsedMilliseconds}ms'
        : '失败：${watch.elapsedMilliseconds}ms 内没拿到截图'
              '（截图通道无响应，或无障碍服务被系统关掉了）';
    QuizDiag.log(
      QuizDiagStage.result,
      ok ? '自检：截图通道正常' : '自检：截图通道失败',
      fields: {'ms': watch.elapsedMilliseconds, 'bytes': bytes?.length ?? 0},
    );
    if (!mounted) return;
    setState(() {
      _probe = text;
      _probing = false;
    });
  }

  String get _report => QuizPluginSelfCheckPage.buildReport(
    status: _status,
    probe: _probe,
    recent: _recent,
    important: _important,
  );

  Future<void> _copyReport() async {
    await Clipboard.setData(ClipboardData(text: _report));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制，直接粘贴发给我即可')),
    );
  }

  Future<void> _clearLogs() async {
    await QuizDiag.clearAll();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已清空本页日志')));
  }

  Widget _card({required String title, required List<Widget> children}) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppTokens.spaceMd),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppTokens.spaceSm),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _logBox(List<String> lines, String emptyText) {
    if (lines.isEmpty) {
      return Text(emptyText, style: Theme.of(context).textTheme.bodySmall);
    }
    return SelectableText(
      lines.join('\n'),
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('答题助手自检'),
        actions: [
          IconButton(
            tooltip: '重新检测',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppTokens.spaceLg),
              children: [
                _card(
                  title: '读屏依赖的条件',
                  children: [
                    ..._status.entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppTokens.spaceXs,
                        ),
                        child: Text('· ${e.key}：${e.value}'),
                      ),
                    ),
                    const SizedBox(height: AppTokens.spaceSm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _credentialChecking
                            ? null
                            : _probeCredential,
                        icon: _credentialChecking
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.key_outlined, size: 18),
                        label: Text(_credentialChecking ? '正在检测…' : '检测凭证'),
                      ),
                    ),
                  ],
                ),
                _card(
                  title: '截图通道自测',
                  children: [
                    Text(_probe),
                    const SizedBox(height: AppTokens.spaceSm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: _probing ? null : _probeCapture,
                        icon: _probing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.screenshot_monitor, size: 18),
                        label: Text(_probing ? '正在截图…' : '截图自测'),
                      ),
                    ),
                  ],
                ),
                _card(
                  title: '最近日志（内存，含所有级别）',
                  children: [_logBox(_recent, '（还没有日志）')],
                ),
                _card(
                  title: '重要事件（落本机，重开 App 也还在）',
                  children: [_logBox(_important, '（没有重要事件）')],
                ),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _copyReport,
                        icon: const Icon(Icons.copy_all, size: 18),
                        label: const Text('复制结论'),
                      ),
                    ),
                    const SizedBox(width: AppTokens.spaceSm),
                    OutlinedButton(
                      onPressed: _clearLogs,
                      child: const Text('清空日志'),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.spaceSm),
                Text(
                  '把「复制结论」的内容发给我，就能直接定位卡在哪一步。'
                  '（本页不显示任何令牌/口令）',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}
