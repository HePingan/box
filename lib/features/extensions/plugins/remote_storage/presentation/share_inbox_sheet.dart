// 收到系统分享后的落点面板（286 P3）。
//
// 为什么要有这一步而不是"直接开始上传"：远程存储有多个账户、也有目录，
// 分享进来的图/视频必须有人回答"传到哪个账户的哪个目录"。默认给第一个账户
// 与根目录，用户改一下就能传，不需要先去插件里选。
//
// 上传全部走已有的传输队列（含并发/重试/落盘/前台保活），不另开一条通路；
// 传成功后删掉缓存里的中转副本（原生侧 24h 还会兜底清一次）。
library;

import 'dart:io';

import 'package:box/features/extensions/plugins/remote_storage/application/remote_storage_service.dart';
import 'package:box/features/extensions/plugins/remote_storage/application/transfer_queue.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/share_inbox_models.dart';
import 'package:flutter/material.dart';

class ShareInboxSheet extends StatefulWidget {
  const ShareInboxSheet({super.key, required this.files});

  final List<SharedInboxFile> files;

  @override
  State<ShareInboxSheet> createState() => _ShareInboxSheetState();
}

class _ShareInboxSheetState extends State<ShareInboxSheet> {
  List<RemoteStorageAccount> _accounts = const <RemoteStorageAccount>[];
  RemoteStorageAccount? _account;
  final TextEditingController _dirController = TextEditingController(text: '/');
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  @override
  void dispose() {
    _dirController.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    try {
      final accounts = await remoteStorageService().loadAccounts();
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _account = accounts.isEmpty ? null : accounts.first;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _loading = false;
      });
    }
  }

  /// 目标目录：留空、`/`、末尾多余的斜杠都归一化。
  ///
  /// 空串就是根目录（与浏览页一致：浏览到根时 `_path` 是空串，不是 `/`）；
  /// 用户随手打字（`相册/2026`、`/相册/2026/`）不该报错，也不该拼出 `//`。
  String get _targetDir {
    var raw = _dirController.text.trim();
    if (raw.isEmpty || raw == '/') return '';
    while (raw.length > 1 && raw.endsWith('/')) {
      raw = raw.substring(0, raw.length - 1);
    }
    return raw.startsWith('/') ? raw : '/$raw';
  }

  void _startUpload() {
    final account = _account;
    if (account == null) return;
    final queue = transferQueue();
    final service = remoteStorageService();
    final dir = _targetDir;
    final dirLabel = dir.isEmpty ? '根目录' : dir;

    for (final file in widget.files) {
      queue.enqueue(
        kind: TransferKind.upload,
        title: file.name,
        subtitle: '${account.label} · $dirLabel',
        totalBytes: file.sizeBytes,
        runner: (cancel, onProgress) => service.uploadFile(
          account,
          file: LocalUploadFile(
            path: file.path,
            name: file.name,
            size: file.sizeBytes,
          ),
          targetDir: dir,
          overwrite: false,
          onProgress: onProgress,
          cancel: cancel,
        ),
        // 落盘信息：应用被杀后能按原样重建这条上传（缓存里的中转副本还在）。
        spec: TransferRestoreSpec(
          kind: TransferKind.upload,
          accountId: account.id,
          remotePath: dir,
          localPath: file.path,
          fileName: file.name,
          overwrite: false,
          title: file.name,
          subtitle: '${account.label} · $dirLabel',
          totalBytes: file.sizeBytes,
        ),
        onFinished: (task) {
          if (task.status == TransferStatus.done) {
            _deleteInboxCopy(file.path);
          }
        },
      );
    }

    Navigator.of(context).pop();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('已加入传输队列：${widget.files.length} 个文件')),
    );
  }

  /// 删掉缓存里的中转副本。
  ///
  /// **只删我们自己的中转文件**：路径必须落在 `shared_inbox` 目录里。
  /// 万一 spec/路径来源变了，也绝不能删用户相册里的原文件。
  static void _deleteInboxCopy(String path) {
    if (!path.contains('/shared_inbox/')) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // 删不掉不影响上传结果：原生侧 24h 兜底清理。
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final files = widget.files;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: 12 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inbox_rounded),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '收到 ${files.length} 个分享文件',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '传到哪里？',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: files.length,
                itemBuilder: (context, index) {
                  final file = files[index];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      file.isVideo
                          ? Icons.videocam_outlined
                          : Icons.image_outlined,
                    ),
                    title: Text(file.name, maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(formatRemoteBytes(file.sizeBytes)),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_loadError != null)
              Text('读取账户失败：$_loadError',
                  style: theme.textTheme.bodySmall)
            else if (_accounts.isEmpty)
              Text(
                '还没有远程存储账户：先去「远程存储」插件里添加一个，再回来分享。',
                style: theme.textTheme.bodySmall,
              )
            else ...[
              DropdownButtonFormField<RemoteStorageAccount>(
                initialValue: _account,
                decoration: const InputDecoration(
                  labelText: '账户',
                  isDense: true,
                ),
                items: [
                  for (final account in _accounts)
                    DropdownMenuItem(
                      value: account,
                      child: Text(account.label),
                    ),
                ],
                onChanged: (value) => setState(() => _account = value),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _dirController,
                decoration: const InputDecoration(
                  labelText: '目标目录',
                  hintText: '留空或 / 表示根目录，例如 /相册/2026',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _startUpload,
                    icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                    label: const Text('上传到远程存储'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
