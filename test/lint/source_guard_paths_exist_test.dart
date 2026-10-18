// 元护栏：源码级护栏引用的文件路径必须真实存在。
//
// 为什么需要它（2026-10-18 拆分事故）：
// 本仓有 50+ 个「读源码做断言」的护栏（读文件、找字符串、判存在）。这类护栏有个
// 隐蔽的失效方式：**代码被挪到别的文件之后，护栏还盯着老路径**。
//
// 真实发生的事：本地工具面板按用途拆成 4 个 part、在线漫画页拆成 5 个 part 之后，
//   * `about_content_accuracy_test` 读 `local_tool_panels.dart` 找一句文案 ——
//     文案进了 `*_sensor.part.dart`，护栏开始**假通过**（找不到就当没写？不，是断言
//     直接失败；更糟的是反过来：断言"不该出现"的，挪走后永远找不到，就永远绿）。
//   * `dark_shell_sources_test` 的白名单点名 `comic_online_page.dart`，沉浸层代码
//     进了 `*_reader_chrome.part.dart`，白名单失效 → 两条真实告警。
//
// 两种失效都**不会**让测试报「路径不存在」——读的是老路径上的新文件（或者干脆
// 读空），看起来一切正常。所以这里加一条最朴素的检查：护栏里写死的每个
// `lib/...dart` 路径都必须在磁盘上存在。
//
// 局限（如实说）：这条只能发现"路径不存在"。发现不了"路径存在但内容搬走了"——
// 那种情况仍要靠拆分者自己更新护栏（本轮两处就是这么修的）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 从测试源码里抠出写死的 `lib/**.dart` 路径字面量。
///
/// 只认单引号或双引号包起来的完整路径；拼接出来的（`'lib/$x'`）不认——
/// 那种本来就没法静态判断，硬猜只会制造噪音。
final RegExp _literalLibPath = RegExp(r'''['"](lib/[^'"\n]+\.dart)['"]''');

void main() {
  test('护栏里写死的 lib/**.dart 路径都真实存在', () {
    final testDir = Directory('test');
    expect(testDir.existsSync(), isTrue, reason: '测试要从仓库根目录跑');

    final missing = <String>[];
    for (final entity in testDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final source = entity.readAsStringSync();
      for (final match in _literalLibPath.allMatches(source)) {
        final path = match.group(1)!;
        // 真路径存在就跳过。
        if (File(path).existsSync() || Directory(path).existsSync()) continue;

        // 负向断言：有些护栏要的正是「这个文件**不许**存在」（例如
        // 「那份重复实现已删干净」）。它们引用一个不存在的路径是**正确**的，
        // 不能报成问题。判据看该路径前后 200 字符里有没有 existsSync 的否定用法。
        final window = source.substring(
          (match.start - 200).clamp(0, source.length),
          (match.end + 200).clamp(0, source.length),
        );
        if (window.contains('isFalse') || window.contains('existsSync()')) {
          // existsSync 出现在附近且断言 isFalse → 这是"必须不存在"的检查。
          if (window.contains('isFalse') && window.contains('existsSync')) continue;
        }
        // 行号只是为了报错时好定位。
        final lineNo = '\n'.allMatches(source.substring(0, match.start)).length + 1;
        missing.add('${entity.path}:$lineNo → $path');
      }
    }

    expect(
      missing,
      isEmpty,
      reason: '这些护栏引用的文件已经不存在了（多半是代码被拆到别的文件）：\n'
          '${missing.join('\n')}\n'
          '→ 把路径改到新位置；或改成扫整个目录（见 about_content_accuracy_test '
          '的 readLibDir）。少了这一步，护栏会静默失效。',
    );
  });

  test('拆成 part 的文件，主文件确实声明了这些 part', () {
    // 反向检查：磁盘上有 `xxx.part.dart`，同一目录的主文件里必须有一行
    // `part 'xxx.part.dart';`。少一行的话那个 part 根本不会被编译，
    // 而它里面的类在别处被引用时会报"找不到"——那还算好的；更糟的是
    // 谁都没引用它，于是它静静地不参与编译，测试也发现不了。
    final libDir = Directory('lib');
    final problems = <String>[];

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.endsWith('.part.dart')) continue;

      final dirPath = entity.parent.path;
      final candidates = Directory(dirPath)
          .listSync()
          .whereType<File>()
          .where((f) {
            final n = f.uri.pathSegments.last;
            return n.endsWith('.dart') && !n.endsWith('.part.dart');
          });

      final declared = candidates.any((f) {
        final src = f.readAsStringSync();
        return src.contains("part '$name'") || src.contains('part "$name"');
      });

      if (!declared) {
        problems.add('${entity.path} 没有任何同目录主文件声明它');
      }
    }

    expect(
      problems,
      isEmpty,
      reason: '这些 part 文件没被任何主文件 part 进来（等于死代码）：\n'
          '${problems.join('\n')}',
    );
  });
}
