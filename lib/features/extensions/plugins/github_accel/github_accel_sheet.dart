import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'github_accel_link.dart';
import 'github_accel_probe.dart';
import 'github_accel_service.dart';

/// GitHub 加速下载面板。
///
/// 流程：粘贴链接 → 自动识别形态 → （签名链才联网查仓库）→ 产出加速地址
/// → 直接下载到应用目录 → 可打开/分享。
///
/// 下载走 dio 是为了拿进度回调，参考 lib/update/app_installer_io.dart 的做法。
class GithubAccelSheet extends StatefulWidget {
  const GithubAccelSheet({super.key, this.initialUrl = ''});

  final String initialUrl;

  static Future<void> show(BuildContext context, {String initialUrl = ''}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GithubAccelSheet(initialUrl: initialUrl),
    );
  }

  @override
  State<GithubAccelSheet> createState() => _GithubAccelSheetState();
}

class _GithubAccelSheetState extends State<GithubAccelSheet> {
  final _input = TextEditingController();
  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 10),
      followRedirects: true,
    ),
  );

  String _mirror = GithubAccelLink.defaultMirror;

  /// 测速状态与结果（镜像 url -> 排名）。
  bool _probing = false;
  String _probeNote = '';
  Map<String, MirrorRanking> _rankings = const {};

  /// 每次探测的字节数。调大 → 测量更接近真实大文件吞吐但更耗流量；
  /// 调小 → 省流量但容易被握手开销淹没。64KB 是实测能稳定分辨快慢的下限。
  static const int _probeBytes = 65536;

  /// 还没转换出稳定链接时的测速目标。
  ///
  /// 选**固定 tag** 的 release 资产（不是 latest）：latest 会随上游发版变化，
  /// 文件名一变探测就 404。release 资产实测支持 Range（严格返回 65536 字节），
  /// 而归档（/archive/）和 raw 文件会无视 Range 直接吐几 MB，不适合做探测。
  /// 只用来比较线路快慢，不会下载给用户。
  static const String _probeFallbackTarget =
      'https://github.com/rikkahub/rikkahub/releases/download/2.4.15/'
      'RikkaHub-2.4.15-arm64-v8a.apk';
  GithubAccelResolution? _result;
  bool _resolving = false;

  CancelToken? _cancel;
  double _progress = 0;
  int _received = 0;
  int _total = 0;
  String _savedPath = '';
  String _error = '';

  bool get _downloading => _cancel != null;

  @override
  void initState() {
    super.initState();
    _input.text = widget.initialUrl;
    if (widget.initialUrl.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
    }
  }

  @override
  void dispose() {
    _cancel?.cancel('sheet disposed');
    _input.dispose();
    _dio.close(force: true);
    super.dispose();
  }

  Future<String> _fetch(String url) async {
    final resp = await _dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        // GitHub API 对没有 User-Agent 的请求直接拒；镜像转发时也需要。
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'box-app',
        },
        // 不让 Dio 因 4xx 抛异常 —— 限流响应体里有 "API rate limit" 信息，
        // 交给 service 判断（没有 full_name 就换通道），比抛英文堆栈有用。
        validateStatus: (_) => true,
      ),
    );
    return resp.data ?? '';
  }

  Future<void> _resolve() async {
    final raw = _input.text.trim();
    if (raw.isEmpty) return;

    setState(() {
      _resolving = true;
      _error = '';
      _savedPath = '';
    });

    final svc = GithubAccelService(fetch: _fetch, mirror: _mirror);
    final r = await svc.resolve(raw);

    if (!mounted) return;
    setState(() {
      _result = r;
      _resolving = false;
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _snack('剪贴板是空的');
      return;
    }
    _input.text = text;
    await _resolve();
  }

  Future<void> _copyAccel() async {
    final url = _result?.accelUrl;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    _snack('加速链接已复制');
  }

  Future<void> _download() async {
    final url = _result?.accelUrl;
    if (url == null) return;

    final name = _fileNameFor(url);
    final dir = await getApplicationDocumentsDirectory();
    final saveDir = Directory(p.join(dir.path, 'github_downloads'));
    if (!await saveDir.exists()) {
      await saveDir.create(recursive: true);
    }
    final savePath = p.join(saveDir.path, name);

    final token = CancelToken();
    setState(() {
      _cancel = token;
      _progress = 0;
      _received = 0;
      _total = 0;
      _error = '';
      _savedPath = '';
    });

    try {
      await _dio.download(
        url,
        savePath,
        cancelToken: token,
        onReceiveProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total;
            // total 为 -1 表示服务端没给 Content-Length，此时只能显示已下字节
            _progress = total > 0 ? received / total : 0;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _cancel = null;
        _savedPath = savePath;
      });
      _snack('下载完成');
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _cancel = null);
      if (CancelToken.isCancel(e)) {
        _snack('已取消下载');
        // 取消后残留的半截文件要删掉，否则下次「打开」会拿到坏文件
        await _deleteQuietly(savePath);
        return;
      }
      setState(() => _error = _friendlyError(e));
      await _deleteQuietly(savePath);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cancel = null;
        _error = '下载失败：$e';
      });
      await _deleteQuietly(savePath);
    }
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('[GithubAccel] 清理半截文件失败: $e');
    }
  }

  String _friendlyError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return '连接超时。可以在上方换一个镜像再试。';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == 404) {
          return 'HTTP 404。文件名或版本可能不对，也可能这个镜像不支持该路径。';
        }
        return 'HTTP $code。换个镜像通常能解决。';
      case DioExceptionType.connectionError:
        return '网络不可达，请检查网络或更换镜像。';
      default:
        return '下载失败：${e.message ?? e.type.name}';
    }
  }

  String _fileNameFor(String url) {
    final fromLink = _result?.link.fileName ?? '';
    if (fromLink.isNotEmpty) return fromLink;
    final segs = Uri.tryParse(url)?.pathSegments ?? const [];
    for (final s in segs.reversed) {
      if (s.contains('.')) return s;
    }
    return 'github_download_${DateTime.now().millisecondsSinceEpoch}';
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  static String _fmtBytes(int b) {
    if (b <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var v = b.toDouble();
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _result;

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.rocket_launch_rounded, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'GitHub 加速下载',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '粘贴 GitHub 下载地址，自动转换成镜像加速链接并直接下载。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
              const SizedBox(height: 14),

              TextField(
                controller: _input,
                maxLines: 3,
                minLines: 2,
                style: const TextStyle(fontSize: 12.5),
                decoration: InputDecoration(
                  hintText: 'https://github.com/<用户>/<仓库>/releases/...',
                  hintStyle: const TextStyle(fontSize: 12),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.content_paste_rounded, size: 18),
                    tooltip: '粘贴并转换',
                    onPressed: _downloading ? null : _paste,
                  ),
                ),
                onSubmitted: (_) => _resolve(),
              ),
              const SizedBox(height: 10),

              _mirrorPicker(theme),
              const SizedBox(height: 10),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (_resolving || _downloading) ? null : _resolve,
                  icon: _resolving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_fix_high_rounded, size: 18),
                  label: Text(_resolving ? '识别中…' : '转换为加速链接'),
                ),
              ),

              if (r != null) ...[
                const SizedBox(height: 16),
                _resultCard(theme, r),
              ],

              if (_downloading || _savedPath.isNotEmpty || _error.isNotEmpty)
                ...[const SizedBox(height: 14), _statusCard(theme)],

              const SizedBox(height: 18),
              _helpCard(theme),
            ],
          ),
        );
      },
    );
  }

  Widget _mirrorPicker(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in GithubAccelLink.mirrors)
              ChoiceChip(
                label: Text(
                  _mirrorChipLabel(m),
                  style: const TextStyle(fontSize: 11.5),
                ),
                selected: _mirror == m.url,
                visualDensity: VisualDensity.compact,
                // 测速结果里不可用的镜像置灰，避免用户白选。
                onSelected: (_downloading || _probing || !_mirrorUsable(m.url))
                    ? null
                    : (_) {
                        setState(() => _mirror = m.url);
                        if (_result != null) _resolve();
                      },
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: (_probing || _downloading) ? null : _probeMirrors,
              icon: _probing
                  ? const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.speed_rounded, size: 15),
              label: Text(_probing ? '测速中…' : '测速选最快'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 8),
            if (_probeNote.isNotEmpty)
              Expanded(
                child: Text(
                  _probeNote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  String _mirrorChipLabel(GithubMirror m) {
    final r = _rankings[m.url];
    if (r == null) return m.label;
    if (!r.usable) return '${m.label} ✗';
    return '${m.label} ${r.medianMs}ms';
  }

  bool _mirrorUsable(String url) {
    final r = _rankings[url];
    return r == null || r.usable;
  }

  /// 对所有内置镜像并发测速，自动切到最快的那个。
  ///
  /// 探测目标优先用当前已转换出的稳定链接（最贴近真实下载路径）；
  /// 还没转换时退回一个体积够小的公共文件，只为比较线路快慢。
  Future<void> _probeMirrors() async {
    final stable = _result?.link.stableUrl ?? _probeFallbackTarget;

    setState(() {
      _probing = true;
      _probeNote = '';
    });

    final prober = MirrorProbe(probe: _probeOnce);
    final ranked = await prober.rank(stable);

    if (!mounted) return;

    final best = ranked.where((r) => r.usable).toList();
    setState(() {
      _rankings = {for (final r in ranked) r.mirror: r};
      _probing = false;
      if (best.isEmpty) {
        _probeNote = '所有线路都没测通，可能是当前网络不通';
      } else {
        _mirror = best.first.mirror;
        _probeNote = '已选 ${best.first.label}（${best.first.summary}）';
      }
    });

    // 换了镜像就重算加速地址，让下载按钮用上新线路。
    if (best.isNotEmpty && _result != null) await _resolve();
  }

  /// 真实探测一次：只取前 64KB，量总耗时。
  ///
  /// 用流式读取并在收够字节后主动中断，而不是信任 Range：实测部分镜像
  /// 对 raw 文件无视 Range（gh-proxy 返回 290KB 而非 64KB），归档更是
  /// 直接吐 10MB。不设上限的话「测速」本身就变成了大流量下载。
  Future<MirrorSample> _probeOnce(String mirror, String url) async {
    final target = '${_trimSlash(mirror)}/$url';
    final sw = Stopwatch()..start();
    try {
      final resp = await _dio.get<ResponseBody>(
        target,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Range': 'bytes=0-${_probeBytes - 1}',
            'User-Agent': 'box-app',
          },
          followRedirects: true,
          receiveTimeout: const Duration(seconds: 12),
          sendTimeout: const Duration(seconds: 12),
          validateStatus: (c) => c != null && c < 400,
        ),
      );

      var got = 0;
      final sub = resp.data!.stream;
      await for (final chunk in sub) {
        got += chunk.length;
        // 收够就走，多余的字节没有测量价值，只是浪费用户流量。
        if (got >= _probeBytes) break;
      }
      sw.stop();

      if (got <= 0) {
        return MirrorSample(mirror: mirror, ok: false, error: '没返回数据');
      }
      return MirrorSample(mirror: mirror, ok: true, elapsed: sw.elapsed);
    } on DioException catch (e) {
      sw.stop();
      return MirrorSample(
        mirror: mirror,
        ok: false,
        error: _shortDioError(e),
      );
    } catch (e) {
      sw.stop();
      return MirrorSample(mirror: mirror, ok: false, error: '$e');
    }
  }

  static String _shortDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return '超时';
      case DioExceptionType.badCertificate:
        return '证书无效';
      case DioExceptionType.badResponse:
        return 'HTTP ${e.response?.statusCode ?? '?'}';
      case DioExceptionType.connectionError:
        return '连不上';
      default:
        return '失败';
    }
  }

  static String _trimSlash(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  Widget _resultCard(ThemeData theme, GithubAccelResolution r) {
    final ok = r.ok && r.accelUrl != null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (ok ? Colors.green : Colors.orange).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (ok ? Colors.green : Colors.orange).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                size: 16,
                color: ok ? Colors.green.shade700 : Colors.orange.shade800,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  ok ? '转换成功' : '无法转换',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (r.link.fileName.isNotEmpty)
                Flexible(
                  child: Text(
                    r.link.fileName,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                ),
            ],
          ),
          if (r.message.isNotEmpty) ...[
            const SizedBox(height: 6),
            // 失败提示里带着可手填的链接模板，做成可选中方便复制。
            SelectableText(
              r.message,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
            ),
          ],
          if (!ok && r.link.kind == GithubLinkKind.signedAsset) ...[
            const SizedBox(height: 8),
            // 镜像限流是间歇性的，重试很可能直接成功，给个一键入口。
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _resolving ? null : _resolve,
                icon: const Icon(Icons.refresh_rounded, size: 15),
                label: const Text('重试转换'),
              ),
            ),
          ],
          if (ok) ...[
            const SizedBox(height: 10),
            SelectableText(
              r.accelUrl!,
              style: const TextStyle(fontSize: 11, height: 1.35),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _downloading ? null : _download,
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('立即下载'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _copyAccel,
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  label: const Text('复制'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_downloading) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    _total > 0
                        ? '下载中 ${(_progress * 100).toStringAsFixed(1)}%'
                          '（${_fmtBytes(_received)} / ${_fmtBytes(_total)}）'
                        : '下载中 ${_fmtBytes(_received)}（服务端未返回总大小）',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: () => _cancel?.cancel('user'),
                  child: const Text('取消'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: _total > 0 ? _progress : null,
              minHeight: 4,
            ),
          ],
          if (_error.isNotEmpty)
            Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 16,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_error, style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          if (_savedPath.isNotEmpty) ...[
            Text('已保存：', style: theme.textTheme.bodySmall),
            const SizedBox(height: 2),
            SelectableText(
              _savedPath,
              style: const TextStyle(fontSize: 10.5, height: 1.3),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () => OpenFilex.open(_savedPath),
                  icon: const Icon(Icons.open_in_new_rounded, size: 15),
                  label: const Text('打开'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(files: [XFile(_savedPath)]),
                  ),
                  icon: const Icon(Icons.ios_share_rounded, size: 15),
                  label: const Text('分享'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _helpCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '支持的链接形态',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          ...[
            'Release 附件：/releases/latest/download/… 或 /releases/download/<tag>/…',
            'raw 文件：raw.githubusercontent.com/…',
            '源码归档：/archive/… 与 codeload.github.com/…',
            '浏览器复制到的签名长链（release-assets…）会自动查仓库并重建为稳定地址',
          ].map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('· ', style: theme.textTheme.bodySmall),
                  Expanded(
                    child: Text(t, style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '提示：签名长链带 sig/se 参数，几十分钟就过期，本插件会改用 latest 稳定地址重建。',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
        ],
      ),
    );
  }
}
