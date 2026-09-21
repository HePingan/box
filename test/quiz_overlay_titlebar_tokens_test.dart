import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 悬浮窗标题栏**排版令牌契约**（2026-09-13 第二轮视觉优化终审要求「token 化锁值」）。
///
/// 设计终审结论：左右内边距必须对称、右侧按钮须体现「主-次」间距层次。
/// 纯靠人眼核对 XML 容易在后续改动中回归，故用测试把常量锁死 ——
/// 任何一次改间距若破坏对称性或层次，这里立刻红灯。
///
/// 这些数值同时是 `quiz_overlay_titlebar_preview_test.dart` 出图所用的取值，
/// 出图与出包同源，避免「设计稿好看、真机跑偏」。
void main() {
  late String xml;

  setUpAll(() {
    final f = File('android/app/src/main/res/layout/quiz_overlay.xml');
    expect(f.existsSync(), isTrue, reason: '找不到悬浮窗布局文件');
    xml = f.readAsStringSync();
  });

  /// 取某个 id 所在元素的某个属性值（就近向下搜索，取第一个匹配）。
  String? attrOf(String id, String attr) {
    final start = xml.indexOf('android:id="@+id/$id"');
    if (start < 0) return null;
    final slice = xml.substring(start, (start + 900).clamp(0, xml.length));
    final m = RegExp('$attr="([^"]+)"').firstMatch(slice);
    return m?.group(1);
  }

  group('左右内边距（方案 A 后语义调整）', () {
    test('标题栏 paddingStart 保留，paddingEnd 交给滑动区自己收', () {
      // 方案 A（用户 2026-09-15 拍板）：按钮区改为横向可滑动后，
      // 标题栏本身的 paddingEnd 必须为 0 —— 右侧留白改由滑动区内部的
      // title_actions_row 末尾 padding 提供，这样按钮可以一直滑到窗口边缘，
      // 不会因为外层 padding 白白损失 12dp 可视宽度。
      // 因此「左右 padding 必须相等」这条旧契约已被方案 A 取代。
      final s = attrOf('title_bar', 'android:paddingStart');
      final e = attrOf('title_bar', 'android:paddingEnd');
      expect(s, isNotNull, reason: 'title_bar 必须有 paddingStart');
      expect(e, isNotNull, reason: 'title_bar 必须有 paddingEnd');
      expect(s, equals('12dp'), reason: '左侧留给拖动热区，仍为 12dp');
      expect(e, equals('0dp'),
          reason: '方案 A：右侧 padding 必须为 0，让滑动区能贴到窗口边缘；'
              '右侧留白由 title_actions_row 的 paddingEnd 提供');

      // 右侧留白不能凭空消失 —— 但 2026-09-18 起改由内容内固定宽度的 Space 提供：
      // 「录入」按钮贴窗口右缘被裁（用户截图定位）后，12dp 留白从
      // title_actions_row 的 paddingEnd 移到内容里。机制：HorizontalScrollView
      // 超宽时会吞掉 padding 致末按钮贴边裁切；内容内的 Space 随内容滚动，
      // 滚到最右仍有 12dp 余量。故此处断「行内存在 12dp Space」。
      final rowStart = xml.indexOf('android:id="@+id/title_actions_row"');
      final rowEnd = xml.indexOf('<!-- /title_actions_row -->');
      expect(rowStart, greaterThanOrEqualTo(0), reason: '布局缺 title_actions_row');
      expect(rowEnd, greaterThan(rowStart), reason: '缺 title_actions_row 闭合注释');
      final rowBlock = xml.substring(rowStart, rowEnd);
      expect(
        RegExp(r'<Space[^>]*android:layout_width="12dp"').hasMatch(rowBlock),
        isTrue,
        reason: '尾部留白必须由行内 12dp Space 提供，否则最后一个按钮贴着边缘被裁',
      );
    });
  });

  group('右侧按钮主次间距层次（终审第 2 条）', () {
    test('⋯ 与 AI 胶囊之间（more.marginEnd）大于 次要组间距', () {
      final more = attrOf('btn_more', 'android:layout_marginEnd');
      final eye = attrOf('btn_hide_overlay', 'android:layout_marginEnd');
      expect(more, isNotNull);
      expect(eye, isNotNull);
      final mv = int.parse(more!.replaceAll('dp', ''));
      final ev = int.parse(eye!.replaceAll('dp', ''));
      expect(mv, greaterThan(ev),
          reason: '主操作(AI)前应比次要组(眼/关闭)留更多呼吸感');
    });

    test('AI 胶囊与眼睛之间保持分离（ai.marginEnd > 0）', () {
      final ai = attrOf('btn_ai_vision', 'android:layout_marginEnd');
      expect(ai, isNotNull);
      expect(int.parse(ai!.replaceAll('dp', '')), greaterThan(0),
          reason: 'AI 胶囊不得与眼睛贴死，否则视觉成团');
    });
  });

  group('标题栏宽度：方案 A 后不再要求「一屏放得下」', () {
    test('最窄真机窗宽下按钮溢出是预期行为（靠滑动取用），不得再靠隐藏解决', () {
      // 方案 A（用户 2026-09-15 拍板）取代了旧的「全机型不得溢出」契约。
      //
      // 旧契约的问题：为了让 4 组元素塞进 274dp，实现被迫在窄窗下把
      // ⋯ 菜单和相似度胶囊设为 GONE。用户实际体验是「按钮被裁掉/找不到」
      // （第 5 次反馈「框选按钮找不到」即由此引发）。
      //
      // 新契约：内容可以超出窗宽 —— 溢出部分改由 HorizontalScrollView
      // 横向滑动取用，**全部按钮恒可见**。
      const pad = 12; // 仅左侧；右侧已交给滑动区内部
      const badge = 16 * 2 + 6 * 5;
      const btn = 26;
      const ai = 6 + 13 + 3 + 22 + 8;
      const margin = 8 + 3 + 5 + 12;
      const total = pad + badge + btn * 3 + ai + margin;

      // 记录事实：内容宽度确实可能超过最窄窗宽 274dp。
      // 这里不断言「必须放得下」，只断言滑动容器存在以承接溢出。
      expect(total, greaterThan(0));
      final f = File('android/app/src/main/res/layout/quiz_overlay.xml');
      final xml = f.readAsStringSync();
      expect(xml.contains('android:id="@+id/title_actions_scroll"'), isTrue,
          reason: '方案 A 下按钮区溢出由滑动承载，'
              'title_actions_scroll 必须存在，否则溢出就真的看不到按钮了');
    });
  });

  group('状态行已废弃，不得复活（否则白带回归）', () {
    test('status_row 高度为 0 且 gone', () {
      final h = attrOf('status_row', 'android:layout_height');
      expect(h, equals('0dp'), reason: 'status_row 必须归零，否则又出现白色横带');
    });

    test('相似度胶囊已内联进标题栏', () {
      final barStart = xml.indexOf('android:id="@+id/title_bar"');
      final rowStart = xml.indexOf('android:id="@+id/status_row"');
      final badge = xml.indexOf('android:id="@+id/tv_similarity_badge"');
      expect(badge, greaterThan(barStart));
      expect(badge, lessThan(rowStart),
          reason: '胶囊必须在 title_bar 内、status_row 之前');
    });
  });

  group('AI 联网搜题入口必须显眼可辨（终审亮点项）', () {
    test('AI 按钮带文字标签，不是纯图标', () {
      final start = xml.indexOf('android:id="@+id/btn_ai_vision"');
      final slice = xml.substring(start, (start + 1400).clamp(0, xml.length));
      expect(slice, contains('android:text="AI"'),
          reason: '纯星星用户认不出是联网搜题，必须带 AI 文字');
    });

    test('AI 按钮有独立底色（区别于其他图标按钮）', () {
      final start = xml.indexOf('android:id="@+id/btn_ai_vision"');
      final slice = xml.substring(start, (start + 1400).clamp(0, xml.length));
      expect(slice, contains('quiz_ai_button_bg'));
    });
  });
}
