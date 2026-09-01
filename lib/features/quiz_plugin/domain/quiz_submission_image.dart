import 'dart:convert';
import 'dart:typed_data';

/// 投稿图片来源分类。
enum QuizImageSourceKind {
  /// 完全没有图片。
  none,

  /// 内联字节（`data:` URL），直接解码渲染。
  inlineBytes,

  /// 可访问的网络地址。
  networkUrl,

  /// 有来源字符串但当前端拿不到像素（例如只拿到投稿设备的本地路径）。
  unavailable,
}

/// 一次图片来源解析的结果。
class QuizImageSource {
  const QuizImageSource._({
    required this.kind,
    this.url,
    this.bytes,
    this.reason,
  });

  final QuizImageSourceKind kind;

  /// 仅 [QuizImageSourceKind.networkUrl] 时非空。
  final String? url;

  /// 仅 [QuizImageSourceKind.inlineBytes] 时非空。
  final Uint8List? bytes;

  /// 仅 [QuizImageSourceKind.unavailable] 时非空，面向审核员的人话解释。
  final String? reason;

  static const QuizImageSource empty = QuizImageSource._(
    kind: QuizImageSourceKind.none,
  );
}

/// 投稿图片来源解析。
///
/// 存在的原因是一个真实线上故障：投稿端把 **投稿设备的私有目录路径**
/// （`/data/user/0/com.example.box/...`）当作图片字段上传，审核端看到它以
/// `/` 开头，就按「服务端相对路径」拼上域名，请求
/// `https://background.hpa888.top/data/user/0/...` —— 服务器必然 404，
/// 审核员只看到「图片加载失败」。
///
/// 那个路径只在投稿者自己的手机上有意义，审核端无论怎么拼都取不到像素。
/// 所以这里显式把它判成 [QuizImageSourceKind.unavailable]，
/// 让 UI 说清「投稿端未上传图片」而不是伪装成网络错误。
class QuizSubmissionImage {
  const QuizSubmissionImage._();

  /// Android/iOS 应用私有目录或外部存储的绝对路径前缀。
  static const List<String> _deviceLocalPrefixes = <String>[
    '/data/',
    '/storage/',
    '/sdcard/',
    '/var/mobile/',
    '/private/var/',
  ];

  /// 判断 [raw] 是否是「投稿设备本地路径」。
  ///
  /// 这类值不能拼域名，也不能在审核端 `Image.file` 打开
  /// （审核员的设备上没有这个文件）。
  static bool isDeviceLocalPath(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return false;
    if (value.startsWith('data:')) return false;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return false;
    }
    if (value.startsWith('file://')) return true;
    for (final prefix in _deviceLocalPrefixes) {
      if (value.startsWith(prefix)) return true;
    }
    return false;
  }

  /// 把投稿记录里的图片字段解析成可渲染的来源。
  ///
  /// [serverUrl] 是当前登录的服务端地址；相对路径拼它，而不是硬编码域名，
  /// 这样切换环境（测试/生产）时审核端不会去请求错误的主机。
  static QuizImageSource resolveForDisplay(
    String? rawSource, {
    required String serverUrl,
  }) {
    final value = (rawSource ?? '').trim();
    if (value.isEmpty) return QuizImageSource.empty;

    // 1) 内联字节：唯一一种审核端一定能看到像素的形态。
    if (value.startsWith('data:')) {
      final comma = value.indexOf(',');
      if (comma < 0) {
        return const QuizImageSource._(
          kind: QuizImageSourceKind.unavailable,
          reason: '图片数据损坏（data URL 缺少分隔符）',
        );
      }
      try {
        final bytes = base64Decode(value.substring(comma + 1));
        if (bytes.isEmpty) {
          return const QuizImageSource._(
            kind: QuizImageSourceKind.unavailable,
            reason: '图片数据损坏（解码后为空）',
          );
        }
        return QuizImageSource._(
          kind: QuizImageSourceKind.inlineBytes,
          bytes: bytes,
        );
      } catch (_) {
        return const QuizImageSource._(
          kind: QuizImageSourceKind.unavailable,
          reason: '图片数据损坏（Base64 解码失败）',
        );
      }
    }

    // 2) 投稿设备本地路径：审核端取不到，必须在拼 URL 之前拦掉。
    if (isDeviceLocalPath(value)) {
      return const QuizImageSource._(
        kind: QuizImageSourceKind.unavailable,
        reason: '投稿端未上传图片本体，只回传了投稿设备上的本地路径，'
            '审核端无法读取。请让投稿者在新版客户端重新提交。',
      );
    }

    // 3) 绝对 URL：原样使用。
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return QuizImageSource._(
        kind: QuizImageSourceKind.networkUrl,
        url: value,
      );
    }

    // 4) 服务端相对路径：拼当前 serverUrl。
    final base = serverUrl.trim();
    if (base.isEmpty) {
      return const QuizImageSource._(
        kind: QuizImageSourceKind.unavailable,
        reason: '未配置服务端地址，无法解析图片相对路径',
      );
    }
    final host = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final path = value.startsWith('/') ? value : '/$value';
    return QuizImageSource._(
      kind: QuizImageSourceKind.networkUrl,
      url: '$host$path',
    );
  }
}
