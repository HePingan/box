// 悬浮窗标题栏排版预览：按真实 dp 和颜色画出新旧两版，供人工判断「丑不丑」。
// 这是设计稿渲染，不是从 Android 布局反推 —— 尺寸/颜色与 quiz_overlay.xml 保持一致。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _titleGradStart = Color(0xFF6366F1);
const _titleGradEnd = Color(0xFF4F46E5);

/// 中文字体：headless 渲染器默认无 CJK 字形，会画成方块，必须先加载。
Future<void> _loadCjkFont() async {
  const candidates = [
    '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc',
    '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf',
  ];
  for (final path in candidates) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final loader = FontLoader('CJK')
      ..addFont(Future.value(f.readAsBytesSync().buffer.asByteData()));
    await loader.load();
    return;
  }
}

void main() {
  test('渲染标题栏新旧对比图', () async {
    await _loadCjkFont();
    const width = 480.0; // 最宽机型窗宽
    const barH = 36.0;
    const scale = 3.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 背景
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, 720),
      Paint()..color = const Color(0xFFE5E7EB),
    );

    // ── 新版（第二轮优化后）──
    _label(canvas, '新：状态胶囊在左(绿/灰/琥珀) + 留白 + ⋯ + [✨ AI] + 👁 + ✕（去掉冗余字样、间距分层）', 16);
    _newTitleBar(canvas, Offset(12, 36), width - 24, barH);
    _answerPreview(canvas, Offset(12, 36 + barH), width - 24,
        '答案：取得学习驾驶证明', pill: '90%', pillColor: const Color(0xFF12B76A));

    // ── 未命中态 ──
    _label(canvas, '新：未命中态的引导（用户诉求）', 268);
    _newTitleBar(canvas, Offset(12, 288), width - 24, barH,
        pill: '未命中', pillColor: const Color(0xFF98A2B3));
    _answerPreview(canvas, Offset(12, 288 + barH), width - 24,
        '未搜到答案。点右上角 ✨ 星星按钮，用 AI 联网搜题。',
        pill: '未命中', pillColor: const Color(0xFF98A2B3), miss: true);

    // ── 检索中态 ──
    _label(canvas, '新：读屏中（琥珀胶囊 + 进度条）', 468);
    _newTitleBar(canvas, Offset(12, 488), width - 24, barH,
        pill: '读屏中', pillColor: const Color(0xFFF59E0B));

    // ── 真机窄窗复现（用户 18:44 截图的那台：iQOO 1440px/密度3.5 → 窗仅 137dp）──
    // 这是**真因面板**：与上面几栏不同，这里窗宽只有 137dp，标题栏静态需求
    // 193~224dp → 溢出。旧逻辑下右侧按钮被裁掉（用户截图里 AI + 更多 消失）。
    _label(canvas, '真因复现：窄窗 137dp（iQOO 1440px@3.5）— 旧 vs 新', 550);
    _label(canvas, '旧：193dp 挤进 137dp → 「更多」越界消失、AI 被胶囊压住 ↓', 572);
    _newTitleBar(canvas, Offset(12, 588), 137, barH,
        pill: '未命中', pillColor: const Color(0xFF98A2B3), adaptive: false);
    _label(canvas, '新：自适应让位 — 胶囊/更多先收，AI 保位零重叠可见 ↓', 636);
    _newTitleBar(canvas, Offset(12, 654), 137, barH,
        pill: '未命中', pillColor: const Color(0xFF98A2B3), adaptive: true);

    final img = await recorder.endRecording().toImage(
        (width * scale).toInt(), (720 * scale).toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('/root/box/build/titlebar_preview.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    debugPrint('written');
  });
}

