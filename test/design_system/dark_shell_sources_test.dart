import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 护栏：**外壳页面里不许再出现"写死的浅色底 / 写死的板岩色文字"**。
///
/// 为什么单独立一条：`AppTokens` 的表面色改成随亮度解析（深色批次 1）之后，
/// 任何"写死的白色面板"都会在深色档下变成刺眼的白块，更糟的是——如果那块的
/// 文字用的是 tokens（深色档下变浅），就会出现**浅字压白底 = 看不见**。
/// 这一条把整类问题钉死，不用每次靠截图去发现。
///
/// 规则：
/// 1. 裸的 `color: Colors.white,` / `backgroundColor:` / `fillColor:` 若处在
///    `BoxDecoration/Container/Material/Card/Scaffold` 上下文里 → 判红
///    （带 alpha 的 `Colors.white.withValues(...)` 是"彩色底上的高光/覆层"，放行）。
/// 2. 写死的近白色 `Color(0xFF……)`（R、G、B 三个通道都 ≥ 0xE0）出现在
///    颜色位置 → 判红（品牌色如 `0xFFEC4899` G 通道很低，不会误伤）。
/// 3. 写死的板岩色文字（`0xFF5B6B8C` / `0xFF64748B` / `0xFF94A3B8`）→ 判红，
///    应改用 `AppTokens.textSecondary` / `textTertiary`。
/// 4. 低阶灰 `Colors.grey.shade50/100/200` → 判红（浅色档的灰抄成字面量，
///    深色档下依旧是浅灰块）。
/// 5. 黑色系文字 `Colors.black87/54/45/38/26` → 判红（深色档下看不清）。
///
/// 例外文件（`allowFiles`）是**内容层**：视频/音频播放器与彩色圆底图标，
/// 那里的白色是"深色媒体底上的前景色"，深浅档都该是白的。
void main() {
  // 不再逐个目录列举 —— 直接扫整棵 lib/。
  // 为什么改：批次 1/2 各漏过一次目录（update/account/admin 漏过，app/ about/
  // cloud_sync/ quiz_plugin/ 又漏过），每次都是真机截图才发现。判据改成
  // "整棵树 + 具名例外"后，新写的页面自动在管。
  const String libRoot = 'lib';
  /// 白色本来就是对的前景（深色媒体底 / 彩色底上的文字与图标）。
  const Set<String> allowFiles = <String>{
    'lib/design_system/app_tokens.dart',
    'lib/design_system/widgets/empty_error_states.dart',
    'lib/features/api_hub/application/public_api_registry.dart',
    'lib/features/extensions/market/domain/plugin_market_manifest.dart',
    'lib/features/extensions/plugins/remote_storage/presentation/'
        'remote_storage_player_page.dart',
    // 更新弹窗顶部那条蓝色信息带：它自己就是彩色底，圆环描边与图标必然是白的
    // （正文/按钮/提示底都已改用 tokens）。
    'lib/update/update_dialog.dart',
    // 关于页头部那个 64×64 的圆角方块：底色是 AppTokens.blueGradient（彩色渐变），
    // 里面的图标必然是白的（该文件只有这一处白色）。
    'lib/features/about/presentation/about_page.dart',
    // ── 内容层里"自带深底"的部分（深浅档都该是深色，白色是深底上的前景）──
    // 播放器控制层与浮层：压在视频画面上，底色必须深。
    'lib/video/widgets/player/custom_video_controls.dart',
    'lib/video/widgets/player/player_overlays.dart',
    // 漫画阅读器（含在线条漫页）：沉浸式黑底 + 白色控件，与外壳深浅无关。
    'lib/features/comic/presentation/comic_reader_page.dart',
    'lib/features/comic/presentation/comic_online_page.dart',
    // 小说阅读器的目录/设置弹层：跟随阅读器自己的 warm/paper/dark 三档。
    'lib/novel/pages/reader/reader_directory_sheet.dart',
    'lib/novel/pages/reader/reader_settings_sheet.dart',
  };

  /// 只对"板岩色文字"那条规则例外：题库管理页的状态色板里 `#94A3B8`
  /// 是"草稿/未知"的语义色（chip 淡底 + 同色描边），深浅档通用；
  /// 这个文件其余部分该收口的照样要收口 —— 所以**不能**整文件放进 allowFiles。
  const Set<String> slateAllowExtra = <String>{
    'lib/features/admin/presentation/widgets/quiz_bank_tab_widgets.part.dart',
  };

  /// 低阶灰（`Colors.grey.shade50/100/200` 之类）：深色档下仍是浅灰，会成白块。
  final RegExp lowShadeGrey = RegExp(
    r'Colors\.(grey|blueGrey|blue|indigo|teal|cyan)\.shade(50|100|200)\b',
  );

  /// 黑色系文字：浅色档的"黑字"抄成字面量，深色档下看不清。
  final RegExp blackText = RegExp(r'Colors\.black(87|54|45|38|26)\b');

  const String panelContext =
      r'BoxDecoration|decoration:|Container\(|Material\(|Card\(|Scaffold\(';
  final RegExp whiteFill = RegExp(
    r'color:\s*Colors\.white,|backgroundColor:\s*Colors\.white,|'
    r'fillColor:\s*(const\s+)?Colors\.white,',
  );
  final RegExp slateText =
      RegExp(r'Color\(0xFF(5B6B8C|64748B|94A3B8|475569|334155)\)');
  final RegExp hexColor = RegExp(r'Color\(0xFF([0-9A-Fa-f]{6})\)');

  bool isNearWhite(String hex6) {
    final int r = int.parse(hex6.substring(0, 2), radix: 16);
    final int g = int.parse(hex6.substring(2, 4), radix: 16);
    final int b = int.parse(hex6.substring(4, 6), radix: 16);
    return r >= 0xE0 && g >= 0xE0 && b >= 0xE0;
  }

  List<String> shellSources() {
    final List<String> out = <String>[];
    for (final FileSystemEntity e in Directory(libRoot).listSync(recursive: true)) {
      if (e is File && e.path.endsWith('.dart')) out.add(e.path);
    }
    return out;
  }

  test('外壳页面里没有"写死的白色面板底"（深色档下会变白块）', () {
    final List<String> bad = <String>[];
    for (final String path in shellSources()) {
      if (allowFiles.contains(path)) continue;
      final List<String> lines = File(path).readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        if (!whiteFill.hasMatch(lines[i])) continue;
        final String ctx = lines
            .sublist(i - 6 < 0 ? 0 : i - 6, i + 1)
            .join('\n');
        if (RegExp(panelContext).hasMatch(ctx)) {
          bad.add('$path:${i + 1} ${lines[i].trim()}');
        }
      }
    }
    expect(
      bad,
      isEmpty,
      reason: '这些地方用写死的白色当面板底，深色档下会变成白块：\n${bad.join('\n')}\n'
          '→ 改成 AppTokens.surface / surfaceMuted，边框改用 AppTokens.cardBorder；'
          '确实是"彩色底上的前景白"的，把该行加进白名单并写明理由。',
    );
  });

  test('外壳页面里没有"写死的近白色"（浅灰底 / 浅灰描边）', () {
    final List<String> bad = <String>[];
    for (final String path in shellSources()) {
      if (allowFiles.contains(path)) continue;
      final List<String> lines = File(path).readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i];
        final String trimmed = line.trimLeft();
        // 注释行跳过（说明文字里提到色值不算）。
        if (trimmed.startsWith('//')) continue;
        for (final RegExpMatch m in hexColor.allMatches(line)) {
          if (isNearWhite(m.group(1)!)) {
            bad.add('$path:${i + 1} ${line.trim()}');
          }
        }
      }
    }
    expect(
      bad,
      isEmpty,
      reason: '这些地方写死了近白色（≥0xE0 三通道全是高值），深色档下会发亮：\n'
          '${bad.join('\n')}\n→ 浅灰底用 AppTokens.surfaceMuted，'
          '描边/割线用 AppTokens.cardBorder / AppTokens.divider。',
    );
  });

  test('外壳页面里没有"黑色系文字"（Colors.black87/54/45/38/26，深色档下看不清）', () {
    final List<String> bad = <String>[];
    for (final String path in shellSources()) {
      if (allowFiles.contains(path)) continue;
      final List<String> lines = File(path).readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        if (blackText.hasMatch(lines[i])) {
          bad.add('$path:${i + 1} ${lines[i].trim()}');
        }
      }
    }
    expect(
      bad,
      isEmpty,
      reason: '把"浅色档的黑字"抄成了字面量，深色档下就是深字压深底：\n'
          '${bad.join('\n')}\n→ 正文用 AppTokens.textPrimary / textSecondary，'
          '次要信息用 textTertiary。（本规则只管 black87/54/45/38/26；'
          '纯 Colors.black 的遮罩 / 阴影 / 播放器黑底是合法的。）',
    );
  });

  test('外壳页面里没有"低阶灰"（Colors.grey.shade50/100/200，深色档下仍是浅灰）', () {
    final List<String> bad = <String>[];
    for (final String path in shellSources()) {
      if (allowFiles.contains(path)) continue;
      final List<String> lines = File(path).readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        if (lowShadeGrey.hasMatch(lines[i])) {
          bad.add('$path:${i + 1} ${lines[i].trim()}');
        }
      }
    }
    expect(
      bad,
      isEmpty,
      reason: '低阶灰是把"浅色档的灰"抄成了字面量，深色档下依然是浅灰块：\n'
          '${bad.join('\n')}\n→ 底色用 AppTokens.surface / surfaceMuted，'
          '文字用 textSecondary / textTertiary，描边用 cardBorder。',
    );
  });

  test('外壳页面里没有"写死的板岩色文字"（深色档下会消失）', () {
    final List<String> bad = <String>[];
    for (final String path in shellSources()) {
      if (allowFiles.contains(path) || slateAllowExtra.contains(path)) {
        continue;
      }
      final List<String> lines = File(path).readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        if (slateText.hasMatch(lines[i])) {
          bad.add('$path:${i + 1} ${lines[i].trim()}');
        }
      }
    }
    expect(
      bad,
      isEmpty,
      reason: '板岩色文字写死之后，深色档下就是"深字压深底"：\n${bad.join('\n')}\n'
          '→ 改用 AppTokens.textSecondary / textTertiary。',
    );
  });
}
