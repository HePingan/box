/// 从 OCR 全文解析题干 / 选项 / 答案（适配驾考宝典等常见 UI）。
///
/// 支持题型（用户截图样式）：
/// 1. 单选 + 配图 + A/B/C/D 文字选项（如「违法行为」）
/// 2. 判断纯文字：A 正确 / B 错误
/// 3. 判断 + 配图
/// 4. 单选 + 多图选项：A 图1 / B 图4 …
class OcrQuizParseResult {
  const OcrQuizParseResult({
    this.question = '',
    this.options = const [],
    this.correctAnswer = '',
    this.analysis = '',
    this.rawText = '',
    this.questionType = 'single_choice',
  });

  final String question;
  final List<String> options;
  final String correctAnswer;
  final String analysis;
  final String rawText;

  /// single_choice | true_false
  final String questionType;
}

class _QaSplit {
  const _QaSplit({required this.question, required this.options});
  final String question;
  final List<String> options;
}

class OcrQuizParser {
  OcrQuizParser._();

  /// 选项行：A. xxx / A、xxx / A 正确；排除 C1/B2 准驾车型代号
  static final _optLine = RegExp(
    r'^\s*([A-DＡ-Ｄ])(?!\d)(?:\s*[.、．:：)）]\s*|\s+)(.+?)\s*$',
  );

  static final _answerLine = RegExp(r'^\s*(答案|正确答案|参考答案)\s*[:：]?\s*(.+)$');

  static final _answerInline = RegExp(
    r'(?:答案|正确答案)\s*[:：]?\s*([A-DＡ-Ｄ正确错误对错]+)',
  );

  /// 进入解析/技巧区
  static final _analysisStart = RegExp(
    r'^\s*(解析|说明|详解|题目解析|本题技巧|本题口诀|技巧|试题详解|相关法规)',
  );

  static final _tfOnly = RegExp(r'^\s*(正确|错误|对|错)\s*$');
  static final _imageOpt = RegExp(r'^图\s*[1-4１２３４]$');

  static final _noiseExact = <String>{
    '答题',
    '背题',
    '视频',
    '设置',
    '读题',
    '收藏',
    '速记',
    '点我讲题',
    '有问题',
    '单选',
    '判断',
    '多选',
    'new',
    'NEW',
    '驾考宝典',
    '查看完整技巧',
    '查看完整技巧>',
    '查看完整技巧>>',
  };

  static final _noiseContains = <RegExp>[
    RegExp(r'适用于\d+道题'),
    RegExp(r'^\d+/\d+$'),
    RegExp(r'^\d{3,5}$'),
    RegExp(r'KB/s|5G|4G'),
    RegExp(r'查看完整'),
    RegExp(r'点我讲'),
    RegExp(r'有问题'),
    RegExp(r'^[-—–\s]+$'),
  ];

