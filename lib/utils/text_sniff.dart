// 文本 / 二进制的**内容判据**（不看文件名）。
//
// 为什么单开一个文件：这条判据原先只活在 server_ops 的编辑器里，于是「点开一个文件
// 该走文本还是交给别的应用」这一跳用的是**后缀白名单** —— 白名单没命中的一律被当成
// 二进制，弹「这是二进制文件」。实测 `.dev.vars`（113 B 的纯文本）就这样被挡在门外，
// 而 `.env` / `Dockerfile` / `Makefile` / `README` / `nginx.conf.bak` / `id_rsa.pub`
// 这一大批同样中招（65 个真实文件名里 44 个判错）。
//
// 口径：**名字只用来做「快速肯定」，拿不准时按内容判**。判据与 `file(1)` 的常用启发式
// 一致 —— 文本里不该有 NUL；非 UTF-8（GBK 等）当文本编辑会写坏文件，所以也不算「可编辑的文本」。
// `.dev.vars` 这类文件只有几十到几百字节，多读一次开头远比判错便宜。
//
// 明确不在这里管的：文件名后缀表（那是各插件自己的呈现偏好）、大小上限（各有各的口径）。
import 'dart:convert';
import 'dart:typed_data';

/// 嗅探要看多少字节。
///
/// 8KB 与 server_ops 原先的判据一致，也是 `file(1)` 的常用取样量：文本类文件的信息
/// 都集中在开头，再多读只是白费流量（远端存储那一侧是按 Range 读的）。
const int kTextSniffBytes = 8 * 1024;

/// 看起来是二进制吗：前 8KB 里出现 NUL 就当二进制。
bool textSniffLooksBinary(Uint8List bytes) {
  final n = bytes.length < kTextSniffBytes ? bytes.length : kTextSniffBytes;
  for (var i = 0; i < n; i++) {
    if (bytes[i] == 0) return true;
  }
  return false;
}

/// 是合法 UTF-8 吗。
///
/// 只支持 UTF-8：GBK/GB18030 的配置读进来是乱码，存回去就是**把好好的文件改坏**。
bool textSniffIsValidUtf8(Uint8List bytes) {
  try {
    utf8.decode(bytes);
    return true;
  } on FormatException {
    return false;
  }
}

/// 这段开头像文本吗（既没有 NUL、又是合法 UTF-8）。
bool textSniffSaysText(Uint8List bytes) {
  if (bytes.isEmpty) return false;
  if (textSniffLooksBinary(bytes)) return false;
  return textSniffIsValidUtf8(bytes);
}

/// 后缀**按名字**就能断定"不是文本"的那几类。
///
/// 用途只有一个：省掉一次开头读取。名字落在这些后缀上时没必要再多读一次
/// （点开一个 .png 却先网络读 8KB 是白费），直接走"交给本机应用"。
///
/// **反过来说：不在这里不等于就是文本**。文本判断以内容为准（`textSniffSaysText`），
/// 这张表只是"快速否定"。刻意不做成白名单 —— 白名单漏一个后缀就会把纯文本
/// 误报成二进制（本文件开头那段就是这么来的）。
const Set<String> kDefinitelyNonTextExts = {
  // 图片
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif', 'avif', 'ico', 'tiff', 'tif',
  // 视频
  'mp4', 'mkv', 'mov', 'avi', 'webm', '3gp', 'm4v', 'flv', 'wmv', 'mpg', 'mpeg', 'rmvb',
  // 音频
  'mp3', 'flac', 'wav', 'aac', 'm4a', 'ogg', 'opus', 'wma', 'amr', 'ape',
  // 压缩包 / 安装包 / 镜像
  'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'zst', 'apk', 'ipa', 'jar', 'war',
  'deb', 'rpm', 'iso', 'dmg', 'exe', 'msi', 'dll', 'so', 'dylib',
  // 文档 / 库 / 字体等二进制容器
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp',
  'db', 'sqlite', 'sqlite3', 'mdb', 'bin', 'dat', 'pak', 'whl', 'pyc', 'class',
  'ttf', 'otf', 'woff', 'woff2', 'eot', 'psd', 'ai', 'sketch', 'blend',
};

/// 后缀名（末尾一段，转小写；没有后缀返回空串）。
String textSniffExtOf(String name) {
  final idx = name.lastIndexOf('.');
  if (idx <= 0 || idx == name.length - 1) return '';
  return name.substring(idx + 1).toLowerCase();
}

/// 名字上就能判断"不是文本"吗（见 [kDefinitelyNonTextExts]）。
bool textSniffNameLooksNonText(String name) =>
    kDefinitelyNonTextExts.contains(textSniffExtOf(name));
