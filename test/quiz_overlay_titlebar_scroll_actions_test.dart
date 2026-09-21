import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 悬浮窗标题栏「按钮区可横向滑动」结构契约（方案 A，用户 2026-09-15 拍板）。
///
/// ## 背景
/// 用户报「上面的功能按钮被裁掉了」。真机实测：标题栏有 6 个常驻控件合计约
/// 204dp，而窗口窄时可用宽度仅约 119dp → 右侧按钮被裁。
///
/// 用户拍板方案 A：**右侧按钮区改为横向可滑动**，且必须保留拖窗能力。
///
/// ## 本测试锁死的结构契约（改坏任一条即红灯）
/// 1. `title_bar` 下必须存在 `HorizontalScrollView`（`title_actions_scroll`）；
/// 2. 6 个功能按钮必须**在滑动区内部**（否则滑不动）；
/// 3. 拖动热区 `title_drag_handle` 必须**在滑动区外部**且在 `title_bar` 内
///    —— 这是「横滑归按钮、拖动归左侧」互不抢手势的结构前提；
/// 4. 相似度胶囊也在滑动区外（作为拖动热区的一部分，且不被滑走）。
///
/// 为什么必须用结构断言而非源码文本断言：
/// 上一次尺寸类缺陷就是「测试只断源码文本、从不校验真实结构」而漏掉的。
/// 这里用 XML 解析真实父子层级，而非正则匹配字符串。
void main() {
  late String xml;

  setUpAll(() {
    final f = File('android/app/src/main/res/layout/quiz_overlay.xml');
    expect(f.existsSync(), isTrue, reason: '找不到悬浮窗布局文件');
    xml = f.readAsStringSync();
  });

  /// 返回 id 对应元素的开标签索引。
  int idx(String id) => xml.indexOf('android:id="@+id/$id"');

  test('title_bar 内必须有 HorizontalScrollView（按钮滑动容器）', () {
    expect(idx('title_bar'), greaterThan(0), reason: '布局里应有 title_bar');
    expect(idx('title_actions_scroll'), greaterThan(0),
        reason: '方案 A 要求按钮区可滑动：title_bar 下必须存在 '
            'title_actions_scroll（HorizontalScrollView）');
  });

  test('title_actions_scroll 必须是 HorizontalScrollView 且含按钮行', () {
    final i = idx('title_actions_scroll');
    // 向上找最近的 '<' 取标签名
    final lt = xml.lastIndexOf('<', i);
    final tagEnd = xml.indexOf(' ', lt);
    final tagName = xml.substring(lt + 1, tagEnd).trim();
    expect(tagName, 'HorizontalScrollView',
        reason: 'title_actions_scroll 应是 HorizontalScrollView，实际是 <$tagName>');
    expect(idx('title_actions_row'), greaterThan(i),
        reason: '滑动区内部应有 title_actions_row 作为按钮行容器');
  });

  test('6 个功能按钮必须全部在滑动区内部（否则滑不动）', () {
    const buttons = [
      'btn_more',
      'btn_ai_vision',
      'btn_region_entry',
      'btn_hide_overlay',
      'btn_quiz_entry',
    ];
    final scrollStart = idx('title_actions_scroll');
    final rowStart = idx('title_actions_row');
    expect(scrollStart, greaterThan(0));
    expect(rowStart, greaterThan(scrollStart),
        reason: '按钮行容器应在滑动区开标签之后');

    for (final b in buttons) {
      final bi = idx(b);
      expect(bi, greaterThan(rowStart),
          reason: '$b 应在 title_actions_row 内部（即滑动区内部），'
              '否则按钮无法横向滑动，用户报的「被裁掉」会复现');
    }
  });

  test('拖动热区 title_drag_handle 必须在滑动区外部（否则滑动会抢走拖窗手势）', () {
    final handle = idx('title_drag_handle');
    expect(handle, greaterThan(0),
        reason: '方案 A 必须有独立拖动热区 title_drag_handle：'
            '因为 title_bar 含 HorizontalScrollView 后，'
            '若把整个 title_bar 当拖动目标，横向手势会被 ScrollView 吃掉，'
            '窗口将无法拖动');

    final scrollStart = idx('title_actions_scroll');
    expect(handle, lessThan(scrollStart),
        reason: 'title_drag_handle 必须在滑动区**之前**（外部），'
            '否则它会被 ScrollView 吞掉横向手势，拖动失效');
  });

  test('拖动热区必须有真实宽度（0dp 会让拖窗无从下手）', () {
    final i = idx('title_drag_handle');
    final slice = xml.substring(i, (i + 500).clamp(0, xml.length));
    final m = RegExp(r'android:layout_width="([^"]+)"').firstMatch(slice);
    expect(m, isNotNull, reason: 'title_drag_handle 应显式声明 layout_width');
    final w = m!.group(1)!;
    expect(w, isNot('0dp'),
        reason: 'title_drag_handle 宽度不能为 0dp：否则拖动热区实际不存在，'
            '用户抓不住窗口（当前约定 28dp）');
  });

  test('相似度胶囊在拖动区外侧（不被滑走，且作为拖动热区）', () {
    final badge = idx('tv_similarity_badge');
    expect(badge, greaterThan(0));
    final scrollStart = idx('title_actions_scroll');
    expect(badge, lessThan(scrollStart),
        reason: '相似度胶囊应留在滑动区外：它既是常驻状态显示，'
            '也是拖动热区的一部分');
  });

  test('title_bar 自身高度仍为 36dp（不因加滑动而变高挤占答案区）', () {
    final i = idx('title_bar');
    final slice = xml.substring(i, (i + 400).clamp(0, xml.length));
    final m = RegExp(r'android:layout_height="([^"]+)"').firstMatch(slice);
    expect(m, isNotNull);
    expect(m!.group(1), '36dp',
        reason: '标题栏高度须保持 36dp；加 HorizontalScrollView 不应把它撑高，'
            '否则会挤占答案显示区（与高度自适应策略冲突）');
  });

  test('滑动区启用浅色风格开关：scrollbars=none + overScrollMode=never', () {
    final i = idx('title_actions_scroll');
    final slice = xml.substring(i, (i + 600).clamp(0, xml.length));
    expect(RegExp(r'android:scrollbars="none"').hasMatch(slice), isTrue,
        reason: '标题栏仅 36dp 高，显示滚动条会压住按钮');
    expect(RegExp(r'android:overScrollMode="never"').hasMatch(slice), isTrue,
        reason: '滑到尽头出现光晕会干扰浮层观感');
  });
}
