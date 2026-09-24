// 远程存储 domain 层纯函数/模型单测（无网络、无插件依赖）。
//
// 覆盖：内网判定、http 放行策略、地址校验、路径编码/拼接/父路径、
// 条目分类、字节格式化、文件名清洗、错误映射单一事实源、取消令牌、
// 账户 JSON 往返。

import 'dart:convert';

import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('isPrivateHost（拍板 5 的内网判定）', () {
    test('回环与本机名', () {
      expect(isPrivateHost('127.0.0.1'), isTrue);
      expect(isPrivateHost('127.8.8.8'), isTrue);
      expect(isPrivateHost('localhost'), isTrue);
      expect(isPrivateHost('::1'), isTrue);
      expect(isPrivateHost('[::1]'), isTrue);
    });

    test('RFC1918 三段与边界', () {
      expect(isPrivateHost('10.0.0.1'), isTrue);
      expect(isPrivateHost('172.16.0.1'), isTrue);
      expect(isPrivateHost('172.31.255.254'), isTrue);
      expect(isPrivateHost('172.32.0.1'), isFalse);
      expect(isPrivateHost('172.15.0.1'), isFalse);
      expect(isPrivateHost('192.168.1.10'), isTrue);
      expect(isPrivateHost('192.169.0.1'), isFalse);
    });

    test('链路本地 / CGNAT / 公网', () {
      expect(isPrivateHost('169.254.1.1'), isTrue);
      expect(isPrivateHost('100.64.0.1'), isTrue);
      expect(isPrivateHost('100.127.255.1'), isTrue);
      expect(isPrivateHost('100.128.0.1'), isFalse);
      expect(isPrivateHost('8.8.8.8'), isFalse);
      expect(isPrivateHost('dav.jianguoyun.com'), isFalse);
    });

    test('.local 与单标签主机名', () {
      expect(isPrivateHost('nas.local'), isTrue);
      expect(isPrivateHost('mynas'), isTrue);
      expect(isPrivateHost('NAS'), isTrue);
      expect(isPrivateHost(''), isFalse);
      expect(isPrivateHost('   '), isFalse);
    });
  });

  group('RemoteStorageAccount.httpEffectiveAllowed（拍板 5 策略）', () {
    test('auto：私网放行，公网禁止', () {
      expect(
        testAccount(baseUrl: 'http://192.168.1.2:5005/webdav')
            .httpEffectiveAllowed,
        isTrue,
      );
      expect(
        testAccount(baseUrl: 'http://8.8.8.8/dav').httpEffectiveAllowed,
        isFalse,
      );
    });

    test('allow 始终放行；deny 始终禁止', () {
      expect(
        testAccount(baseUrl: 'http://8.8.8.8/dav', tlsMode: RemoteTlsMode.allow)
            .httpEffectiveAllowed,
        isTrue,
      );
      expect(
        testAccount(
          baseUrl: 'http://192.168.1.2/webdav',
          tlsMode: RemoteTlsMode.deny,
        ).httpEffectiveAllowed,
        isFalse,
      );
    });

    test('https 恒为 false（不涉及明文放行）', () {
      expect(
        testAccount(baseUrl: 'https://dav.jianguoyun.com/dav/')
            .httpEffectiveAllowed,
        isFalse,
      );
    });
  });

  group('displayHost / isInsecure', () {
    test('displayHost 保留端口', () {
      expect(
        testAccount(baseUrl: 'https://dav.jianguoyun.com/dav/').displayHost,
        'dav.jianguoyun.com',
      );
      expect(
        testAccount(baseUrl: 'http://192.168.1.2:5005/webdav').displayHost,
        '192.168.1.2:5005',
      );
    });

    test('isInsecure 覆盖 http 与自签名开关', () {
      expect(testAccount(baseUrl: 'http://192.168.1.2/webdav').isInsecure,
          isTrue);
      expect(
        testAccount(
          baseUrl: 'https://nas.local:5006/dav',
          allowBadCert: true,
        ).isInsecure,
        isTrue,
      );
      expect(
        testAccount(baseUrl: 'https://dav.jianguoyun.com/dav/').isInsecure,
        isFalse,
      );
    });
  });

  group('validateBaseUrl', () {
    test('空值', () {
      expect(RemoteStorageAccount.validateBaseUrl(''), '请输入服务器地址');
      expect(RemoteStorageAccount.validateBaseUrl('   '), '请输入服务器地址');
    });

    test('缺协议前缀被拒绝', () {
      expect(
        RemoteStorageAccount.validateBaseUrl('dav.jianguoyun.com/dav'),
        '地址无法解析，请包含 http:// 或 https:// 前缀',
      );
    });

    test('非 http/https 被拒绝', () {
      expect(
        RemoteStorageAccount.validateBaseUrl('ftp://example.com'),
        '仅支持 http:// 与 https://',
      );
    });

    test('合法地址返回 null', () {
      expect(
        RemoteStorageAccount.validateBaseUrl(
          'https://dav.jianguoyun.com/dav/',
        ),
        isNull,
      );
      expect(
        RemoteStorageAccount.validateBaseUrl('http://192.168.1.2:5005/webdav'),
        isNull,
      );
    });
  });

  group('newId', () {
    test('前缀 rs_ 且不重复', () {
      final a = RemoteStorageAccount.newId();
      final b = RemoteStorageAccount.newId();
      expect(a, startsWith('rs_'));
      expect(a, isNot(b));
    });
  });

  group('账户 JSON 往返', () {
    test('全字段往返一致', () {
      final account = testAccount(
        tlsMode: RemoteTlsMode.allow,
        allowBadCert: true,
        showSystemFolders: true,
        createdAt: 123456,
      );
      final restored = RemoteStorageAccount.fromJson(account.toJson());
      expect(restored, isNotNull);
      expect(restored!.id, account.id);
      expect(restored.label, account.label);
      expect(restored.baseUrl, account.baseUrl);
      expect(restored.username, account.username);
      expect(restored.password, account.password);
      expect(restored.tlsMode, RemoteTlsMode.allow);
      expect(restored.allowBadCert, isTrue);
      expect(restored.showSystemFolders, isTrue);
      expect(restored.createdAt, 123456);
    });

    test('缺 id/baseUrl 返回 null；可选字段取默认', () {
      expect(RemoteStorageAccount.fromJson({'baseUrl': 'https://x/'}), isNull);
      expect(RemoteStorageAccount.fromJson({'id': 'a'}), isNull);
      expect(RemoteStorageAccount.fromJson('not-a-map'), isNull);

      final minimal = RemoteStorageAccount.fromJson({
        'id': 'rs_1',
        'baseUrl': 'https://x/',
      });
      expect(minimal, isNotNull);
      expect(minimal!.tlsMode, RemoteTlsMode.auto);
      expect(minimal.allowBadCert, isFalse);
      expect(minimal.createdAt, greaterThan(0));
    });

    test('copyWith 保留 id/createdAt，覆盖其余字段', () {
      final account = testAccount(createdAt: 999);
      final updated = account.copyWith(
        label: '新名字',
        tlsMode: RemoteTlsMode.deny,
      );
      expect(updated.id, account.id);
      expect(updated.createdAt, 999);
      expect(updated.label, '新名字');
      expect(updated.tlsMode, RemoteTlsMode.deny);
      expect(updated.password, account.password);
    });
  });

  group('remoteEntryKind', () {
    RemoteStorageEntry entry(String name, {bool dir = false}) =>
        RemoteStorageEntry(name: name, path: name, isDirectory: dir);

    test('目录/图片/视频/音频/文本/其它', () {
      expect(remoteEntryKind(entry('Box', dir: true)), RemoteEntryKind.folder);
      expect(remoteEntryKind(entry('a.png')), RemoteEntryKind.image);
      expect(remoteEntryKind(entry('照片.PNG')), RemoteEntryKind.image);
      expect(remoteEntryKind(entry('v.mp4')), RemoteEntryKind.video);
      expect(remoteEntryKind(entry('s.flac')), RemoteEntryKind.audio);
      expect(remoteEntryKind(entry('笔记.md')), RemoteEntryKind.text);
      expect(remoteEntryKind(entry('archive.zip')), RemoteEntryKind.other);
      expect(remoteEntryKind(entry('无扩展名')), RemoteEntryKind.other);
    });
  });

  group('formatRemoteBytes', () {
    test('阈值与精度', () {
      expect(formatRemoteBytes(null), '');
      expect(formatRemoteBytes(-1), '');
      expect(formatRemoteBytes(512), '512 B');
      expect(formatRemoteBytes(1024), '1.00 KB');
      expect(formatRemoteBytes(1536), '1.50 KB');
      expect(formatRemoteBytes(100 * 1024), '100 KB');
      expect(formatRemoteBytes(20 * 1024 * 1024), '20.0 MB');
    });
  });

  group('sanitizeRemoteSegment', () {
    test('合法名', () {
      expect(sanitizeRemoteSegment('a.txt'), 'a.txt');
      expect(sanitizeRemoteSegment(' 笔记.md '), '笔记.md');
    });

    test('越权与非法字符被拒', () {
      expect(sanitizeRemoteSegment(''), isNull);
      expect(sanitizeRemoteSegment('.'), isNull);
      expect(sanitizeRemoteSegment('..'), isNull);
      expect(sanitizeRemoteSegment('a/b'), isNull);
      expect(sanitizeRemoteSegment(r'a\b'), isNull);
      expect(sanitizeRemoteSegment('a\u0001b'), isNull);
      expect(sanitizeRemoteSegment('x' * 256), isNull);
    });

    test('长度按 UTF-8 字节判：86 个汉字 = 258 字节被拒，85 个通过', () {
      final bytes = remoteSegmentByteLength('中' * 86);
      expect(bytes, 258, reason: '汉字 3 字节，旧实现按 UTF-16 数只有 86 通过');
      expect(sanitizeRemoteSegment('中' * 86), isNull);
      expect(sanitizeRemoteSegment('中' * 85), '中' * 85);
      expect(remoteSegmentByteLength('中' * 85), 255);
    });

    test('结尾的点会被削掉（SMB 会静默截断，削掉后两种后端一致）', () {
      expect(sanitizeRemoteSegment('报告.'), '报告');
      expect(sanitizeRemoteSegment('a.txt...'), 'a.txt');
      expect(sanitizeRemoteSegment('...'), isNull, reason: '全是点 → 空名');
      expect(sanitizeRemoteSegment('名字 .'), '名字');
    });

    test('Windows 保留名被拒（含带扩展名的形式）', () {
      for (final name in ['CON', 'con', 'NUL', 'nul.txt', 'aux.tar.gz', 'COM1', 'lpt9.log']) {
        expect(sanitizeRemoteSegment(name), isNull, reason: name);
      }
      expect(sanitizeRemoteSegment('console.txt'), 'console.txt', reason: '不做前缀匹配');
      expect(sanitizeRemoteSegment('COM10'), 'COM10', reason: 'COM10 不是保留名');
    });

    test('拒绝原因可读，且与清洗判定一致', () {
      expect(remoteSegmentRejectionReason('a.txt'), isNull);
      expect(remoteSegmentRejectionReason(''), contains('空'));
      expect(remoteSegmentRejectionReason('.'), contains('不能是'));
      expect(remoteSegmentRejectionReason('a/b'), contains('分隔符'));
      expect(remoteSegmentRejectionReason('中' * 86), contains('字节'));
      expect(remoteSegmentRejectionReason('NUL'), contains('保留名'));
      expect(remoteSegmentRejectionReason('...'), contains('点'));

      // 判据一致：reason 说合法 ⇔ sanitize 返回非 null
      for (final name in ['a.txt', '.', '..', '...', 'NUL', '报告.', '中' * 86]) {
        expect(
          remoteSegmentRejectionReason(name) == null,
          sanitizeRemoteSegment(name) != null,
          reason: '两处判据必须同步：$name',
        );
      }
    });
  });

  group('上传前配额判断（O5）', () {
    test('服务端给了可用配额且本次超出 → 提示', () {
      expect(
        uploadExceedsQuota(const RemoteStorageQuota(availableBytes: 100), 101),
        isTrue,
      );
      expect(
        uploadExceedsQuota(const RemoteStorageQuota(availableBytes: 100), 100),
        isFalse,
        reason: '刚好用完不算超',
      );
      expect(
        uploadExceedsQuota(const RemoteStorageQuota(availableBytes: 0), 1),
        isTrue,
      );
    });

    test('配额未知/缺属性/负数 → 一律不提示（不拿猜出来的数字吓用户）', () {
      expect(uploadExceedsQuota(null, 1 << 40), isFalse);
      expect(uploadExceedsQuota(const RemoteStorageQuota(), 1 << 40), isFalse);
      expect(
        uploadExceedsQuota(const RemoteStorageQuota(usedBytes: 5), 1 << 40),
        isFalse,
      );
      expect(
        uploadExceedsQuota(
          const RemoteStorageQuota(availableBytes: -3),
          1 << 40,
        ),
        isFalse,
        reason: 'RFC 4331 的负数表示未知',
      );
    });
  });

  group('路径工具', () {
    test('encodeRemotePath 逐段编码', () {
      expect(
        encodeRemotePath('a b/中文.txt'),
        'a%20b/%E4%B8%AD%E6%96%87.txt',
      );
      expect(encodeRemotePath('/a//b'), 'a/b');
      expect(encodeRemotePath(''), '');
    });

    test('joinRemotePath', () {
      expect(joinRemotePath('dir', 'a.txt'), 'dir/a.txt');
      expect(joinRemotePath('', 'a.txt'), 'a.txt');
      expect(joinRemotePath('   ', 'a.txt'), 'a.txt');
    });

    test('parentRemotePath', () {
      expect(parentRemotePath('a/b/c.txt'), 'a/b');
      expect(parentRemotePath('a/b'), 'a');
      expect(parentRemotePath('a'), '');
      expect(parentRemotePath(''), '');
    });
  });

  group('TransferCancelToken', () {
    test('未取消时不抛；取消后 throwIfCanceled 抛异常', () {
      final token = TransferCancelToken();
      token.throwIfCanceled();
      expect(token.isCanceled, isFalse);
      token.cancel();
      expect(token.isCanceled, isTrue);
      expect(token.throwIfCanceled, throwsA(isA<TransferCanceledException>()));
    });
  });

  group('错误映射单一事实源（§5.5）', () {
    test('状态码 → 种类', () {
      expect(
        remoteStorageExceptionForStatus(401).kind,
        RemoteStorageError.unauthorized,
      );
      expect(
        remoteStorageExceptionForStatus(403).kind,
        RemoteStorageError.forbidden,
      );
      expect(
        remoteStorageExceptionForStatus(404).kind,
        RemoteStorageError.notFound,
      );
      expect(
        remoteStorageExceptionForStatus(405).kind,
        RemoteStorageError.methodNotAllowed,
      );
      expect(
        remoteStorageExceptionForStatus(409).kind,
        RemoteStorageError.conflict,
      );
      expect(
        remoteStorageExceptionForStatus(507).kind,
        RemoteStorageError.insufficientStorage,
      );
      expect(
        remoteStorageExceptionForStatus(500).kind,
        RemoteStorageError.http,
      );
    });

    test('消息与状态码', () {
      final unauthorized = remoteStorageExceptionForStatus(401);
      expect(unauthorized.statusCode, 401);
      expect(
        unauthorized.message,
        '用户名或密码不正确；坚果云请使用网页端生成的「应用密码」',
      );

      final generic = remoteStorageExceptionForStatus(302);
      expect(generic.message, '服务器返回 HTTP 302');
    });

    test('remoteStorageErrorMessage 文案', () {
      expect(
        remoteStorageErrorMessage(RemoteStorageError.http, statusCode: 500),
        '服务器返回 HTTP 500',
      );
      expect(
        remoteStorageErrorMessage(RemoteStorageError.http),
        '服务器返回 HTTP ?',
      );
      expect(
        remoteStorageErrorMessage(RemoteStorageError.unknown),
        '操作失败',
      );
      expect(
        remoteStorageErrorMessage(
          RemoteStorageError.unknown,
          detail: '底层炸了',
        ),
        '操作失败：底层炸了',
      );
      expect(
        remoteStorageErrorMessage(RemoteStorageError.network),
        '网络错误，无法连接服务器',
      );
    });
  });

  group('PreviewPayload', () {
    test('文本解码与超限', () {
      final ok = PreviewPayload(
        bytes: utf8.encode('你好'),
        truncated: false,
        oversize: false,
      );
      expect(ok.textOrNull, '你好');

      const big = PreviewPayload(
        bytes: [1, 2, 3],
        truncated: true,
        oversize: true,
        totalLength: 999999,
      );
      expect(big.textOrNull, isNull);
      expect(big.truncated, isTrue);
      expect(big.totalLength, 999999);
    });
  });

  group('图片预览降采样宽度（C4）', () {
    test('按屏幕宽度 × 像素比 × 2 计算', () {
      expect(
        previewImageDecodeWidth(logicalWidth: 400, devicePixelRatio: 3),
        2400, // 400 × 3 × 2
      );
      expect(
        previewImageDecodeWidth(logicalWidth: 411.4, devicePixelRatio: 2.625),
        2160, // 411.4 × 2.625 × 2 = 2159.85 → 四舍五入
      );
    });

    test('设备信息不可用 → 不限制（不猜一个错的宽度把图糊掉）', () {
      expect(previewImageDecodeWidth(logicalWidth: 0, devicePixelRatio: 3), isNull);
      expect(previewImageDecodeWidth(logicalWidth: 400, devicePixelRatio: 0), isNull);
      expect(previewImageDecodeWidth(logicalWidth: -1, devicePixelRatio: -1), isNull);
    });

    test('倍数为 2：再大对肉眼无意义，只是白吃内存', () {
      expect(kPreviewImageDecodeWidthFactor, 2);
    });
  });

  group('重试判定与退避（O2：别让凭证错白等退避）', () {
    test('可重试：网络抖动 / 超时 / 429 / 5xx / 无状态码的 http / 非归一异常', () {
      final retryable = <Object>[
        const RemoteStorageException(RemoteStorageError.timeout, '连接超时'),
        const RemoteStorageException(RemoteStorageError.network, '网络错误'),
        remoteStorageExceptionForStatus(408),
        remoteStorageExceptionForStatus(429),
        remoteStorageExceptionForStatus(500),
        remoteStorageExceptionForStatus(503),
        const RemoteStorageException(RemoteStorageError.http, 'HTTP 未知'),
        Exception('未知异常'),
      ];
      for (final e in retryable) {
        expect(isRetryableTransferError(e), isTrue, reason: '$e 应可重试');
      }
    });

    test('不重试：凭证 / 权限 / 路径 / 方法 / 冲突 / 空间 / 证书 / 取消 / 未知', () {
      final fatal = <Object>[
        remoteStorageExceptionForStatus(400),
        remoteStorageExceptionForStatus(401),
        remoteStorageExceptionForStatus(403),
        remoteStorageExceptionForStatus(404),
        remoteStorageExceptionForStatus(405),
        remoteStorageExceptionForStatus(409),
        remoteStorageExceptionForStatus(412),
        remoteStorageExceptionForStatus(507),
        const RemoteStorageException(RemoteStorageError.certificate, '证书'),
        const RemoteStorageException(RemoteStorageError.canceled, '取消'),
        const RemoteStorageException(RemoteStorageError.unknown, '未知'),
        const TransferCanceledException(),
      ];
      for (final e in fatal) {
        expect(isRetryableTransferError(e), isFalse, reason: '$e 不应重试');
      }
    });

    test('退避序列递进；越界取两端（不崩）', () {
      expect(kTransferRetryDelays, hasLength(kTransferRetries));
      expect(retryDelayFor(1), kTransferRetryDelays.first);
      expect(retryDelayFor(2), kTransferRetryDelays.last);
      expect(retryDelayFor(9), kTransferRetryDelays.last);
      expect(retryDelayFor(0), kTransferRetryDelays.first);
      expect(retryDelayFor(-3), kTransferRetryDelays.first);
      expect(
        kTransferRetryDelays.first < kTransferRetryDelays.last,
        isTrue,
        reason: '必须是递进而非固定等待',
      );
    });

    test('Retry-After 更长时取更长；更短时不拖慢退避', () {
      expect(
        retryDelayFor(1, retryAfter: const Duration(seconds: 30)),
        const Duration(seconds: 30),
      );
      expect(
        retryDelayFor(2, retryAfter: const Duration(milliseconds: 10)),
        kTransferRetryDelays.last,
      );
    });

    test('429 的 Retry-After 挂在异常上，供队列读取', () {
      final e = remoteStorageExceptionForStatus(
        429,
        retryAfter: const Duration(seconds: 5),
      );
      expect(e.kind, RemoteStorageError.http);
      expect(e.statusCode, 429);
      expect(e.retryAfter, const Duration(seconds: 5));
      expect(isRetryableTransferError(e), isTrue);
    });
  });

  group('导出策略（B2：SAF 阈值与 MIME）', () {
    test('64MB 以内走系统另存，超过走分享', () {
      expect(
        exportStrategyFor(1024),
        RemoteExportStrategy.safSave,
      );
      expect(
        exportStrategyFor(kSafExportMaxBytes),
        RemoteExportStrategy.safSave,
      );
      expect(
        exportStrategyFor(kSafExportMaxBytes + 1),
        RemoteExportStrategy.shareFromAppDir,
      );
    });

    test('大小未知/非法 → 保守走分享（不赌内存）', () {
      expect(exportStrategyFor(null), RemoteExportStrategy.shareFromAppDir);
      expect(exportStrategyFor(0), RemoteExportStrategy.shareFromAppDir);
      expect(exportStrategyFor(-1), RemoteExportStrategy.shareFromAppDir);
    });

    test('MIME 按扩展名给，大小写不敏感，未知扩展名回落二进制流', () {
      expect(mimeTypeForFileName('a.mp4'), 'video/mp4');
      expect(mimeTypeForFileName('A.JPG'), 'image/jpeg');
      expect(mimeTypeForFileName('book.epub'), 'application/epub+zip');
      expect(mimeTypeForFileName('noext'), 'application/octet-stream');
    });
  });

  group('列表缩略图判定（281+）', () {
    RemoteStorageEntry entry({
      String name = 'a.jpg',
      String? path,
      bool dir = false,
      int? size = 1000,
      DateTime? modifiedAt,
    }) => RemoteStorageEntry(
      name: name,
      path: path ?? name,
      isDirectory: dir,
      size: size,
      modifiedAt: modifiedAt,
    );

    test('图片、大小已知且不超上限 → 取缩略图', () {
      expect(isThumbnailableEntry(entry()), isTrue);
      expect(
        isThumbnailableEntry(entry(size: kThumbnailMaxBytes)),
        isTrue,
        reason: '正好等于上限也可以取',
      );
    });

    test('非图片不取（视频/音频/文本/其他）', () {
      for (final name in ['a.mp4', 'a.mp3', 'a.txt', 'a.zip', 'noext']) {
        expect(
          isThumbnailableEntry(entry(name: name)),
          isFalse,
          reason: '$name 不该取缩略图',
        );
      }
    });

    test('超过上限不取：不为一行 40dp 的缩略图去拉一张 10MB 原图', () {
      expect(isThumbnailableEntry(entry(size: kThumbnailMaxBytes + 1)), isFalse);
    });

    test('大小未知（null / 0）不取——不为了猜大小多发一次请求', () {
      expect(isThumbnailableEntry(entry(size: null)), isFalse);
      expect(isThumbnailableEntry(entry(size: 0)), isFalse);
    });

    test('目录不取（即使名字像图片）', () {
      expect(isThumbnailableEntry(entry(name: 'a.jpg', dir: true)), isFalse);
    });

    test('缓存键：账户 / 路径 / 大小 / 修改时间任一变化都要换键', () {
      final base = entry(
        modifiedAt: DateTime.utc(2023, 1, 30, 11, 22),
      );
      final key = thumbnailCacheKey('acct1', base);
      expect(thumbnailCacheKey('acct1', base), key, reason: '同样的条目 → 同样的键');

      expect(thumbnailCacheKey('acct2', base), isNot(key));
      expect(
        thumbnailCacheKey('acct1', entry(path: 'other.jpg', modifiedAt: base.modifiedAt)),
        isNot(key),
      );
      expect(
        thumbnailCacheKey('acct1', entry(size: 2000, modifiedAt: base.modifiedAt)),
        isNot(key),
        reason: '文件被替换（大小变了）→ 旧缩略图必须失效',
      );
      expect(
        thumbnailCacheKey(
          'acct1',
          entry(modifiedAt: DateTime.utc(2024, 1, 1)),
        ),
        isNot(key),
        reason: '修改时间变了也要失效',
      );
    });
  });
}
