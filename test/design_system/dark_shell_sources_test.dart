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
/// 3. 写死的板岩色文字（`0xFF5B6B8C` / `0xFF64748B`）→ 判红，应改用
///    `AppTokens.textSecondary`。
///
/// 例外文件（`allowFiles`）是**内容层**：视频/音频播放器与彩色圆底图标，
/// 那里的白色是"深色媒体底上的前景色"，深浅档都该是白的。
void main() {
  const List<String> trees = <String>[
    'design_system/',
    'features/home/',
    'features/tools/',
    'features/content/',
    'features/extensions/',
    'features/local_tools/',
    'features/api_hub/',
  ];
  const List<String> looseFiles = <String>[
    'lib/app/app_shell.dart',
    'lib/app_drawer.dart',
  ];

  /// 白色本来就是对的前景（深色媒体底 / 彩色底上的文字与图标）。
  const Set<String> allowFiles = <String>{
    'lib/design_system/app_tokens.dart',
    'lib/design_system/widgets/empty_error_states.dart',
    'lib/features/api_hub/application/public_api_registry.dart',
    'lib/features/extensions/market/domain/plugin_market_manifest.dart',
    'lib/features/extensions/plugins/remote_storage/presentation/'
        'remote_storage_player_page.dart',
  };

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
    for (final String tree in trees) {
      final Directory dir = Directory('lib/$tree');
      if (!dir.existsSync()) continue;
      for (final FileSystemEntity e in dir.listSync(recursive: true)) {
        if (e is File && e.path.endsWith('.dart')) out.add(e.path);
      }
    }
    out.addAll(looseFiles);
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
        if (!RegExp(r'color:|fillColor|backgroundColor').hasMatch(line)) {
          continue;
        }
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

  test('外壳页面里没有"写死的板岩色文字"（深色档下会消失）', () {
    final List<String> bad = <String>[];
    for (final String path in shellSources()) {
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
