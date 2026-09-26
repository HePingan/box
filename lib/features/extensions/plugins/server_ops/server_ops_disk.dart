// 磁盘卡片背后的纯逻辑：把 du 报的「1.2G」换算回字节、按大小倒排、算占比、
// 以及「上一级」是谁。单独放一层是为了能对着断言测 —— 这类换算写在 UI 里最容易错。
//
// 服务端给的是 `du -h` 的**人类可读**串（1.2G / 512M / 4.0K）。排序时一定要先换算
// 成字节：按字符串排会把 "9.0M" 排在 "10G" 前面（'9' > '1'），一眼看不出错。

import 'server_ops_api_client.dart';

/// 认这些后缀（du -h 用的就是这几种；K/M/G/T/P 与 KiB 写法都吃）。
const _units = <String, int>{
  'B': 1,
  'K': 1024,
  'M': 1024 * 1024,
  'G': 1024 * 1024 * 1024,
  'T': 1024 * 1024 * 1024 * 1024,
  'P': 1024 * 1024 * 1024 * 1024 * 1024,
};

/// 「1.2G」/「512M」/「4.0K」/「123」→ 字节数。认不出来返回 0（当最小值，不丢行）。
///
/// 认不出来就返回 0 而不是抛异常：这是"看盘用"的界面，一行脏数据不该让整张卡片打不开。
int opsParseHumanSize(String raw) {
  final s = raw.trim().toUpperCase().replaceAll('IB', '').replaceAll(' ', '');
  if (s.isEmpty) return 0;
  final unit = s[s.length - 1];
  final mult = _units[unit];
  final numPart = mult == null ? s : s.substring(0, s.length - 1);
  final value = double.tryParse(numPart);
  if (value == null || value.isNaN || value < 0) return 0;
  return (value * (mult ?? 1)).round();
}

/// 按占用从大到小排（服务端是按路径字母序给的，直接用会把大目录埋在中间）。
List<OpsDiskRow> opsSortDiskRowsBySize(List<OpsDiskRow> rows) {
  final copy = List<OpsDiskRow>.of(rows);
  copy.sort((a, b) {
    final byBytes = opsParseHumanSize(b.size).compareTo(opsParseHumanSize(a.size));
    return byBytes != 0 ? byBytes : a.path.compareTo(b.path);
  });
  return copy;
}

/// 这一行占它自己总量的比例（0..1），用来画长度条。
///
/// 分母是"子项里最大的那个"而不是它们的和：du 的输出里子项之和常大于父项本身
/// （硬链接、子目录还会各算一次），拿和当分母会画出一堆不满的条，看不出谁大谁小。
double opsDiskBarShare(int bytes, List<OpsDiskRow> rows) {
  var maxBytes = 0;
  for (final r in rows) {
    final b = opsParseHumanSize(r.size);
    if (b > maxBytes) maxBytes = b;
  }
  if (maxBytes <= 0) return 0;
  return (bytes / maxBytes).clamp(0.0, 1.0);
}

/// 上一级目录；已经在根上时返回 null（界面据此禁用按钮）。
String? opsParentPath(String path) {
  final p = path.trim();
  if (p.isEmpty || p == '/') return null;
  final trimmed = p.endsWith('/') ? p.substring(0, p.length - 1) : p;
  if (trimmed.isEmpty || trimmed == '/') return null;
  final idx = trimmed.lastIndexOf('/');
  if (idx <= 0) return '/';
  return trimmed.substring(0, idx);
}

/// 清理项（服务端只认这几个）。
class OpsCleanupMode {
  const OpsCleanupMode(this.key, this.label, this.hint);

  final String key;
  final String label;
  final String hint;
}

const kOpsCleanupModes = <OpsCleanupMode>[
  OpsCleanupMode('journal', '系统日志', '清到只剩 200MB（保留最近的）'),
  OpsCleanupMode('tmp', '临时文件', '只删 /tmp 里 7 天没动过的普通文件'),
  OpsCleanupMode('apt', '软件包缓存', 'apt 下载过的安装包缓存'),
];

/// 清理结果怎么说人话（服务端回的是字节数）。
String opsCleanupResultText(String what, int freedBytes) {
  final label = kOpsCleanupModes
      .firstWhere((m) => m.key == what, orElse: () => kOpsCleanupModes.first)
      .label;
  if (freedBytes <= 0) return '「$label」没什么可清的（本来就很干净）';
  return '「$label」清出 ${opsFormatBytes(freedBytes)}';
}

/// 字节数说人话（1 位小数）。
String opsFormatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[i]}';
}
