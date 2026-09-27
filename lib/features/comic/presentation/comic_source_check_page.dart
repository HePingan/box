// 漫画源自检页：一句话回答"这个源在这台手机上到底能不能用"。
//
// 设计取舍：
//   * 只跑三步（搜索 / 详情 / 章节取图），每步都给"通过或原因"，不打分不美化；
//   * 失败原因里带上页面标题 —— 502 这种错误光看"命中 0"是看不出来的；
//   * 拿到图就**当场显示一张**（图片链没有防盗链，能显示即证明可读）；
//   * 「复制结论」把整份报告变成纯文本 —— 手机上看不出毛病时，贴回来就是证据。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_back_button.dart';
import '../domain/comic_source.dart';
import '../domain/comic_source_diagnostics.dart';
import '../domain/sources/seed_comic_source.dart';
import 'comic_source_webview_target.dart';

class ComicSourceCheckPage extends StatefulWidget {
  const ComicSourceCheckPage({super.key, this.targetOverride});

  /// 单测注入假取数（真机省略即用 WebView）。
  final ComicSourceTarget? targetOverride;

  @override
  State<ComicSourceCheckPage> createState() => _ComicSourceCheckPageState();
}

class _ComicSourceCheckPageState extends State<ComicSourceCheckPage> {
  final TextEditingController _key = TextEditingController(text: '海贼');
  // 只在真机上才建 WebView（单测注入假取数时**不能**碰平台控件，否则测试会去实例化
  // 平台 WebView 而失败）。
  late final ComicSourceWebViewController? _webView =
      widget.targetOverride == null ? ComicSourceWebViewController() : null;

  late final ComicSource? _source = ComicSource.tryParse(kSeedComicSourceJson);

  ComicProbeReport? _report;
  List<ComicProbeStep> _live = const [];
  String? _runningStep;
  bool _running = false;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  ComicSourceTarget get _target => widget.targetOverride ?? _webView!.target;

  Future<void> _run() async {
    final source = _source;
    if (source == null) {
      setState(() => _live = const []);
      return;
    }
    setState(() {
      _running = true;
      _report = null;
      _live = const [];
      _runningStep = '搜索';
    });
    final report = await runComicSourceProbe(
      target: _target,
      source: source,
      key: _key.text.trim().isEmpty ? '海贼' : _key.text.trim(),
      onStep: (step) {
        if (!mounted) return;
        setState(() {
          _live = [..._live, step];
          _runningStep = null;
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      _report = report;
      _runningStep = null;
    });
  }

  String _reportText(ComicProbeReport r) {
    final sb = StringBuffer()
      ..writeln('【漫画源自检】${r.sourceName}')
      ..writeln('结果：${r.okCount}/${r.steps.length} 步通过'
          '${r.allOk ? '（全部通过）' : ''}，总耗时 ${(r.totalMs / 1000).toStringAsFixed(1)} 秒')
      ..writeln('关键字：${_key.text.trim()}');
    for (final s in r.steps) {
      sb.writeln('· [${s.ok ? '通过' : '失败'}] ${s.name}（${s.elapsedMs}ms）${s.note}');
      if (s.pageTitle != null && s.pageTitle!.isNotEmpty) {
        sb.writeln('    页面标题：${s.pageTitle}');
      }
      if (s.finalUrl != null && s.finalUrl!.isNotEmpty) {
        sb.writeln('    最终地址：${s.finalUrl}');
      }
      for (final sample in s.samples) {
        sb.writeln('    样例：$sample');
      }
    }
    if (r.firstImageUrl != null) sb.writeln('首图：${r.firstImageUrl}');
    return sb.toString();
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    return Scaffold(
      backgroundColor: AppTokens.background,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('漫画源自检'),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (source == null)
                const Text('书源配置解析失败（内置 JSON 不完整）——这是 App 自身的问题，不是站点的问题。')
              else ...[
                Text(
                  source.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                Text(
                  source.baseUrl,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTokens.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '这一步用这台手机上的真 WebView 跑三件事：搜索 → 打开一本书 → 打开第一章取图。'
                  '站点有人机验证（纯请求会被 403），所以只能在手机上问出真相。\n'
                  '结论只代表**这台手机 + 当前网络**；换网络或站点改版都会变。',
                  style: TextStyle(fontSize: 12, color: AppTokens.textSecondary),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _key,
                  decoration: const InputDecoration(
                    labelText: '搜索关键字',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _running ? null : _run(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton(
                      onPressed: _running ? null : _run,
                      child: Text(_running ? '自检中…' : '开始自检'),
                    ),
                    const SizedBox(width: 10),
                    if (_report != null)
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: _reportText(_report!)),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('自检报告已复制')),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('复制结论'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                for (final step in _live) _stepCard(step),
                if (_runningStep != null) _pendingCard(_runningStep!),
                if (_report != null && !_running) ..._summary(_report!),
              ],
            ],
          ),
          if (widget.targetOverride == null) _webView!.buildOffscreen(),
        ],
      ),
    );
  }

  List<Widget> _summary(ComicProbeReport r) {
    return [
      const Divider(height: 28),
      Text(
        r.allOk
            ? '结论：三步全通 ✅ 这个源在这台手机上可用'
            : '结论：${r.steps.length - r.okCount} 步没过 ❌ 上面每一步后面写了原因',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: r.allOk ? AppTokens.emerald : AppTokens.rose,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        '总耗时 ${(r.totalMs / 1000).toStringAsFixed(1)} 秒',
        style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary),
      ),
      if (r.firstImageUrl != null) ...[
        const SizedBox(height: 14),
        const Text(
          '取到的第一张图（能显示就说明图片链通、没有防盗链）：',
          style: TextStyle(fontSize: 12, color: AppTokens.textSecondary),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            r.firstImageUrl!,
            height: 240,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Text(
              '这张图没加载出来（地址拿到了但取不到）',
              style: TextStyle(fontSize: 12, color: AppTokens.rose),
            ),
          ),
        ),
      ],
      const SizedBox(height: 14),
      const Text(
        '已知差异（不藏着）：书源里的「繁转简」本 App 未实现，繁体章节会显示为繁体；'
        '书源 ruleBookInfo.tocUrl 第 3 段是它自身的笔误，本 App 用详情页的章节链接。',
        style: TextStyle(fontSize: 11, color: AppTokens.textTertiary),
      ),
    ];
  }

  Widget _stepCard(ComicProbeStep step) {
    final color = step.ok ? AppTokens.emerald : AppTokens.rose;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                step.ok ? Icons.check_circle_rounded : Icons.error_rounded,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(
                step.name,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: color,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Text(
                '${step.elapsedMs} ms',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTokens.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(step.note, style: const TextStyle(fontSize: 12)),
          if (step.pageTitle != null && step.pageTitle!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SelectableText(
                '页面标题：${step.pageTitle}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTokens.textSecondary,
                ),
              ),
            ),
          if (step.finalUrl != null && step.finalUrl!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SelectableText(
                '最终地址：${step.finalUrl}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTokens.textSecondary,
                ),
              ),
            ),
          for (final sample in step.samples)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SelectableText(
                '样例：$sample',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTokens.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pendingCard(String name) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text('$name：正在跑（真 WebView 里过挑战、等页面渲染）…'),
        ],
      ),
    );
  }
}
