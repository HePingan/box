// 网页源码获取：把服务端返回的**原始文本**拉下来看。
//
// 定位说清楚（也写在界面上）：这是源码，不是浏览器渲染后的页面 —— 动态站点
// 拿到的往往是空壳。要"看页面长什么样"请用内置浏览器。
//
// 取数接缝：单测注入假 client（仓库纪律：单测不联网），"真机会不会好"由带
// `live` 标签的用例真连一次证明。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_back_button.dart';
import 'package:box/tool_web_page.dart';

/// 源码展示的字节上限。超过就截断并**明说截断**，不做假完整。
const int kSourceFetchMaxBytes = 200 * 1024;

/// 主机名（ASCII）判据 —— 与网络诊断插件保持同一套，别两处各写一份。
final RegExp _asciiHost = RegExp(r'^[A-Za-z0-9]([A-Za-z0-9\-._]*[A-Za-z0-9])?$');

/// 单次拉取结果。
class SourceFetchResult {
  const SourceFetchResult({
    required this.bytes,
    this.statusCode,
    this.contentType,
    this.finalUrl,
    this.truncated = false,
    this.error,
  });

  final List<int> bytes;
  final int? statusCode;
  final String? contentType;
  final String? finalUrl;
  final bool truncated;
  final String? error;

  bool get ok => error == null && statusCode != null;
  int get byteCount => bytes.length;

  String get text => const Utf8Decoder(allowMalformed: true).convert(bytes);
}

/// 取数接缝（真机走 [IoSourceFetch]；单测注入假实现）。
abstract class SourceFetch {
  Future<SourceFetchResult> fetch(String url, {Duration timeout});
}

/// 生产实现：http 包，不跟 JS、只看服务端返回的第一手文本。
class IoSourceFetch implements SourceFetch {
  IoSourceFetch({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<SourceFetchResult> fetch(
    String url, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      final res = await _client.get(Uri.parse(url)).timeout(timeout);
      final full = res.bodyBytes;
      final truncated = full.length > kSourceFetchMaxBytes;
      return SourceFetchResult(
        bytes: truncated ? full.sublist(0, kSourceFetchMaxBytes) : full,
        statusCode: res.statusCode,
        contentType: res.headers['content-type'],
        finalUrl: res.request?.url.toString(),
        truncated: truncated,
      );
    } on TimeoutException {
      return SourceFetchResult(
        bytes: const [],
        error: '等了 ${timeout.inSeconds} 秒没有响应（超时）',
      );
    } on FormatException {
      return const SourceFetchResult(bytes: [], error: '地址格式不对');
    } catch (e) {
      return SourceFetchResult(bytes: const [], error: _describe(e));
    }
  }

  String _describe(Object e) {
    final s = e.toString();
    if (s.contains('SocketException')) {
      if (s.contains('Failed host lookup')) return '域名解析不了（DNS 查不到这台主机）';
      if (s.contains('Connection refused')) return '对方拒绝了连接';
      if (s.contains('timed out')) return '连接超时';
      if (s.contains('Network is unreachable')) return '本机没有可用网络';
      return '网络层错误：$s';
    }
    if (s.contains('HandshakeException')) return 'TLS 握手失败（证书或协议问题）';
    if (s.contains('HttpException')) return 'HTTP 层错误：$s';
    return s;
  }
}

/// 网页源码获取页。
class SourceFetchPage extends StatefulWidget {
  const SourceFetchPage({super.key, this.fetch});

  /// 可注入取数（测试用）；生产省略即走默认实现。
  final SourceFetch? fetch;

  @override
  State<SourceFetchPage> createState() => _SourceFetchPageState();
}

class _SourceFetchPageState extends State<SourceFetchPage> {
  final TextEditingController _url = TextEditingController(
    text: 'https://box.hpa888.top/updates/box/android/release/version.json',
  );

  late final SourceFetch _fetch = widget.fetch ?? IoSourceFetch();

  SourceFetchResult? _result;
  String? _inputError;
  bool _running = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  String? _normalize(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final withScheme = t.contains('://') ? t : 'https://$t';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    // 主机名必须是 ASCII（和网络诊断同一套判据）：中文域名输进来多半是打错了，
    // 与其让 DNS 去猜，不如当场说"认不出"。
    if (!_asciiHost.hasMatch(uri.host)) return null;
    return uri.toString();
  }

  Future<void> _run() async {
    final url = _normalize(_url.text);
    if (url == null) {
      setState(() {
        _inputError = '认不出这个地址：要 http/https 开头的网址（不写协议按 https 试）';
        _result = null;
      });
      return;
    }
    setState(() {
      _inputError = null;
      _running = true;
      _result = null;
    });
    final r = await _fetch.fetch(url);
    if (!mounted) return;
    setState(() {
      _running = false;
      _result = r;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.background,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('网页源码获取'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '看服务端返回的原始文本（源码）。动态页面的内容由 JS 生成，'
            '这里看到的多是空壳 —— 要看渲染后的页面请用「用内置浏览器打开」。',
            style: TextStyle(fontSize: 12, color: AppTokens.textSecondary),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            decoration: InputDecoration(
              labelText: '网址',
              hintText: 'https://example.com',
              errorText: _inputError,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _run(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                onPressed: _running ? null : _run,
                child: Text(_running ? '拉取中…' : '拉取源码'),
              ),
              const SizedBox(width: 12),
              if (_result?.finalUrl != null && _result!.error == null)
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ToolWebPage(
                        title: '源码所示页面',
                        url: _result!.finalUrl!,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.public_rounded, size: 18),
                  label: const Text('用内置浏览器打开'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_running) _pending(),
          if (_result != null) ..._resultView(_result!),
        ],
      ),
    );
  }

  Widget _pending() {
    return Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text('正在拉取 ${_url.text.trim()} …')),
      ],
    );
  }

  List<Widget> _resultView(SourceFetchResult r) {
    if (r.error != null) {
      return [
        _line('没拉到内容', bad: true),
        const SizedBox(height: 6),
        SelectableText('原因：${r.error}', style: const TextStyle(fontSize: 13)),
      ];
    }

    final statusOk = r.statusCode != null && r.statusCode! >= 200 && r.statusCode! < 400;
    return [
      _line('HTTP ${r.statusCode}', bad: !statusOk),
      _line('大小 ${_sizeLabel(r.byteCount)}${r.truncated ? '（已截断，只显示前 ${kSourceFetchMaxBytes ~/ 1024} KB）' : ''}'),
      if (r.contentType != null) _line('类型 ${r.contentType}'),
      if (r.finalUrl != null && r.finalUrl != _url.text.trim())
        _line('最终地址 ${r.finalUrl}'),
      const SizedBox(height: 12),
      Row(
        children: [
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: r.text));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('源码已复制')),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('复制源码'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTokens.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SelectableText(
          r.text.isEmpty ? '（内容为空）' : r.text,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
        ),
      ),
    ];
  }

  Widget _line(String text, {bool bad = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: bad ? AppTokens.rose : AppTokens.textPrimary,
          fontWeight: bad ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }

  String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes 字节';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }
}
