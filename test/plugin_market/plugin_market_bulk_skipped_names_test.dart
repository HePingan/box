// P1-5 尾巴回归测试：批量安装的「已跳过 N 个」必须给出插件名或原因。
//
// 原状（plugin_market_page.dart 批量安装收尾）：
//   final skippedText = skipped > 0
//       ? '，已跳过 $skipped 个不兼容/需确认插件'
//       : '';
// 用户看到「已跳过 3 个不兼容/需确认插件」后，无法知道是哪 3 个、各自是
// 不兼容还是需要确认 —— 只能一个一个再点开看，4 个以上时基本等于要放弃。
// 而批量安装本来就是为了省掉逐点点开的操作。
//
// 预期修法：跳过时逐条留名（与既有的 failedIds/failedReasons 同一模式），
// 收尾 SnackBar 里列出（超过上限折叠为「等」）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const kBulkFile =
    'lib/features/extensions/market/presentation/plugin_market_page.dart';

/// 剥掉行注释，避免把注释里的示例文案当成实现。
String _stripContent() {
  return File(kBulkFile)
      .readAsLinesSync()
      .map((line) {
        final idx = line.indexOf('//');
        return idx >= 0 ? line.substring(0, idx) : line;
      })
      .join('\n');
}

void main() {
  group('P1-5 批量安装跳过项必须可辨识', () {
    test('批量安装循环必须记录被跳过插件的名字', () {
      final src = _stripContent();
      expect(
        src,
        matches(RegExp(r'skippedNames\.add\(\s*blockers\.isNotEmpty')),
        reason: 'P1-5：只知道跳过几个，用户无法定位是哪几个插件',
      );
    });

    test('收尾提示必须把跳过名单带出来', () {
      final src = _stripContent();
      expect(
        src,
        matches(RegExp(r'skippedNames\.take\(')),
        reason: 'P1-5：收尾 SnackBar 必须列出被跳过的插件名（可折叠）',
      );
    });
  });
}
