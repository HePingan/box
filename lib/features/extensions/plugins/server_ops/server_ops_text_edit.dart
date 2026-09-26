// 服务器运维插件：文件「编辑」的**纯逻辑** —— 能不能编辑 / 保存时怎么还原原风格 /
// 备份命名与清理 / 哪些文件保存前得多一道确认。
//
// 为什么单开一个文件：这些判断错了后果很实在 —— 把 GBK 的配置存成乱码、
// 覆盖掉别人刚改过的文件、改坏 sshd_config 把自己锁在门外。而它们都不依赖
// 平台、不依赖网络，抽出来就能被真正验证（跟 terminal_controls.dart 一个道理）。
//
// 明确不在这里管的：上传本身成不成功（服务层）、编辑器的手感与键盘（真机）。

import 'dart:convert';
import 'dart:typed_data';

/// 允许编辑的大小上限。预览另有一套更小的（`kOpsPreviewMaxBytes = 64KB`）：
/// 看 64KB 够，改 256KB 也够；再大就该用专门的工具，而不是在手机软键盘上滚。
const int kOpsEditMaxBytes = 256 * 1024;

/// 备份保留份数（超出的自动删）。
const int kOpsBackupKeep = 3;

/// 落盘途中那个临时文件名的标记（保存成功后它就不存在了；万一失败也是先删它）。
const String kOpsPendingMarker = '.box-new-';

/// 备份文件名的标记：`hosts` → `hosts.box-bak-20260926-150501`。
///
/// 为什么放在**同目录**而不是隐藏目录：手机文件页里直接看得见、能手动删，
/// 出问题时不用记一个特殊路径。
const String kOpsBackupMarker = '.box-bak-';

/// 看起来是二进制吗：前 8KB 里出现 NUL 就当作二进制。
///
/// 判据跟 `file(1)` 的常用启发式一致 —— 文本文件里不该有 NUL，
/// 有就说明是图片/压缩包/可执行文件，不能拿去当文本编辑。
bool opsLooksBinary(Uint8List bytes) {
  final n = bytes.length < 8192 ? bytes.length : 8192;
  for (var i = 0; i < n; i++) {
    if (bytes[i] == 0) return true;
  }
  return false;
}

/// 是合法 UTF-8 吗。
///
/// 只支持 UTF-8：GBK/GB18030 的配置读进来是乱码，存回去就是**把好好的文件改坏**。
/// 遇到这种文件只给预览、不给编辑，并在界面上说明原因。
bool opsIsValidUtf8(Uint8List bytes) {
  try {
    utf8.decode(bytes);
    return true;
  } on FormatException {
    return false;
  }
}

/// 原文件的"风格"：有没有 BOM、结尾有没有换行、换行是 CRLF 还是 LF。
///
/// 保存时按这套还原：编辑器里的 `TextEditingController` 会把 CRLF 归一成 LF，
/// 直接存回去等于"顺手把整个文件的换行都改了" —— diff 一屏红。
class OpsTextStyle {
  const OpsTextStyle({
    required this.bom,
    required this.trailingNewline,
    required this.crlf,
  });

  /// UTF-8 BOM（`EF BB BF`）。
  final bool bom;

  /// 原文件结尾有换行（编辑器里看不出来，但是 POSIX 文本的规矩）。
  final bool trailingNewline;

  /// 用 CRLF（Windows 风格）。
  final bool crlf;

  static const OpsTextStyle plain = OpsTextStyle(
    bom: false,
    trailingNewline: false,
    crlf: false,
  );

  static OpsTextStyle detect(Uint8List bytes, String text) {
    final bom = bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF;
    return OpsTextStyle(
      bom: bom,
      trailingNewline: text.isNotEmpty && text.endsWith('\n'),
      crlf: text.contains('\r\n'),
    );
  }
}

/// 按原风格编码回去：BOM、结尾换行、换行符形式都跟着原文件走。
///
/// 传进来的文本是编辑器里的内容（LF）；这里负责"翻译"回原文件的写法。
Uint8List opsEncodeWithStyle(String text, OpsTextStyle style) {
  var out = text;
  if (style.crlf) {
    // 先把可能混进来的 CRLF 归一，再统一换掉，避免出现 \r\r\n
    out = out.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
  }
  if (style.trailingNewline && out.isNotEmpty && !out.endsWith('\n')) {
    out += style.crlf ? '\r\n' : '\n';
  }
  final body = utf8.encode(out);
  if (!style.bom) return Uint8List.fromList(body);
  return Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, ...body]);
}

