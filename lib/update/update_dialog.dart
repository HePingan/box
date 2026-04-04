import 'package:flutter/material.dart';

import 'app_installer.dart';
import 'update_models.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateManifest manifest;
  final String currentVersionName;
  final int currentVersionCode;
  final bool force;

  const UpdateDialog({
    super.key,
    required this.manifest,
    required this.currentVersionName,
    required this.currentVersionCode,
    required this.force,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
// 优先显示后台填的 title，如果没有填 title，再退而求其次显示日期
  String _titleText() {
    final title = widget.manifest.title;
    if (title != null && title.isNotEmpty) {
      return title;
    }
    final s = widget.manifest.publishedAt;
    if (s == null || s.isEmpty) return '发现新版本';
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  Future<void> _doUpdate() async {
    setState(() {
      _downloading = true;
      _progress = 0;
    });

    try {
      await AppInstaller.downloadAndInstall(
        manifest: widget.manifest,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _progress = p);
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final manifest = widget.manifest;

    return PopScope(
      canPop: !widget.force,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Container(
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(top: 28, bottom: 18),
                  color: const Color(0xFF66B7E8),
                  child: const Center(
                    child: _InfoIcon(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Text(
                          _titleText(),
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF222222),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '最新版本为：${manifest.latestVersionName} (${manifest.latestVersionCode})',
                        style: const TextStyle(fontSize: 16, color: Color(0xFF333333)),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '已安装版本：${widget.currentVersionName} (${widget.currentVersionCode})',
                        style: const TextStyle(fontSize: 16, color: Color(0xFF333333)),
                      ),
                      if (manifest.notice != null && manifest.notice!.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          manifest.notice!,
                          style: const TextStyle(fontSize: 14, color: Color(0xFF666666)),
                        ),
                      ],
                      if (manifest.changelog.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        const Text(
                          '更新内容：',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF333333),
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...manifest.changelog.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '• $item',
                              style: const TextStyle(fontSize: 13, color: Color(0xFF666666)),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: _downloading ? null : _doUpdate,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF6FB7E8), width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            _downloading
                                ? '下载中 ${(100 * _progress).clamp(0, 100).toStringAsFixed(0)}%'
                                : '更新',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Color(0xFF5FADE0),
                            ),
                          ),
                        ),
                      ),
                      if (_downloading) ...[
                        const SizedBox(height: 12),
                        LinearProgressIndicator(value: _progress),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoIcon extends StatelessWidget {
  const _InfoIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
      ),
      child: const Center(
        child: Icon(
          Icons.info_outline,
          size: 36,
          color: Colors.white,
        ),
      ),
    );
  }
}