  static OcrQuizParseResult parse(String raw) {
    final text = raw.replaceAll('\r\n', '\n').trim();
    if (text.isEmpty) {
      return OcrQuizParseResult(rawText: raw);
    }

    final normalized = text
        // OCR/无障碍常把「·」当逻辑项分隔符（分隔题干与选项、选项之间）；先切成行。
        .replaceAll(RegExp(r'[·•・]'), '\n')
        .replaceAllMapped(
          // 无障碍树有时把选项字母和正文拆成相邻节点：A\n选项 → A. 选项。
          RegExp(
            r'^\s*([A-DＡ-Ｄ])\s*\n\s*(?!答案|正确答案)([^\n]+)$',
            multiLine: true,
          ),
          (m) => '${m.group(1)}. ${m.group(2)}',
        )
        .replaceAllMapped(
          RegExp(r'(答案|正确答案)\s*([A-DＡ-Ｄ])\b'),
          (m) => '${m.group(1)}：${m.group(2)}',
        )
        .replaceAllMapped(
          RegExp(r'([A-DＡ-Ｄ])(?!\d)\s*(正确|错误)(?=\s*[B-DＢ-Ｄ]|$)'),
          (m) => '${m.group(1)}. ${m.group(2)}',
        );

    final lines = normalized
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .where((e) => !_isNoiseLine(e))
        .toList();

    final options = <String>[];
    final questionParts = <String>[];
    String answer = '';
    String analysis = '';
    var inAnalysis = false;
    var sawOption = false;

    for (final line in lines) {
      // 答案
      final ans = _answerLine.firstMatch(line);
      if (ans != null) {
        final answerAndAnalysis = ans.group(2)!.trim();
        // OCR 常把「答案：C 解析：……」合并为同一行；先截答案，再保留解析。
        final split = answerAndAnalysis.split(
          RegExp(r'\s*(?:解析|说明|详解|技巧)\s*[:：]?\s*'),
        );
        answer = split.first.trim();
        if (split.length > 1) {
          analysis = split.skip(1).join(' ').trim();
        }
        // 答案出现后，后续默认进解析区（驾考 UI：答案栏下面是技巧）
        inAnalysis = true;
        continue;
      }
      final ansInline = _answerInline.firstMatch(line);
      if (ansInline != null && answer.isEmpty) {
        answer = ansInline.group(1)!.trim();
        inAnalysis = true;
        continue;
      }

      // 解析 / 技巧区
      if (_analysisStart.hasMatch(line)) {
        inAnalysis = true;
        final body = line
            .replaceFirst(_analysisStart, '')
            .replaceFirst(RegExp(r'^[:：\s]+'), '')
            .trim();
        if (body.isNotEmpty && analysis.length < 400) {
          analysis = analysis.isEmpty ? body : '$analysis\n$body';
        }
        continue;
      }
      if (inAnalysis) {
        if (analysis.length < 400 && !_isNoiseLine(line)) {
          analysis = analysis.isEmpty ? line : '$analysis\n$line';
        }
        continue;
      }

      // 同行多选项
      final multi = _splitInlineOptions(line);
      if (multi.length >= 2) {
        options.addAll(multi);
        sawOption = true;
        continue;
      }

      final opt = _optLine.firstMatch(line);
      if (opt != null) {
        final body = _cleanOptionBody(opt.group(2)!);
        if (body.isNotEmpty) {
          options.add(body);
          sawOption = true;
        }
        continue;
      }

      if (_tfOnly.hasMatch(line)) {
        if (!options.contains(line.trim())) options.add(line.trim());
        sawOption = true;
        continue;
      }

      final imgLine = line.replaceAll(' ', '');
      if (_imageOpt.hasMatch(imgLine)) {
        if (!options.contains(imgLine)) options.add(imgLine);
        sawOption = true;
        continue;
      }

      if (sawOption && answer.isEmpty && RegExp(r'^[A-DＡ-Ｄ]$').hasMatch(line)) {
        answer = line;
        inAnalysis = true;
        continue;
      }

      // 题干：仅选项出现前收集
      if (!sawOption && !_looksLikeChrome(line)) {
        questionParts.add(line);
      }
    }

    var question = _cleanQuestion(questionParts.join('\n').trim());

    // 驾考无字母选项兜底（如「违规行为/违章行为/违法行为/犯罪行为」）
    if (options.isEmpty) {
      final split = _splitQa(lines);
      if (split != null) {
        question = split.question;
        options.addAll(split.options);
      }
    }

    final isTrueFalse = _detectTrueFalse(question, options, normalized);
    var finalOptions = options;
    if (isTrueFalse) {
      finalOptions = _normalizeTrueFalseOptions(options);
    } else if (finalOptions.isEmpty) {
      if (normalized.contains('图1') ||
          normalized.contains('图 1') ||
          RegExp(r'以下哪种|下列哪|哪一种|哪幅').hasMatch(question)) {
        finalOptions = ['图1', '图2', '图3', '图4'];
      }
    }
    finalOptions = _uniqueKeepOrder(finalOptions);

    final mapped = _mapAnswerToOption(answer, finalOptions, isTrueFalse);

    return OcrQuizParseResult(
      question: question,
      options: finalOptions,
      correctAnswer: mapped,
      analysis: analysis.trim(),
      rawText: text,
      questionType: isTrueFalse ? 'true_false' : 'single_choice',
    );
  }

  static bool _isNoiseLine(String line) {
    final t = line.trim();
    if (t.isEmpty) return true;
    if (_noiseExact.contains(t)) return true;
    if (_noiseExact.contains(t.toLowerCase())) return true;
    for (final re in _noiseContains) {
      if (re.hasMatch(t)) return true;
    }
    if (RegExp(r'收藏').hasMatch(t) && t.length < 12) return true;
    return false;
  }

