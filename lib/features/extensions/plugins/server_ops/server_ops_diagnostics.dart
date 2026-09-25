// 服务器运维插件：连接体检（文件通道 / 终端 / 主机快照）。
//
// 为什么要有：以前只有"用的时候报错"，连不上到底是哪一段断的（WebDAV？终端？
// 快照端点？）谁也说不清 —— 三个是**互相独立**的端点，失败原因完全不同：
//   * 文件通道走 WebDAV（Basic 认证 + rclone）；
//   * 终端是 ttyd，认证由 WebView 层应答，普通 GET 能测"地址 + 口令 + nginx location"；
//   * 快照是边缘机上的静态文件 + 查询令牌。
// 所以给用户一个能自己跑、能报出状态码的入口，别让"连不上"变成猜。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:box/features/extensions/plugins/server_ops/host_models.dart';
import 'package:box/features/extensions/plugins/server_ops/host_service.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_files_service.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';

/// 单项体检结果。detail 一律是给人看的中文。
class OpsProbeResult {
  const OpsProbeResult({
    required this.label,
    required this.ok,
    required this.detail,
  });

  final String label;
  final bool ok;
  final String detail;
}

/// 终端探针：可注入（单测不许联网）。
typedef OpsTerminalProbe = Future<OpsProbeResult> Function(
  String url,
  String user,
  String password,
);

/// 三项体检，顺序固定（文件 → 终端 → 快照），失败不中断后面两项。
Future<List<OpsProbeResult>> runOpsProbes({
  required ServerOpsFilesService files,
  required HostService hosts,
  required String terminalUrl,
  required String user,
  required String password,
  OpsTerminalProbe? terminalProbe,
}) async {
  final probe = terminalProbe ?? probeOpsTerminal;
  return <OpsProbeResult>[
    await probeOpsFiles(files),
    await probe(terminalUrl, user, password),
    await probeOpsSnapshot(hosts),
  ];
}

/// 按**一台服务器**跑三项体检（B1：诊断跟着当前选中的机器走）。
///
/// 地址 / 用户名 / 终端地址全部取自这台服务器，口令由调用方给（它只在会话内存与
/// 本机加密存储里，不在模型里）。[files] 也必须是按同一台服务器的设置建出来的，
/// 否则会出现"测的是 A 机、连的是 B 机"的假结论。
Future<List<OpsProbeResult>> runOpsProbesForServer({
  required ServerOpsServer server,
  required String password,
  required ServerOpsFilesService files,
  required HostService hosts,
  OpsTerminalProbe? terminalProbe,
}) =>
    runOpsProbes(
      files: files,
      hosts: hosts,
      terminalUrl: server.effectiveTerminalUrl,
      user: server.effectiveUser,
      password: password,
      terminalProbe: terminalProbe,
    );

/// 文件通道：列一次根目录。这是"口令对不对、服务起没起"最小的一次真实请求。
Future<OpsProbeResult> probeOpsFiles(ServerOpsFilesService files) async {
  try {
    final entries = await files.list('');
    return OpsProbeResult(
      label: '文件通道（WebDAV）',
      ok: true,
      detail: '根目录 ${entries.length} 项',
    );
  } catch (e) {
    return OpsProbeResult(
      label: '文件通道（WebDAV）',
      ok: false,
      detail: serverOpsErrorMessage(e),
    );
  }
}

/// 主机快照：拉一次 hosts.json（带令牌）。
Future<OpsProbeResult> probeOpsSnapshot(HostService hosts) async {
  try {
    final HostSnapshot snap = await hosts.fetch();
    final at = snap.generatedAt?.toLocal();
    return OpsProbeResult(
      label: '主机状态快照',
      ok: true,
      detail: at == null
          ? '${snap.hosts.length} 台机器'
          : '${snap.hosts.length} 台机器，采样于 ${at.hour.toString().padLeft(2, '0')}:'
              '${at.minute.toString().padLeft(2, '0')}',
    );
  } catch (e) {
    return OpsProbeResult(
      label: '主机状态快照',
      ok: false,
      detail: e is HostFetchException ? e.message : '取快照失败：$e',
    );
  }
}

/// 默认终端探针：对终端地址发一次带 Basic 认证的 GET。
///
/// ttyd 前端就是一张 HTML 页面，所以 200 足以证明「地址对 + 口令对 + nginx location
/// 匹配上了」。分状态码给结论，而不是笼统的"连接失败"：
///   401 → 口令不对；404 → 端点没匹配（HTTP/2 下 nginx 会假装 404 的老坑）；
///   其余非 200 → 原样报状态码；超时/异常 → 不可达（附原因）。
Future<OpsProbeResult> probeOpsTerminal(
  String url,
  String user,
  String password,
) async {
  const label = '终端（ttyd）';
  final uri = Uri.tryParse(url);
  if (uri == null || url.trim().isEmpty) {
    return const OpsProbeResult(label: label, ok: false, detail: '终端地址没填或不是合法 URL');
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(uri).timeout(const Duration(seconds: 10));
    // 用 UTF-8 字节拼 Basic 头，避免非 ASCII 口令在 latin1 下被悄悄改写。
    final token = base64.encode(utf8.encode('${user.isEmpty ? '' : user}:$password'));
    req.headers.set(HttpHeaders.authorizationHeader, 'Basic $token');
    req.headers.set(HttpHeaders.acceptHeader, 'text/html');
    final resp = await req.close().timeout(const Duration(seconds: 10));
    await resp.drain<void>();
    switch (resp.statusCode) {
      case 200:
        return const OpsProbeResult(label: label, ok: true, detail: '页面可达（200）');
      case 401:
        return const OpsProbeResult(label: label, ok: false, detail: '认证失败（401）：口令不对');
      case 404:
        return const OpsProbeResult(
          label: label,
          ok: false,
          detail: '404：终端端点没匹配上（地址写错，或走了 HTTP/2）',
        );
      default:
        return OpsProbeResult(
          label: label,
          ok: false,
          detail: 'HTTP ${resp.statusCode}',
        );
    }
  } catch (e) {
    return OpsProbeResult(label: label, ok: false, detail: '连不上：$e');
  } finally {
    client.close(force: true);
  }
}

