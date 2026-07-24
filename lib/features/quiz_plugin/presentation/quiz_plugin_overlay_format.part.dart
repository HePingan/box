part of './quiz_plugin_entry.dart';

// 悬浮窗文本格式化 —— 纯函数，无共享可变状态。

/// 将引擎的结构化答案转成悬浮窗正文。
/// 本地题库的 answer.text 是完整详情（首行常为「匹配题目」），
/// 必须优先使用 correctAnswer，不能把整段详情硬加「答案：」前缀。
/// 取引擎给出的相似度，作为原生标题栏的稳定状态信息。
int? _similarityForResult(QuizResult result) {
  if (!result.isSuccess || result.answers.isEmpty) return null;
  return QuizPluginEntry.similarityPercentForAnswer(result.answers.first);
}

String _withSimilarityMarker(String text, QuizResult result) {
  final similarity = _similarityForResult(result);
  if (similarity == null) return text;
  // 原生标题栏从正文提取相似度；隐藏 marker 不影响用户阅读，也不会重复显示。
  return '$text\n[[SIM:$similarity]]';
}

/// 悬浮窗正文只放答案本身。
/// 相似度已在标题栏/摘要条展示；匹配题干/选项/解析不再塞进内容区。
String _overlayTextForAnswer(QuizAnswer answer) {
  final correct = answer.correctAnswer.trim();
  if (correct.isNotEmpty) {
    final base = correct.startsWith('答案') ? correct : '答案：$correct';
    if (!answer.alignedToProbe &&
        answer.alignmentMethod == 'bank_raw' &&
        answer.options.isNotEmpty) {
      return '$base（未对齐卷面选项）';
    }
    return base;
  }

  // 无结构化答案时，从详情里尽量抠出答案行；抠不到再退回极简首行。
  final detail = answer.text.trim();
  if (detail.isEmpty) return '答案待核对';
  final lines = detail
      .split('\n')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  final answerLine = lines.firstWhere(
    (line) =>
        line.startsWith('答案') &&
        !line.startsWith('答案区') &&
        !line.contains('相似度'),
    orElse: () => '',
  );
  if (answerLine.isNotEmpty) return answerLine;

  final optionLike = lines.firstWhere(
    (line) =>
        RegExp(r'^[A-DＡ-Ｄ][.、．:：)].+').hasMatch(line) ||
        RegExp(r'^[A-DＡ-Ｄ]$').hasMatch(line) ||
        ((line.contains('正确') || line.contains('错误')) && line.length <= 12),
    orElse: () => '',
  );
  if (optionLike.isNotEmpty) {
    return optionLike.startsWith('答案') ? optionLike : '答案：$optionLike';
  }

  final fallback = lines.firstWhere(
    (line) =>
        !line.startsWith('匹配题目') &&
        !line.startsWith('选项') &&
        !line.startsWith('解析') &&
        !line.contains('相似度'),
    orElse: () => '',
  );
  if (fallback.isEmpty) return '答案待核对';
  return fallback.startsWith('答案') ? fallback : '答案：$fallback';
}

String _formatResultForOverlay(QuizResult result) {
  if (result.isSuccess) {
    final texts = result.answers
        .map(_overlayTextForAnswer)
        .where((text) => text.trim().isNotEmpty)
        .toList();
    if (texts.isEmpty) return '未找到答案';
    if (texts.length == 1) return texts.first.trim();
    final buf = StringBuffer('多个匹配：');
    for (var i = 0; i < texts.length; i++) {
      final label = String.fromCharCode(0x41 + (i % 26));
      buf.write('\n$label. ${texts[i].trim()}');
    }
    return buf.toString();
  }
  return result.error?.isNotEmpty == true ? result.error! : '未找到答案';
}

/// 多匹配列表：每条单独一条，供原生切换正文。
List<String> _answersListForOverlay(QuizResult result) {
  if (!result.isSuccess) return const [];
  return result.answers
      .map(_overlayTextForAnswer)
      .where((t) => t.trim().isNotEmpty)
      .toList();
}

String? _extractAnswerKey(QuizResult result) {
  if (!result.isSuccess || result.answers.isEmpty) return null;
  final structured = result.answers.first.correctAnswer.trim();
  final source = structured.isNotEmpty
      ? structured
      : result.answers.first.text.trim();
  final m = RegExp(r'^[答案：:\s]*([A-DＡ-Ｄ])\b').firstMatch(source);
  if (m != null) return m.group(1);
  final m2 = RegExp(r'答案[是为：:\s]*([A-DＡ-Ｄ])').firstMatch(source);
  return m2?.group(1);
}

String _formatDebugCapture(String captured) {
  final lines = captured
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .take(12)
      .toList();
  final preview = lines.isEmpty ? captured.trim() : lines.join('\n');
  return '【调试】无障碍捕获到 ${captured.length} 字 / ${lines.length} 行\n'
      '若这里有题目但无答案，说明卡在题库匹配；若这里为空/不是题目，说明卡在屏幕捕获或识别区域。\n\n'
      '$preview';
}
