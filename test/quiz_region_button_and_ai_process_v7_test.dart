import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 用户 2026-09-14 第五次反馈（原话）：
///   「悬浮窗还是没有变化，放大悬浮窗并且帮框选识别范围的按钮也加回来，
///     ai回答时在答题悬浮窗下面显示作答过程」
///
/// 三条诉求逐条上锁。这次的关键教训（写进代码注释，也在这里锁住）：
///   **尺寸修复必须是无条件下限，不能是一次性 schema 迁移。**
///   v4/v5/v6 都是一次性迁移 → 跑过一次即作废、且「保存值×1.5」对本来就
///   很小的保存值无效 → 用户连续三次报「没有变化」。下面第二条测试专门
///   防止有人再把它改回一次性迁移。
void main() {
  final kt = File(
    '/root/box/android/app/src/main/kotlin/top/hpa888/box/'
    'QuizAccessibilityService.kt',
  ).readAsStringSync();
  final layout = File(
    '/root/box/android/app/src/main/res/layout/quiz_overlay.xml',
  ).readAsStringSync();
  // 尺寸决策的单一事实源（P0-1）。断语义请查这里，不要再断 Service 内联函数体。
  final policy = File(
    '/root/box/android/app/src/main/kotlin/top/hpa888/box/OverlayGeometryPolicy.kt',
  ).readAsStringSync();
  final entry = File(
    '/root/box/lib/features/quiz_plugin/presentation/quiz_plugin_entry.dart',
  ).readAsStringSync();
  final engine = File(
    '/root/box/lib/features/quiz_plugin/data/quiz_engine.dart',
  ).readAsStringSync();
  final bridge = File(
    '/root/box/lib/features/quiz_plugin/utils/ai_process_bridge.dart',
  ).readAsStringSync();
  final activity = File(
    '/root/box/android/app/src/main/kotlin/top/hpa888/box/MainActivity.kt',
  ).readAsStringSync();

  /// 取出 Kotlin 函数体（按缩进配对花括号，够用且不受注释内括号影响）。
  String funBody(String src, String signature) {
    final start = src.indexOf(signature);
    expect(start, greaterThanOrEqualTo(0), reason: '未找到 $signature');
    var i = src.indexOf('{', start);
    var depth = 0;
    final buf = StringBuffer();
    for (; i < src.length; i++) {
      final c = src[i];
      if (c == '{') depth++;
      if (c == '}') {
        depth--;
        if (depth == 0) {
          buf.write(c);
          break;
        }
      }
      buf.write(c);
    }
    return buf.toString();
  }

  group('① 悬浮窗真正放大（不再是一次性迁移）', () {
    test('loadOverlaySize 施加无条件下限，而非 schema 一次性迁移', () {
      final body = funBody(kt, 'private fun loadOverlaySize()');
      // 必须存在「无条件抬升」逻辑（对比下限后 coerceAtLeast）。
      expect(
        body.contains('floorW') && body.contains('floorH'),
        isTrue,
        reason: '缺少无条件下限 floorW/floorH —— 又会退回「一次性迁移」老路',
      );
      expect(
        RegExp(r'coerceAtLeast\(floor[WH]\)').hasMatch(body),
        isTrue,
        reason: '保存值小于下限时必须 coerceAtLeast 抬升',
      );
    });

    test('不能再依赖「schema < N 才迁移一次」的旧写法', () {
      final body = funBody(kt, 'private fun loadOverlaySize()');
      // 旧写法特征：以 schema 比较作为「是否放大」的唯一条件。
      final hasOneShotGate = RegExp(
        r'KEY_OVERLAY_SIZE_SCHEMA,\s*0\)\s*<\s*[0-9]',
      ).hasMatch(body);
      expect(
        hasOneShotGate,
        isFalse,
        reason: '检测到一次性 schema 迁移门闸：跑过一次即作废，'
            '用户会再次报「没有变化」',
      );
    });

    test('默认尺寸按 dp 计算且宽度取屏宽 80%', () {
      // 2026-09-15 修订：公式已抽到 OverlayGeometryPolicy（P0-1）。断语义不再断位置。
      // 2026-09-18 修订：宽比例 0.94 → 0.80（用户拍板缩窗、减少遮挡）。
      // ⚠️ 再调 DEFAULT_WIDTH_RATIO 时本断言须同步更新（值锁是预期行为）。
      expect(
        RegExp(r'DEFAULT_WIDTH_RATIO\s*=\s*0\.80f').hasMatch(policy),
        isTrue,
        reason: '宽度按屏宽 80% 取值（v264 起缩窗契约）',
      );
      expect(
        RegExp(r'coerceAtMost\(input\.screenW\)').hasMatch(policy),
        isTrue,
        reason: '必须夹到屏幕宽（dp 语义），避免 px/dp 混用溢出',
      );
    });

    test('默认高度下限为屏高 42%，不再被固定小上限卡死', () {
      // 2026-09-18 修订：默认高下限 0.55 → 0.42（用户拍板缩窗、减少遮挡）。
      // ⚠️ 再调 DEFAULT_MIN_HEIGHT_RATIO_OF_SCREEN 时本断言须同步更新。
      expect(
        RegExp(r'DEFAULT_MIN_HEIGHT_RATIO_OF_SCREEN\s*=\s*0\.42f')
            .hasMatch(policy),
        isTrue,
        reason: '高度按屏高 42% 起（v264 起缩窗契约）',
      );
    });
  });

  group('② 框选识别范围的按钮加回来', () {
    test('布局中 btn_region_entry 是可见的标题栏按钮（不是 1dp stub）', () {
      final i = layout.indexOf('@+id/btn_region_entry');
      expect(i, greaterThanOrEqualTo(0), reason: '布局里没有框选按钮');
      // 取该按钮声明块
      final block = layout.substring(
        layout.lastIndexOf('<ImageButton', i),
        layout.indexOf('/>', i),
      );
      // 与其它图标按钮同量级即可；30dp 是为了保证触控目标（26dp 在真机上偏差）。
      expect(
        RegExp(r'30dp').hasMatch(block),
        isTrue,
        reason: '应与其它图标按钮同量级且触控目标足够',
      );
      expect(
        block.contains('visibility="gone"'),
        isFalse,
        reason: '框选按钮不能是隐藏的',
      );
      expect(block.contains('layout_width="1dp"'), isFalse,
          reason: '1dp 是 stub 占位，不是真按钮');
    });

    test('框选按钮有专属图标，且点击进入 OCR 框选', () {
      expect(
        File('/root/box/android/app/src/main/res/drawable/'
                'ic_region_select.xml')
            .existsSync(),
        isTrue,
        reason: '缺少框选图标 drawable',
      );
      expect(
        kt.contains('R.id.btn_region_entry'),
        isTrue,
        reason: 'Kotlin 未引用框选按钮，点了没反应',
      );
      final i = kt.indexOf('R.id.btn_region_entry)?.setOnClickListener');
      expect(i, greaterThanOrEqualTo(0), reason: '框选按钮没有点击监听');
      final click = kt.substring(i, i + 320);
      expect(click.contains('enterRegionMode()'), isTrue,
          reason: '点击应进入框选模式');
    });

    test('框选按钮不参与让位（恒可见）；方案 A 后不再计入宽度预算', () {
      final body = funBody(kt, 'private fun applyTitleBarAdaptive');
      expect(
        RegExp(r'region\?\.visibility\s*=\s*View\.VISIBLE').hasMatch(body),
        isTrue,
        reason: '框选按钮必须恒可见，否则用户又找不到',
      );
      // 方案 A（用户 2026-09-15 拍板）：按钮区改为横向可滑动后，
      // 不再存在「宽度预算」概念 —— 放不下就滑动取用，而不是靠隐藏别的按钮腾位。
      // 故 regionPx 预算核算已被撤销；改为断言滑动容器承接溢出。
      expect(
        body.contains('regionPx'),
        isFalse,
        reason: '方案 A 已取消宽度预算裁剪，不应再有 regionPx 让位核算',
      );
      expect(
        kt.contains('R.id.title_actions_scroll') ||
            kt.contains('TITLE_ACTIONS_SCROLL_ENABLED'),
        isTrue,
        reason: '方案 A 须有滑动容器/开关，承接按钮溢出',
      );
    });
  });

  group('③ 答题悬浮窗下方显示 AI 作答过程', () {
    test('布局含 ai_process_box 且位于答案 ScrollView 之后（下方）', () {
      final boxIdx = layout.indexOf('@+id/ai_process_box');
      final ansIdx = layout.indexOf('@+id/scroll_answer');
      expect(boxIdx, greaterThanOrEqualTo(0), reason: '布局缺 AI 过程区块');
      final ansScroll = ansIdx >= 0
          ? ansIdx
          : layout.indexOf('android:id="@+id/tv_answer"');
      expect(ansScroll, greaterThanOrEqualTo(0));
      expect(
        boxIdx,
        greaterThan(ansScroll),
        reason: 'AI 过程必须排在答案之后，才是「在下面显示」',
      );
    });

    test('过程文本容器与折叠开关齐备', () {
      for (final id in [
        '@+id/tv_ai_process',
        '@+id/tv_ai_process_toggle',
        '@+id/ai_process_header',
        '@+id/scroll_ai_process',
      ]) {
        expect(layout.contains(id), isTrue, reason: '布局缺 $id');
      }
    });

    test('原生侧提供 updateAiProcess 且经桥暴露给 Flutter', () {
      expect(kt.contains('fun updateAiProcess('), isTrue);
      expect(
        kt.contains('fun updateAiProcessIfRunning('),
        isTrue,
        reason: '需要 companion 静态入口供 Flutter 调用',
      );
      expect(
        activity.contains('"updateAiProcess" ->'),
        isTrue,
        reason: 'MethodChannel 未分发 updateAiProcess',
      );
      expect(activity.contains('updateAiProcessIfRunning(text)'), isTrue);
    });

    test('过程文本只推阶段事实，不推模型思维链原文', () {
      expect(engine.contains('AiProcessBridge.push'), isTrue,
          reason: 'quiz_engine 未推送作答过程');
      expect(
        engine.contains('① 读屏截图'),
        isTrue,
        reason: '缺阶段化过程文本（应展示可核对的阶段）',
      );
      // 防回归：不得把上游 reasoning 原样塞进过程区（英文思维链会误导用户）。
      expect(
        RegExp(r'proc\.add\([^)]*reasoning').hasMatch(engine),
        isFalse,
        reason: '过程区不应直接展示 reasoning 原文',
      );
    });

    test('新题开始检索先清空上一题的过程（防串题）', () {
      final body = funBody(entry, 'static Future<void> _showNewQuestionSearching');
      expect(
        body.contains('AiProcessBridge.clear()'),
        isTrue,
        reason: '换题必须清过程，否则用户看到的是上一题的过程',
      );
    });

    test('推送桥用真实 MethodChannel 名，且失败静默', () {
      expect(
        bridge.contains("'top.hpa888.box/quiz_plugin'"),
        isTrue,
        reason: '频道名必须与原生 CHANNEL 完全一致，否则推送全丢',
      );
      expect(
        bridge.contains('catch'),
        isTrue,
        reason: '推送失败必须静默，不能影响出答案',
      );
      expect(activity.contains('top.hpa888.box/quiz_plugin'), isTrue);
    });

    test('失败时也把原因推给用户看（便于自助排查）', () {
      expect(
        engine.contains("proc.add('✖ 失败："),
        isTrue,
        reason: '失败原因应展示在过程区，用户不必去翻调试日志',
      );
    });
  });
}
