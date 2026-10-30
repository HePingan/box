/// 市场卡片上的「下载量 / 更新时间 / 包体积」这一行（纯函数，便于单测）。
///
/// 为什么要它：market 的排序支持「按下载量」「按更新时间」，但卡片上这两个数
/// 一个都不显示 —— 排完序用户看不出依据，等于排序不可验证。这里把排序依据
/// 直接写出来，顺带让「这个插件有多大」在安装前可见。
///
/// 显示口径刻意保守：**没有数据就不显示**（0 次下载不写「0 次下载」，
/// 解析不出的时间不编造），宁可少一行，也不给用户假信息。
library;

String _two(int v) => v.toString().padLeft(2, '0');

/// 拼出卡片上那一行；三个字段全空时返回空串（调用方据此不渲染）。
String marketPluginStatsLine({
  required int downloadCount,
  required String publishedAt,
  required int packageSize,
  DateTime? now,
}) {
  final parts = <String>[];
  if (downloadCount > 0) parts.add('↓ $downloadCount 次下载');
  final stamp = marketUpdatedStamp(publishedAt, now: now);
  if (stamp.isNotEmpty) parts.add(stamp);
  final size = formatPackageSize(packageSize);
  if (size.isNotEmpty) parts.add(size);
  return parts.join(' · ');
}

/// 更新时间的相对描述：越近越具体，跨年才写全日期。
///
/// 解析失败或为空返回空串 —— 上游给什么就显示什么，绝不猜一个日期出来。
String marketUpdatedStamp(String publishedAt, {DateTime? now}) {
  final raw = publishedAt.trim();
  if (raw.isEmpty) return '';
  final at = DateTime.tryParse(raw);
  if (at == null) return '';
  final current = now ?? DateTime.now();
  final diff = current.difference(at);
  if (diff.isNegative) return '刚更新'; // 手机时钟比服务器快，别显示「-1 天前」
  if (diff.inMinutes < 60) return '刚更新';
  if (diff.inHours < 24 && current.day == at.day) return '今天更新';
  if (diff.inDays < 2) return '昨天更新';
  if (diff.inDays < 7) return '${diff.inDays} 天前更新';
  if (at.year == current.year) return '${_two(at.month)}-${_two(at.day)} 更新';
  return '${at.year}-${_two(at.month)}-${_two(at.day)} 更新';
}

/// 包体积文案（插件包上限 5 MB，只到 MB 就够）。
String formatPackageSize(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
}
