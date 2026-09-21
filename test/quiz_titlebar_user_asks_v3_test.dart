import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 用户 2026-09-13 第三次反馈（真机截图：紫底 AI 胶囊 + 眼睛 + ✕，相似度胶囊不见了）：
///
///   「那个叉没有必要，保留ai按钮，眼睛按钮和录入题目按钮就行，
///     ai按钮大了，导致旁边的相似度没有显示出来，重新调整，
///     然后ai搜索时没有看到提示与进度，进行优化」
///
/// 拆成 4 条可验证契约：
///   A. 标题栏不得再有可点的关闭(✕)按钮。
///   B. 标题栏必须直接保留三键：AI 联网搜题 / 眼睛(隐藏) / 录入题目。
///      「录入题目」= btn_quiz_entry，原为 1dp GONE 占位、真入口藏在 ⋯ 菜单，
///      用户要求它**直接可见**。
///   C. AI 按钮必须收窄（用户说「AI 按钮大了」，把相似度胶囊挤没了）。
///   D. AI 搜索必须有可见反馈：进度条 + 阶段文案 + 按钮本身状态变化。
void main() {
  final xml = File(
    '/root/box/android/app/src/main/res/layout/quiz_overlay.xml',
  ).readAsLinesSync().join('\n');
  final kt = File(
    '/root/box/android/app/src/main/kotlin/top/hpa888/box/QuizAccessibilityService.kt',
  ).readAsLinesSync().join('\n');

  /// 抽出一个控件的 XML 片段（id 声明所在元素的起止）。
  String widgetBlock(String id) {
    final i = xml.indexOf('android:id="@+id/$id"');
    if (i < 0) return '';
    final start = xml.lastIndexOf('<', i);
    final selfClose = xml.indexOf('/>', i);
    final closeTag = xml.indexOf('</', i);
    final end = (closeTag >= 0 && (selfClose < 0 || closeTag < selfClose))
        ? xml.indexOf('>', closeTag) + 1
        : selfClose + 2;
    return xml.substring(start, end);
  }

  group('防假绿：源文件必须真实读到', () {
    test('XML 与 Kotlin 都读全了', () {
      expect(xml.length, greaterThan(3000));
      expect(kt.length, greaterThan(10000),
          reason: 'Kotlin 源必须真实读入，否则断言全部假绿');
    });
  });

  group('A. 关闭(✕)按钮必须移除', () {
    test('布局里不得再有可点的 btn_close', () {
      final block = widgetBlock('btn_close');
      if (block.isNotEmpty) {
        expect(
          block.replaceAll(RegExp(r'\s+'), ' '),
          contains('android:visibility="gone"'),
          reason: '✕ 已无必要（用户明确要求删除），不得留在标题栏里可点',
        );
      }
    });

    test('考试态 applyExamChrome 不得让 ✕ 复活', () {
      // 曾经的坑：applyExamChrome 里显式 `btn_close ... VISIBLE` 会把
      // 已从布局移除的 ✕ 重新拉出来，破坏「标题栏只留三键」。
      final m = RegExp(r'private fun applyExamChrome\(view: View\)\s*\{')
          .firstMatch(kt);
      expect(m, isNotNull, reason: '应能定位 applyExamChrome');
      final body = kt.substring(m!.end, (m.end + 2400).clamp(0, kt.length));
      expect(
        RegExp(r'R\.id\.btn_close[\s\S]{0,60}?visibility = View\.VISIBLE')
            .hasMatch(body),
        isFalse,
        reason: '考试态不得把关闭按钮置为可见',
      );
      expect(
        RegExp(r'R\.id\.btn_quiz_entry[\s\S]{0,60}?visibility = View\.GONE')
            .hasMatch(body),
        isFalse,
        reason: '考试态也不得隐藏录入题目按钮（用户要求常驻）',
      );
    });

    test('Kotlin 不得再把 btn_close 置 VISIBLE 保位', () {
      expect(
        kt,
        isNot(contains('close?.visibility = View.VISIBLE')),
        reason: '自适应里的「close 永不隐藏」与用户诉求相反，必须删掉',
      );
    });
  });

  group('B. 标题栏必须直接保留 AI / 眼睛 / 录入题目 三键', () {
    test('录入题目 btn_quiz_entry 必须直接可见', () {
      final block = widgetBlock('btn_quiz_entry');
      expect(block, isNotEmpty, reason: '必须先有 btn_quiz_entry 这个控件');
      final flat = block.replaceAll(RegExp(r'\s+'), ' ');
      expect(flat, isNot(contains('android:visibility="gone"')),
          reason: '用户要求「录入题目按钮」直接可见，不能再藏进 ⋯ 菜单');
      expect(flat, isNot(contains('android:layout_width="1dp"')),
          reason: '1dp 是不可点占位，必须给真实尺寸');
    });

    test('眼睛不得再被宽度自适应砍掉', () {
      expect(
        kt,
        isNot(
            contains('eye?.visibility = if (showEye) View.VISIBLE else View.GONE')),
        reason: '眼睛与录入现在是常驻键',
      );
    });

    test('AI 仍恒可见', () {
      expect(kt, contains('R.id.btn_ai_vision)?.visibility = View.VISIBLE'));
    });
  });

  group('C. AI 按钮必须收窄（不再挤掉相似度胶囊）', () {
    test('Kotlin 预算里 AI 宽度常量必须收紧到 < 56dp', () {
      final m = RegExp(r'val aiPx = ([0-9 +*()]+) \* d').firstMatch(kt);
      expect(m, isNotNull, reason: '应保留 aiPx 宽度常量');
      // 允许写成算式（如 (26 + 4)），求值后必须明显小于原来的 56dp。
      final expr = m![1]!;
      final value = RegExp(r'^\s*(\d+)\s*$').firstMatch(expr) != null
          ? int.parse(expr.trim())
          : expr
              .split('+')
              .map((t) => int.parse(t.replaceAll(RegExp(r'[^0-9]'), '')))
              .fold<int>(0, (a, b) => a + b);
      expect(value, lessThan(56),
          reason: '原 56dp 过宽（含 sparkle 图标），新值 $value dp 必须明显收窄');
    });

    test('AI 按钮布局宽度不得再超过 40dp', () {
      final block = widgetBlock('btn_ai_vision');
      expect(block, isNotEmpty);
      final widths =
          RegExp(r'android:layout_width="(\d+)dp"').allMatches(block).toList();
      if (widths.isNotEmpty) {
        expect(int.parse(widths.first[1]!), lessThanOrEqualTo(40));
      }
    });
  });

  group('D. AI 搜索必须有可见提示与进度', () {
    test('进度必须落在**独立横幅**上，不能写进会被收起的相似度胶囊', () {
      expect(xml, contains('@+id/vision_progress_box'),
          reason: '要有独立的进度横幅容器');
      expect(xml, contains('@+id/tv_vision_progress'),
          reason: '横幅要有自己的文案 TextView（不借用相似度胶囊）');
      expect(xml, contains('@+id/vision_progress'),
          reason: '横幅要有进度条');
      // ticker 不得再往 tv_similarity_badge 写倒计时
      final m = RegExp(r'private fun startVisionTicker\(root: View\)\s*\{')
          .firstMatch(kt);
      expect(m, isNotNull);
      final body = kt.substring(m!.end, (m.end + 1600).clamp(0, kt.length));
      expect(body, isNot(contains('tv_similarity_badge')),
          reason: '窄窗下胶囊会被收起，倒计时写进去用户看不到');
      expect(body, contains('vision_progress_box'),
          reason: 'ticker 必须显式显示进度横幅');
    });

    test('进度条 vision_progress 仍在且被 ticker 显示', () {
      expect(xml, contains('@+id/vision_progress'));
      expect(kt, contains('startVisionTicker'));
      // 真实写法是两行：val bar = ...findViewById(R.id.vision_progress) / bar?.visibility = VISIBLE
      expect(
        RegExp(r'vision_progress[\s\S]{0,120}?visibility = View\.VISIBLE').hasMatch(kt) ||
            RegExp(r'visibility = View\.VISIBLE[\s\S]{0,120}?vision_progress').hasMatch(kt),
        isTrue,
        reason: 'ticker 必须把进度条置为可见',
      );
    });

    test('点击 AI 后按钮本身必须有可见进行中状态', () {
      expect(
        kt,
        anyOf(contains('AI…'), contains('识别中')),
        reason: '仅 alpha 0.45 用户感知不到，按钮需显示进行中文案',
      );
    });

    test('阶段文案必须存在（与 Dart 侧同口径）', () {
      expect(kt, contains('正在识别题目'));
      expect(kt, contains('正在请求大模型'));
    });
  });
}
