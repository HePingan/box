import 'dart:convert';
import 'dart:io';

/// 把投稿题目的本地图片转成可跨设备传输的内联负载。
///
/// 背景（真实线上故障）：投稿端过去直接把 `imageUrl` 里的
/// 设备私有路径（`/data/user/0/com.example.box/...`）塞进
/// `POST /api/quiz/submissions` 的 `image` 字段。那个字符串
/// 只在投稿者手机上有意义，审核端拿到后按相对路径拼域名请求，
/// 必然 404 —— 审核界面只显示「图片加载失败」。
///
/// 修法：提交前把本地文件读成 `data:` URL，让像素本体随请求一起走。
class QuizSubmissionImagePayload {
  const QuizSubmissionImagePayload._();

  /// 单张图片内联上限。超过则放弃内联（宁可无图，也不要提交必然失败的大请求体）。
  ///
  /// Base64 会放大约 4/3，1.5MB 原始字节约合 2MB 文本，仍在常见
  /// 服务端 body 上限（多为 4~8MB）内。若服务端放宽可上调此值。
  static const int maxInlineBytes = 1536 * 1024;

  static const Map<String, String> _mimeByExt = <String, String>{
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.webp': 'image/webp',
    '.gif': 'image/gif',
    '.bmp': 'image/bmp',
  };

  /// 把 [rawSource] 解析成 `data:` URL。
  ///
  /// 返回 null 表示「无需或无法内联」：
  /// - 已是 http(s) 或服务端相对路径（像素已在服务端）
  /// - 文件不存在、读取失败、超出 [maxInlineBytes]
  static Future<String?> inline(String? rawSource) async {
    final value = (rawSource ?? '').trim();
    if (value.isEmpty) return null;

    // 已内联，原样返回，避免二次编码把体积再放大 4/3。
    if (value.startsWith('data:')) return value;

    // 服务端已有像素，不必内联。
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return null;
    }

    final path = value.startsWith('file://')
        ? Uri.tryParse(value)?.toFilePath()
        : value;
    if (path == null || path.isEmpty) return null;

    // 只有真实存在的本地文件才值得读；服务端相对路径（/api/...）在此自然落空。
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final length = await file.length();
      if (length <= 0 || length > maxInlineBytes) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return 'data:${_mimeFor(path)};base64,${base64Encode(bytes)}';
    } catch (_) {
      return null;
    }
  }

  /// 本地同步状态字段：只对本机数据库有意义，绝不能进投稿体。
  ///
  /// 真实故障：重推一道「审核中」的题时，`QuizBankItem.toJson()`
  /// 会带上 `syncStatus: pending_review` 和旧的 `remoteSubmissionId`。
  /// 服务端据此认为该投稿已在队列中，于是不新建待审核记录，
  /// 客户端却收到 200 —— 表现为「推送成功但后台看不到待审核投稿」。
  ///
  /// 投稿只描述题目内容；状态与归属一律由服务端决定。
  static const Set<String> localOnlyFields = <String>{
    'id',
    'origin',
    'syncStatus',
    'remoteSubmissionId',
    'lastSubmitAt',
    'lastSubmitError',
  };

  /// 在提交前重写投稿 JSON 的 `image` 字段。
  ///
  /// 内联成功则替换为 data URL；失败则**移除**该字段 ——
  /// 提交一个审核端注定读不到的本地路径没有意义，只会制造
  /// 「有图但加载失败」的假象。
  static Future<Map<String, dynamic>> buildSubmissionJson(
    Map<String, dynamic> json,
  ) async {
    // 先剥掉本地状态字段，再处理图片。顺序无关，但必须两者都做：
    // 缺前者服务端不建待审核记录，缺后者审核端看不到图。
    final out = Map<String, dynamic>.from(json)
      ..removeWhere((key, _) => localOnlyFields.contains(key));

    final raw = out['image']?.toString() ?? '';
    if (raw.trim().isEmpty) return out;
    final inlined = await inline(raw);
    if (inlined != null) {
      out['image'] = inlined;
      return out;
    }

    // 只保留服务端确定能解析的形态。这里用**白名单**而不是
    // 「排除 /data /storage /sdcard」的黑名单：黑名单漏一个前缀
    // （如 /tmp、/var、/Users）就会又发出一个注定 404 的路径。
    if (!_isServerResolvable(raw.trim())) {
      out.remove('image');
    }
    return out;
  }

  /// 服务端能否自行解析该地址。
  static bool _isServerResolvable(String value) {
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return true;
    }
    // 服务端相对路径：必须命中已知的服务端资源前缀。
    const serverPrefixes = <String>[
      '/api/',
      '/uploads/',
      '/upload/',
      '/static/',
      '/media/',
      '/files/',
      '/images/',
    ];
    return serverPrefixes.any(value.startsWith);
  }

  static String _mimeFor(String path) {
    final lower = path.toLowerCase();
    for (final entry in _mimeByExt.entries) {
      if (lower.endsWith(entry.key)) return entry.value;
    }
    return 'image/png';
  }
}