String _two(int v) => v.toString().padLeft(2, '0');

/// 备份文件名：`<path>.box-bak-YYYYMMDD-HHMMSS`。
///
/// 精确到秒就够（同一秒内两次保存会撞名，服务端的 exists 预检会当场拦住，
/// 不会静默覆盖掉上一份备份 —— 那正是我们要的）。
String opsBackupName(String path, DateTime now) {
  final t = now.toLocal();
  final stamp = '${t.year}${_two(t.month)}${_two(t.day)}'
      '-${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';
  return '$path$kOpsBackupMarker$stamp';
}

/// 是不是本插件生成的备份文件。
bool opsIsBackupName(String name) => name.contains(kOpsBackupMarker);

/// 备份名 → 原文件名（`hosts.box-bak-2026…` → `hosts`）；不是备份就返回原串。
String opsOriginalNameFromBackup(String backupName) {
  final at = backupName.indexOf(kOpsBackupMarker);
  return at < 0 ? backupName : backupName.substring(0, at);
}

/// 该删掉哪些旧备份：按名字里的时间戳倒序，保留最近 [keep] 份。
///
/// 只吃"备份文件名"（不含路径）。返回**要删的**那些。
List<String> opsBackupsToPrune(List<String> names, {int keep = kOpsBackupKeep}) {
  final backups = names.where(opsIsBackupName).toList()
    ..sort((a, b) => b.compareTo(a)); // 时间戳是定长的，字符串倒序即最新在前
  if (backups.length <= keep) return const <String>[];
  return backups.sublist(keep);
}

/// 保存前要不要多一道确认 —— 会把自己锁在门外的那些文件。
///
/// 返回一句人话（写清"改坏了的后果"），不需要确认就返回 null。
/// **不是禁止**：`/etc/nginx/*.conf` 恰恰是最常需要手改的东西；
/// 这里要的是"你知道自己在改什么"，而不是"系统替你决定"。
String? opsLockoutWarning(String path) {
  final p = path.toLowerCase();
  bool at(String s) => p == s || p.endsWith('/$s') || p.contains(s);

  if (at('/etc/ssh/sshd_config') || p.endsWith('sshd_config')) {
    return '这是 SSH 的配置：改错一行，下次就登不上这台机器（只能去云控制台救）。';
  }
  if (at('/etc/fstab')) {
    return '这是开机挂载表：改错了机器会起不来（要进救援模式才能修）。';
  }
  if (p == '/etc/passwd' || p.endsWith('/etc/passwd') ||
      p == '/etc/shadow' || p.endsWith('/etc/shadow') ||
      p == '/etc/group' || p == '/etc/sudoers' ||
      p.contains('/etc/sudoers.d/')) {
    return '这是账号/权限文件：改错会登不上、或者 sudo 用不了。';
  }
  if (p.contains('/.ssh/authorized_keys')) {
    return '这是免密登录的钥匙：清空了就再也免密登不上（要靠密码或控制台）。';
  }
  if (p.contains('htpasswd')) {
    return '这是运维通道自己的口令文件：改坏了，App 的文件页和终端页会立刻连不上。';
  }
  if (p.contains('/nginx/') || p.endsWith('.conf') && p.contains('vhost')) {
    return '这是 nginx 配置：改错会导致 nginx 起不来，App 的文件/终端页也跟着断。'
        '（保存前先在终端里跑一次 nginx -t 更稳。）';
  }
  if (p.contains('/etc/systemd/system/') && p.endsWith('.service')) {
    return '这是 systemd 单元：改错了服务起不来（改完要 daemon-reload + restart 才生效）。';
  }
  if (p.contains('/etc/netplan/') ||
      p == '/etc/network/interfaces' ||
      p.contains('/etc/sysconfig/network-scripts/') ||
      p.endsWith('/etc/resolv.conf')) {
    return '这是网络配置：改错会直接把这台机器从网上摘下去。';
  }
  if (p.startsWith('/boot/') || p.contains('grub')) {
    return '这是引导相关文件：改错机器可能起不来。';
  }
  return null;
}