void _label(Canvas c, String s, double y) {
  final tp = TextPainter(
    text: TextSpan(
        text: s,
        style: const TextStyle(
            fontFamily: 'CJK',
            color: Color(0xFF111827),
            fontSize: 11,
            fontWeight: FontWeight.bold)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, Offset(12, y));
}

void _newTitleBar(Canvas c, Offset o, double w, double h,
    {String pill = '90%',
    Color pillColor = const Color(0xFF12B76A),
    bool adaptive = true}) {
  final r = Rect.fromLTWH(o.dx, o.dy, w, h);
  // 渐变底
  c.drawRRect(
    RRect.fromRectAndCorners(r,
        topLeft: const Radius.circular(14), topRight: const Radius.circular(14)),
    Paint()
      ..shader = ui.Gradient.linear(r.topLeft, r.topRight,
          [_titleGradStart, _titleGradEnd]),
  );

  // 自适应预算：可用宽度 = w - 左右 padding(12+12)。
  // 用户 2026-09-13 第三次拍板：关闭(✕)移除；AI/眼睛/录入三键常驻；
  // AI 去图标收窄到约 30dp。只有「更多」和「相似度胶囊」参与让位。
  final budget0 = w - 24;
  const aiW0 = 30.0, eyeW0 = 29.0, entryW0 = 29.0, moreW0 = 31.0;
  var budget = budget0 - (aiW0 + eyeW0 + entryW0);
  final showMore = adaptive ? budget >= moreW0 : true;
  if (showMore) budget -= moreW0;
  final showPill = adaptive ? budget >= 22 : true;

  double x = o.dx + 12;
  // （第二轮已移除「搜题」标记：左端元素过多且与状态胶囊语义重复）

  // 状态胶囊（自适应：空间不足则收起）
  if (showPill) {
    final pillW = _textWidth(pill, 9, bold: true) + 14;
    c.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(x, o.dy + 9, pillW, 18), const Radius.circular(10)),
      Paint()..color = pillColor.withValues(alpha: 0.92),
    );
    _text(c, pill, Offset(x + 7, o.dy + 13), 9, Colors.white, bold: true);
    x += pillW + 2;
  }

  // 右侧控件（从右往左定位）：三键常驻，✕ 已移除。
  double rx = o.dx + w - 12;
  // 录入题目（最右）
  rx -= 26;
  _circleBtn(c, Offset(rx, o.dy + 5), 26, '录');
  // 眼睛
  rx -= 3 + 26;
  _circleBtn(c, Offset(rx, o.dy + 5), 26, '👁');
  // AI 胶囊（核心：永不隐藏，已去图标收窄）
  rx -= 4;
  final aiW = 9 + _textWidth('AI', 11, bold: true) + 9;
  rx -= aiW;
  c.drawRRect(
    RRect.fromRectAndRadius(
        Rect.fromLTWH(rx, o.dy + 5, aiW, 26), const Radius.circular(13)),
    Paint()..color = const Color(0xFF5B21B6),
  );
  // 边框
  c.drawRRect(
    RRect.fromRectAndRadius(
        Rect.fromLTWH(rx, o.dy + 5, aiW, 26), const Radius.circular(13)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0xFFA5B4FC),
  );
  _text(c, 'AI', Offset(rx + 9, o.dy + 12), 11, Colors.white, bold: true);
  if (showMore) {
    rx -= 4 + 26; // more
    _circleBtn(c, Offset(rx, o.dy + 5), 26, '⋯');
  }
}

void _answerPreview(Canvas c, Offset o, double w, String text,
    {String? pill, Color? pillColor, bool miss = false}) {
  const h = 76.0;
  c.drawRRect(
    RRect.fromRectAndCorners(
        Rect.fromLTWH(o.dx, o.dy, w, h),
        bottomLeft: const Radius.circular(12),
        bottomRight: const Radius.circular(12)),
    Paint()..color = miss ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC),
  );
  final tp = TextPainter(
    text: TextSpan(
        text: text,
        style: TextStyle(
            fontFamily: 'CJK',
            color: miss ? const Color(0xFF92400E) : const Color(0xFF344054),
            fontSize: 13,
            height: 1.35,
            fontWeight: miss ? FontWeight.w600 : FontWeight.normal)),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: w - 24);
  tp.paint(c, Offset(o.dx + 12, o.dy + 12));
}

double _textWidth(String s, double size, {bool bold = false}) {
  final tp = TextPainter(
    text: TextSpan(
        text: s,
        style: TextStyle(
            fontFamily: 'CJK',
            fontSize: size, fontWeight: bold ? FontWeight.bold : null)),
    textDirection: TextDirection.ltr,
  )..layout();
  return tp.width;
}

void _text(Canvas c, String s, Offset o, double size, Color color,
    {bool bold = false}) {
  final tp = TextPainter(
    text: TextSpan(
        text: s,
        style: TextStyle(
            fontFamily: 'CJK',
            color: color,
            fontSize: size,
            fontWeight: bold ? FontWeight.bold : null)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, o);
}

void _circleBtn(Canvas c, Offset o, double d, String glyph) {
  c.drawCircle(
      Offset(o.dx + d / 2, o.dy + d / 2), d / 2, Paint()..color = const Color(0x1FFFFFFF));
  _text(c, glyph, Offset(o.dx + 7, o.dy + 6), 12, const Color(0xFFF8FAFC));
}

