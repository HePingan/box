// file_picker 12.x API 迁移守卫。
//
// 背景：项目一度钉在 `file_picker: 12.0.0-beta.7`。那个 beta 仍保留 12.0.0 正式版
// 已经删掉的 `FilePickerResult` 包装层（`pickFiles()` 返回 `FilePickerResult?`，
// 取文件要走 `.files.first` / `.files.single`）。升到稳定版 12.2.0 后
// `pickFiles()` 直接返回 `List<PlatformFile>`，上述写法全部编译不过。
//
// 这个文件守两件事：
//   1. pubspec 不许再钉 beta（`-beta` / `-dev` / `-rc` 预发布版）；
//   2. lib/ 里不许残留 `FilePickerResult` 形态的调用（`.files.` 取值）。
//
// 为什么用源码扫描而不是执行代码：`FilePicker.pickFiles` 是静态方法且直连平台
// 通道，在 `flutter test` 里既注入不进去也调不通（会挂在 MethodChannel 上）。
// 但注意 flutter-analyzer-cleanup 的教训——源码正则只能可靠地断言「缺失」，
// 不能断言「已接线」。这里断言的正是缺失（旧形态不许出现），属于正确用法。
// 「新形态真的能编译」由 `flutter analyze` 保证，不由这个文件保证。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 收集 lib/ 下所有 dart 源码，剥掉注释行（否则本文件式的说明性注释会自我命中）。
Map<String, String> _libSources() {
  final out = <String, String>{};
  final dir = Directory('lib');
  if (!dir.existsSync()) return out;
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final code = entity
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    out[entity.path] = code;
  }
  return out;
}

void main() {
  group('file_picker 依赖约束', () {
    test('不许钉预发布版本（beta / dev / rc）', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final line = pubspec
          .split('\n')
          .firstWhere(
            (l) => l.trimLeft().startsWith('file_picker:'),
            orElse: () => '',
          );

      expect(
        line,
        isNotEmpty,
        reason: 'pubspec.yaml 里找不到 file_picker 依赖行',
      );
      expect(
        line.contains('-beta') ||
            line.contains('-dev') ||
            line.contains('-rc'),
        isFalse,
        reason:
            '不许钉 file_picker 预发布版：beta 版少了正式版之后的修复，'
            '且 12.0.0-beta.7 还带着 12.0.0 已删除的 FilePickerResult。'
            '实测行：$line',
      );
    });
  });

  group('file_picker 12.x 调用形态', () {
    test('lib/ 里不许残留 FilePickerResult 包装层写法', () {
      final offenders = <String>[];
      _libSources().forEach((path, code) {
        if (code.contains('FilePickerResult')) {
          offenders.add('$path（出现 FilePickerResult 类型）');
        }
      });

      expect(
        offenders,
        isEmpty,
        reason:
            'FilePickerResult 在 file_picker 12.0.0 已被移除。'
            'pickFiles() 现在直接返回 List<PlatformFile>，'
            '单选场景应改用 pickFile() 拿 PlatformFile?。命中：$offenders',
      );
    });

    test('FilePicker 调用点不许再用 .files 取值', () {
      final offenders = <String>[];
      // 命中形如 `picked?.files.first` / `pick.files.isEmpty` / `result?.files.single`
      final pattern = RegExp(r'\??\.files\s*\.\s*(first|single|isEmpty|isNotEmpty|length)');
      _libSources().forEach((path, code) {
        if (!code.contains('FilePicker.')) return;
        for (final m in pattern.allMatches(code)) {
          offenders.add('$path → ${m.group(0)}');
        }
      });

      expect(
        offenders,
        isEmpty,
        reason:
            '`.files` 是 FilePickerResult 的成员，12.x 已无此包装层。'
            '单选改 `final file = await FilePicker.pickFile(...)`。命中：$offenders',
      );
    });

    test('单选场景应调 pickFile 而非 pickFiles', () {
      // pickFiles 在 12.x 里 allowMultiple 默认 true，语义是多选。
      // 项目全部 9 处调用点都是单选（历史写法一律取 .first / .single），
      // 因此 lib/ 内不应再出现 pickFiles。若将来真有多选需求，
      // 在这里显式登记白名单，而不是直接删掉这条断言。
      const multiSelectAllowlist = <String>{
        // 远程存储插件：选文件后逐个入传输队列（本身就是批量上传），
        // 不是历史写法遗留，因此显式登记为多选。
        'lib/features/extensions/plugins/remote_storage/presentation/'
            'remote_storage_browser_page.dart',
      };

      final offenders = <String>[];
      _libSources().forEach((path, code) {
        if (!code.contains('FilePicker.pickFiles(')) return;
        if (multiSelectAllowlist.contains(path)) return;
        offenders.add(path);
      });

      expect(
        offenders,
        isEmpty,
        reason:
            'pickFiles() 在 12.x 默认多选且 allowMultiple 已废弃；'
            '单选请用 pickFile()。确有多选需求时把路径加进 multiSelectAllowlist。'
            '命中：$offenders',
      );
    });
  });
}
