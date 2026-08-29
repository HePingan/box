import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'github_accel_link.dart';
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
        headers: const {'Accept': 'application/vnd.github+json'},
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
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final m in GithubAccelLink.mirrors)
          ChoiceChip(
            label: Text(m.label, style: const TextStyle(fontSize: 11.5)),
            selected: _mirror == m.url,
            visualDensity: VisualDensity.compact,
            onSelected: _downloading
                ? null
                : (_) {
                    setState(() => _mirror = m.url);
                    if (_result != null) _resolve();
                  },
          ),
      ],
    );
  }

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
            Text(r.message, style: theme.textTheme.bodySmall),
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