  static bool _looksLikeChrome(String line) {
    return _isNoiseLine(line) ||
        line.contains('技巧') ||
        line.contains('解析') ||
        line.contains('收藏');
  }

  static String _cleanOptionBody(String body) {
    var b = body.trim();
    b = b.replaceAll(RegExp(r'答案\s*[A-DＡ-Ｄ].*$'), '').trim();
    b = b.replaceFirst(RegExp(r'^[A-DＡ-Ｄ](?!\d)\s*[.、．:：)）\s]+'), '');
    return b.trim();
  }

  static String _cleanQuestion(String q) {
    var question = q;
    question = question.replaceFirst(RegExp(r'^\s*\d+\s*[.、．:：]\s*'), '');
    question = question.replaceFirst(RegExp(r'^(单选|判断|多选)\s*'), '');
    question = question.replaceAll(RegExp(r'读题'), '');
    question = question.replaceAll('驾考宝典', '');
    // 去噪点符号（OCR 误识的 · × 等装饰符）
    question = question.replaceAll(RegExp(r'[·•×xX＊*]+'), '').trim();
    question = question
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !_isNoiseLine(e))
        .join('\n')
        .trim();
    return question;
  }

  static bool _detectTrueFalse(
    String question,
    List<String> options,
    String fullText,
  ) {
    if (options.length == 2) {
      final a = options[0];
      final b = options[1];
      bool tf(String s) =>
          s.contains('正确') || s == '对' || s.contains('错误') || s == '错';
      if (tf(a) && tf(b)) return true;
    }
    if (fullText.contains('判断') && options.length <= 2) {
      if (options.isEmpty) return true;
      if (options.every(
        (o) => o.contains('正确') || o.contains('错误') || o == '对' || o == '错',
      )) {
        return true;
      }
    }
    return false;
  }

  static List<String> _normalizeTrueFalseOptions(List<String> options) {
    return const ['正确', '错误'];
  }

  static List<String> _uniqueKeepOrder(List<String> list) {
    final seen = <String>{};
    final out = <String>[];
    for (final e in list) {
      final k = e.trim();
      if (k.isEmpty || seen.contains(k)) continue;
      seen.add(k);
      out.add(k);
    }
    return out;
  }

  static List<String> _splitInlineOptions(String line) {
    final matches = RegExp(
      r'([A-DＡ-Ｄ])(?!\d)\s*[.、．:：)）\s]\s*([^A-DＡ-Ｄ]+?)(?=(?:\s*[A-DＡ-Ｄ](?!\d)\s*[.、．:：)）\s])|$)',
    ).allMatches(line);
    if (matches.length < 2) return const [];
    return matches
        .map((m) => _cleanOptionBody(m.group(2)!))
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// 识别「题干 + 紧接着 2~5 个无字母前缀的短选项」结构。
  /// 典型：驾考宝典「xx 属于什么行为?」后接「违规行为/违章行为/违法行为/犯罪行为」。
  /// 返回 null 表示未命中。
  static _QaSplit? _splitQa(List<String> lines) {
    if (lines.length < 3) return null;
    // 找第一行程式：含问号/选择题尾词，且后面有 ≥2 短选项
    for (var i = 0; i < lines.length - 1; i++) {
      final head = lines[i];
      final isQuestionLike =
          head.contains('?') ||
          head.contains('？') ||
          // 填空式题干：OCR 常丢问号，「（）」是强题干信号。
          head.contains('（）') ||
          head.contains('()') ||
          RegExp(
            r'(属于|是什么|哪些|哪种|哪个|如何|为什么|错误的是|正确的是|以下|表示|含义|行为是|的是)',
          ).hasMatch(head);
      if (!isQuestionLike) continue;
      final opts = <String>[];
      for (var j = i + 1; j < lines.length && opts.length < 6; j++) {
        final t = lines[j].trim();
        // 选项：短、无冒号、非噪声
        if (t.isEmpty ||
            t.length > 30 ||
            t.contains('：') ||
            t.contains(':') ||
            _isNoiseLine(t) ||
            RegExp(r'^[A-DＡ-Ｄ][.、．:：]').hasMatch(t) ||
            RegExp(r'答案|解析|技巧').hasMatch(t)) {
          break;
        }
        opts.add(_cleanOptionNoise(t));
      }
      // OCR 常把同屏并排的选项黏进一行（如「未立即排除故障未将车停到路边」）；
      // 若多数选项共享首字，按首字二次切分。
      final expanded = _splitGluedSiblings(opts);
      if (expanded.length >= 2 && expanded.length <= 5) {
        return _QaSplit(question: _cleanQuestion(head), options: expanded);
      }
    }
    return null;
  }

  /// 兄弟选项共享首字时，拆开被 OCR 黏连的选项。
  /// 例：首字均为「未」→「未立即排除故障未将车停到路边」拆成两项。
  /// 仅在 ≥2 个选项共享同一首字时启用，避免误切普通文本。
  static List<String> _splitGluedSiblings(List<String> opts) {
    if (opts.length < 2) return opts;
    // 统计首字频次，取出现 ≥2 次的首字作为切分标记。
    final firstCharCount = <String, int>{};
    for (final o in opts) {
      if (o.isEmpty) continue;
      final c = o.substring(0, 1);
      firstCharCount[c] = (firstCharCount[c] ?? 0) + 1;
    }
    final delim = firstCharCount.entries
        .where((e) => e.value >= 2)
        .fold<MapEntry<String, int>?>(
          null,
          (best, e) => best == null || e.value > best.value ? e : best,
        )
        ?.key;
    if (delim == null) return opts;
    final out = <String>[];
    for (final o in opts) {
      if (o.length > 1 && o.substring(1).contains(delim)) {
        // 在内部出现的 delim 处切分，保留 delim 作为后段首字。
        var buf = o.substring(0, 1);
        for (var k = 1; k < o.length; k++) {
          final ch = o[k];
          if (ch == delim) {
            if (buf.isNotEmpty) out.add(buf);
            buf = ch;
          } else {
            buf += ch;
          }
        }
        if (buf.isNotEmpty) out.add(buf);
      } else {
        out.add(o);
      }
    }
    return out;
  }

  /// 清洗单条选项文本的噪点（· × 等装饰符、首尾标点）。
  static String _cleanOptionNoise(String raw) {
    var t = raw.trim();
    t = t.replaceAll(RegExp(r'[·•×xX＊*]+'), '').trim();
    t = t.replaceFirst(RegExp(r'^[.、．:：)）\s]+'), '');
    t = t.replaceFirst(RegExp(r'[.、．:：)）\s]+$'), '');
    return t.trim();
  }

  static String _mapAnswerToOption(
    String answer,
    List<String> options,
    bool isTrueFalse,
  ) {
    var a = answer.trim();
    if (a.isEmpty) return '';
    a = a.replaceFirst(RegExp(r'^(答案|正确答案)\s*[:：]?\s*'), '');
    if (options.contains(a)) return a;

    final letter = RegExp(r'[A-DＡ-Ｄ]').firstMatch(a)?.group(0);
    if (letter != null) {
      final key = letter
          .replaceAll('Ａ', 'A')
          .replaceAll('Ｂ', 'B')
          .replaceAll('Ｃ', 'C')
          .replaceAll('Ｄ', 'D');
      final idx = {'A': 0, 'B': 1, 'C': 2, 'D': 3}[key];
      if (idx != null && idx < options.length) return options[idx];
    }

    final img = RegExp(r'图\s*([1-4])').firstMatch(a);
    if (img != null) {
      final label = '图${img.group(1)}';
      if (options.contains(label)) return label;
      final hit = options.where((o) => o.contains(label)).toList();
      if (hit.isNotEmpty) return hit.first;
    }

    if (a.contains('错误') || a == '错' || a == 'B' || a == 'Ｂ') {
      final hit = options.where((o) => o.contains('错误') || o == '错').toList();
      if (hit.isNotEmpty) return hit.first;
      if (isTrueFalse) return '错误';
    }
    if (a.contains('正确') || a == '对' || a == 'A' || a == 'Ａ') {
      final hit = options.where((o) => o.contains('正确') || o == '对').toList();
      if (hit.isNotEmpty) return hit.first;
      if (isTrueFalse) return '正确';
    }

    for (final o in options) {
      if (o.contains(a) || a.contains(o)) return o;
    }
    return a;
  }
}
