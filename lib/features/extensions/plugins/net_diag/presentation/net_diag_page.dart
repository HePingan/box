// 网络诊断插件页面：手机上直连目标做四项检测。
//
// 形状与 monitor / remote_storage 插件一致：runtime 服务可注入（widget 测试
// 不碰真网络）；失败**写出原因**，不许表现成「一直在加载」；每项独立超时并
// 把耗时显示出来，用户不用猜「还要等多久」。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_back_button.dart';

import '../application/net_diag_service.dart';
import '../domain/net_diag_models.dart';

/// 页面用的服务实例（测试可替换）。
NetDiagService _runtimeService = NetDiagService();

/// 测试接缝：与 `debugSetServiceMonitorRuntime` 同形状；不传参恢复默认。
void debugSetNetDiagRuntime({NetDiagService? service}) {
  _runtimeService = service ?? NetDiagService();
}

/// 当前生效的服务（也供测试读，确认页面用的是注入的那个）。
NetDiagService get debugNetDiagService => _runtimeService;

class NetDiagPage extends StatefulWidget {
  const NetDiagPage({super.key});

  @override
  State<NetDiagPage> createState() => _NetDiagPageState();
}

class _NetDiagPageState extends State<NetDiagPage> {
  final _input = TextEditingController();
  List<NetDiagCheckResult> _results = [];
  List<String> _recent = const [];
  NetDiagReport? _report;
  NetDiagTarget? _lastTarget;
  String? _inputError;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final list = await _runtimeService.loadRecent();
    if (!mounted) return;
    setState(() => _recent = list);
  }

  Future<void> _run() async {
    if (_running) return;
    final target = parseNetDiagTarget(_input.text);
    if (target == null) {
      setState(() {
        _inputError = _input.text.trim().isEmpty
            ? '先填一个主机名，例如 box.hpa888.top'
            : '这个地址认不出来：写成 example.com 或 https://example.com:8443 都行';
      });
      return;
    }

    setState(() {
      _inputError = null;
      _running = true;
      _results = [];
      _report = null;
      _lastTarget = target;
    });

    await _runtimeService.rememberTarget(target.raw);
    final report = await _runtimeService.diagnose(
      target,
      onResult: (r) {
        if (!mounted) return;
        setState(() => _results = [..._results, r]);
      },
    );

    if (!mounted) return;
    setState(() {
      _report = report;
      _running = false;
    });
    await _loadRecent();
  }

  Future<void> _copyReport() async {
    final report = _report;
    if (report == null) return;
    await Clipboard.setData(ClipboardData(text: report.toPlainText()));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('结论已复制')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  AppBackButton(
                    onPressed: () => Navigator.maybePop(context),
                    label: '返回',
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '网络诊断',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _introCard(),
                  const SizedBox(height: 14),
                  _inputRow(),
                  if (_inputError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _inputError!,
                      style: const TextStyle(color: AppTokens.rose),
                    ),
                  ],
                  if (_recent.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _recentRow(),
                  ],
                  const SizedBox(height: 16),
                  if (_lastTarget != null &&
                      (!_lastTarget!.explicitScheme || !_lastTarget!.explicitPort))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        '你没写明协议/端口，按 '
                        '${_lastTarget!.scheme}://${_lastTarget!.host}:${_lastTarget!.port} 检测',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  if (_running && _results.isEmpty) _runningHint(),
                  for (final r in _results) _resultCard(r),
                  if (_report != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _copyReport,
                        icon: const Icon(Icons.copy_all_outlined, size: 18),
                        label: const Text('复制结论文本'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _introCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('由手机直连目标检测', style: TextStyle(fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          Text(
            '域名解析 / TCP 连通 / TLS 证书剩余天数 / HTTP 响应，四项各自独立、'
            '每项最多等 8 秒。',
            style: TextStyle(fontSize: 12, height: 1.5),
          ),
          SizedBox(height: 4),
          Text(
            '两点如实说明：① 结论不经过 Box 服务器，是这台手机当场测的，'
            '你在不同网络下结果可能不同；② 不支持 ICMP ping（客户端发不了），'
            '连通性用 TCP 连接测试代替。',
            style: TextStyle(fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _inputRow() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _input,
            autofocus: false,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _run(),
            decoration: const InputDecoration(
              hintText: 'box.hpa888.top 或 https://host:8443',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _running ? null : _run,
          child: Text(_running ? '检测中' : '检测'),
        ),
      ],
    );
  }

  Widget _recentRow() {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final item in _recent)
          ActionChip(
            label: Text(item, style: const TextStyle(fontSize: 12)),
            onPressed: _running
                ? null
                : () {
                    _input.text = item;
                    setState(() => _inputError = null);
                  },
          ),
      ],
    );
  }

  Widget _runningHint() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text('正在检测…（每项最多 8 秒）'),
        ],
      ),
    );
  }

  Widget _resultCard(NetDiagCheckResult r) {
    final color = !r.ok
        ? AppTokens.rose
        : (r.warning != null ? AppTokens.amber : AppTokens.emerald);
    final icon = !r.ok
        ? Icons.error_outline
        : (r.warning != null ? Icons.warning_amber_rounded : Icons.check_circle_outline);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${r.kind.label}：${r.summary}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${r.elapsedMs}ms',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          if (r.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '原因：${r.error}',
                style: const TextStyle(fontSize: 12, color: AppTokens.rose),
              ),
            ),
          if (r.warning != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '提醒：${r.warning}',
                style: const TextStyle(fontSize: 12, color: AppTokens.amber),
              ),
            ),
          for (final d in r.details)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: SelectableText(
                '· $d',
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
