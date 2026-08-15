import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../domain/quiz_config.dart';
import '../domain/quiz_bank.dart';
import '../domain/ocr_quiz_parser.dart';
import '../domain/quiz_answer_aligner.dart';

class QuizResult {
  const QuizResult({
    required this.question,
    this.answers = const [],
    this.error,
    this.elapsedMs = 0,
    this.source = '',
    this.imageUrl,
  });

  final String question;
  final List<QuizAnswer> answers;
  final String? error;
  final int elapsedMs;
  final String source;
  final String? imageUrl;

  QuizResult copyWith({
    String? question,
    List<QuizAnswer>? answers,
    String? error,
    int? elapsedMs,
    String? source,
    String? imageUrl,
  }) {
    return QuizResult(
      question: question ?? this.question,
      answers: answers ?? this.answers,
      error: error ?? this.error,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      source: source ?? this.source,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  bool get isSuccess => error == null && answers.isNotEmpty;
}

class QuizAnswer {
  const QuizAnswer({
    required this.text,
    this.confidence = 0.0,
    this.source = '',
    this.options = const [],
    this.correctAnswer = '',
    this.analysis,
    this.imageUrl,
    this.alignedToProbe = false,
    this.alignmentMethod = '',
  });

  final String text;
  final double confidence;
  final String source;
  final List<String> options;
  final String correctAnswer;
  final String? analysis;
  final String? imageUrl;

  /// 答案是否已投影到当前卷面选项
  final bool alignedToProbe;

  /// exact/letter/synonym/...
  final String alignmentMethod;
}

class QuizEngine {
  QuizEngine({required this.config});

  QuizConfig config;

  Future<QuizResult> search(
    String question, {
    bool forceExternalSearch = false,
    List<String> probeOptions = const [],
  }) async {
    final stopwatch = Stopwatch()..start();
    final trimmed = question.trim();
    if (trimmed.isEmpty) {
      return QuizResult(
        question: question,
        error: '题目为空',
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    }

    if (config.bankEnabled) {
      try {
        final bankResult = await _searchBank(
          trimmed,
          probeOptions: probeOptions,
        );
        if (bankResult != null && bankResult.isNotEmpty) {
          return QuizResult(
            question: question,
            answers: bankResult,
            elapsedMs: stopwatch.elapsedMilliseconds,
            source: '本地题库',
            imageUrl: bankResult.first.imageUrl,
          );
        }
      } catch (_) {
        // 题库查失败不影响继续走外部
      }
    }

    if (!forceExternalSearch && !config.autoSearch) {
      return QuizResult(
        question: question,
        error: '未开启自动搜题',
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    }

    if (config.allowExternalApi && config.apiUrl.isNotEmpty) {
      try {
        final result = await _searchCustomApi(trimmed);
        if (result.isSuccess) {
          return result.copyWith(
            elapsedMs: stopwatch.elapsedMilliseconds,
            source: result.source.isEmpty ? '远程API' : result.source,
          );
        }
      } catch (_) {}
    }

    if (config.allowExternalApi) {
      try {
        final result = await _searchBuiltIn(trimmed);
        return result.copyWith(
          elapsedMs: stopwatch.elapsedMilliseconds,
          source: result.source.isEmpty ? '内置检索' : result.source,
        );
      } catch (e) {
        return QuizResult(
          question: question,
          error: '搜题失败：$e',
          elapsedMs: stopwatch.elapsedMilliseconds,
        );
      }
    }

    return QuizResult(
      question: question,
      error: '本地题库未找到；外部搜题已关闭',
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
  }

  Future<List<QuizAnswer>?> _searchBank(
    String question, {
    List<String> probeOptions = const [],
  }) async {
    await QuizBankCache.instance.ensureLoaded();
    // 自动读屏会带进“答题/背题/设置”等 chrome。题干应与 OCR/试捕路径一样
    // 先经唯一 OcrQuizParser 剥离 chrome/选项，再交给题库 normalizer；
    // 否则 cleanForMatch 取前两行时会把导航文字当题干，导致库中同题也无法命中。
    final parsed = OcrQuizParser.parse(question);
    final searchQuestion = parsed.question.trim().isNotEmpty
        ? parsed.question.trim()
        : question;
    final effectiveOptions = probeOptions.isNotEmpty
        ? probeOptions
        : parsed.options;
    final hay = QuizBankTextNormalizer.cleanForMatch(searchQuestion);
    if (hay.isEmpty) return null;
    final stemLooksImage =
        _stemLooksLikeImageQuestion(searchQuestion) ||
        _stemLooksLikeImageQuestion(question);

    final candidates = QuizBankCache.instance.candidatesFor(hay);
    if (candidates.isEmpty) return null;

    final probeOptNorm = effectiveOptions
        .map(QuizBankTextNormalizer.normalizeOption)
        .where((e) => e.isNotEmpty)
        .toSet();
    final probeImageLike = _isImageLikeOptionSet(effectiveOptions);
    final probeTextLike = _isTextLikeOptionSet(effectiveOptions);

    // ① 题干优先；试捕选项完整时允许作为“召回救援”，避免 OCR 半题漏掉题库原题。
    final byQuestion =
        <({QuizBankItem item, int qScore, int recallOptionScore})>[];
    for (final item in candidates) {
      final target = QuizBankTextNormalizer.cleanForMatch(item.question);
      if (target.isEmpty) continue;
      // 卷面不是看图题时，直接丢掉题库「图1/图2」变体（同题干错版）
      if (!stemLooksImage &&
          !probeImageLike &&
          (_isImageLikeOptionSet(item.options) ||
              _isImageLikeAnswer(item.correctAnswer))) {
        continue;
      }
      final qScore = _questionScore(hay, target);
      final recallOptionScore = probeOptNorm.isEmpty
          ? 0
          : _optionsScore(probeOptNorm, item.options);
      // 题干同文但选项形态冲突（卷面长文 vs 题库图1/图2）直接跳过，避免「答案：A. 图1」。
      if (probeOptNorm.isNotEmpty &&
          _optionShapeConflict(probeImageLike, probeTextLike, item.options)) {
        continue;
      }
      // 常规题干门槛 60；选项高度一致时允许题干最低 35 分入围，交给后续决胜。
      if (qScore >= 60 || (qScore >= 35 && recallOptionScore >= 90)) {
        byQuestion.add((
          item: item,
          qScore: qScore,
          recallOptionScore: recallOptionScore,
        ));
      }
    }
    if (byQuestion.isEmpty) return null;

    byQuestion.sort((a, b) => b.qScore.compareTo(a.qScore));
    final bestQ = byQuestion.first.qScore;

    // ② 取题干接近的一组；若某条选项近乎完全一致，也允许参与决胜。
    // 同题干多变体（文字版/看图版）时放宽入池，交给选项形态与 oScore 决胜。
    final nearGroup = byQuestion.where((e) {
      if (bestQ >= 100) {
        return e.qScore >= 96 || e.recallOptionScore >= 95;
      }
      return (e.qScore >= bestQ - 8 && e.qScore >= 70) ||
          e.recallOptionScore >= 95;
    }).toList();
    final pool = nearGroup.isNotEmpty ? nearGroup : [byQuestion.first];

    // ③ 有试捕选项时始终计算：单候选也用于补偿 OCR 截断后的展示分。
    final useOptions = probeOptNorm.isNotEmpty;

    final scored =
        <
          ({
            QuizBankItem item,
            int score,
            int qScore,
            int oScore,
            int shapeBonus,
          })
        >[];
    for (final e in pool) {
      var oScore = useOptions ? _optionsScore(probeOptNorm, e.item.options) : 0;
      // 无试捕选项时，用题库自身选项形态做弱偏好：同题干优先文字版，避免落到图选题。
      final shapeBonus = useOptions
          ? (probeTextLike && _isTextLikeOptionSet(e.item.options)
                ? 8
                : probeImageLike && _isImageLikeOptionSet(e.item.options)
                ? 8
                : 0)
          : (_isImageLikeOptionSet(e.item.options) ? -18 : 6);
      if (useOptions &&
          _optionShapeConflict(probeImageLike, probeTextLike, e.item.options)) {
        oScore = 0;
      }
      // 卷面已有完整文字选项，但题库选项几乎对不上：强惩罚，防止同题干错变体高置信出炉。
      if (useOptions &&
          probeTextLike &&
          probeOptNorm.length >= 3 &&
          oScore < 40) {
        oScore = min(oScore, 15);
      }
      final bankOptionCount = e.item.options
          .map(QuizBankTextNormalizer.normalizeOption)
          .where((option) => option.isNotEmpty)
          .toSet()
          .length;
      final hasCompleteProbeOptions =
          bankOptionCount > 0 && probeOptNorm.length >= bankOptionCount;
      final baseScore = useOptions
          ? (e.qScore * 0.55 + oScore * 0.45).round().clamp(0, 100)
          : (e.qScore + shapeBonus).clamp(0, 100);
      final score = hasCompleteProbeOptions && e.qScore >= 35 && oScore >= 90
          ? max(baseScore, (e.qScore * 0.20 + oScore * 0.80).round())
          : (baseScore + (useOptions ? 0 : 0));
      scored.add((
        item: e.item,
        score: score.clamp(0, 100),
        qScore: e.qScore,
        oScore: oScore,
        shapeBonus: shapeBonus,
      ));
    }

    scored.sort((a, b) {
      // 决胜：先能否对齐卷面答案，再选项分，再形态分，再题干分
      if (useOptions) {
        final aAlign = QuizAnswerAligner.align(
          bankAnswer: a.item.correctAnswer,
          bankOptions: a.item.options,
          probeOptions: effectiveOptions,
        ).aligned;
        final bAlign = QuizAnswerAligner.align(
          bankAnswer: b.item.correctAnswer,
          bankOptions: b.item.options,
          probeOptions: effectiveOptions,
        ).aligned;
        if (aAlign != bAlign) return bAlign ? 1 : -1;
        final c = b.oScore.compareTo(a.oScore);
        if (c != 0) return c;
      } else {
        final c = b.shapeBonus.compareTo(a.shapeBonus);
        if (c != 0) return c;
      }
      return b.qScore.compareTo(a.qScore);
    });

    // 有完整卷面文字选项时：丢掉选项分过低的候选（同题干图选题/其它变体）
    var filtered = scored;
    if (useOptions && probeTextLike && probeOptNorm.length >= 3) {
      final good = scored.where((e) => e.oScore >= 45).toList();
      if (good.isNotEmpty) {
        filtered = good;
      } else {
        // 全部对不上选项：不返回高置信错答，直接视为未命中
        return null;
      }
    }
    // 无试捕选项时：同题干优先非图选题；若最佳是图选题且存在文字版，换文字版
    if (!useOptions && filtered.isNotEmpty) {
      final best = filtered.first;
      if (_isImageLikeOptionSet(best.item.options) ||
          _isImageLikeAnswer(best.item.correctAnswer)) {
        final textVariant = filtered.firstWhere(
          (e) =>
              !_isImageLikeOptionSet(e.item.options) &&
              !_isImageLikeAnswer(e.item.correctAnswer),
          orElse: () => best,
        );
        if (!identical(textVariant, best)) {
          filtered = [
            textVariant,
            ...filtered.where((e) => !identical(e, textVariant)),
          ];
        }
      }
    }

    // 同题干允许不同选项集共存。若试捕已完整拿到一条题库候选的选项，
    // 选项集就是该题的身份的一部分：只返回完全一致的变体，不能把另一
    // 个同题干版本一起交给悬浮窗，避免首条/轮播落到错误答案。
    final best = filtered.first;
    final bestOptionCount = best.item.options
        .map(QuizBankTextNormalizer.normalizeOption)
        .where((option) => option.isNotEmpty)
        .toSet()
        .length;
    final hasExactCompleteVariant =
        useOptions &&
        best.oScore == 100 &&
        bestOptionCount > 0 &&
        probeOptNorm.length >= bestOptionCount;
    final selected = hasExactCompleteVariant
        ? filtered.where((entry) => entry.oScore == 100).toList()
        : filtered;
    final top = selected.take(config.bankMaxMatches).toList();
    if (top.isEmpty || (top.first.qScore < 60 && top.first.oScore < 90)) {
      return null;
    }
    // 最终闸门：非看图题不得返回「图N」答案（无论有无试捕选项）
    if (!stemLooksImage &&
        !probeImageLike &&
        (_isImageLikeAnswer(top.first.item.correctAnswer) ||
            _isImageLikeOptionSet(top.first.item.options) ||
            _isImageLikeAnswer(
              QuizAnswerAligner.align(
                bankAnswer: top.first.item.correctAnswer,
                bankOptions: top.first.item.options,
                probeOptions: effectiveOptions,
              ).displayAnswer,
            ))) {
      return null;
    }
    // 卷面文字题却只命中图选题答案（图1/图2）：当作未命中，避免误导
    if (_isImageLikeAnswer(top.first.item.correctAnswer) &&
        (probeTextLike ||
            (!_isImageLikeOptionSet(top.first.item.options) && useOptions))) {
      // keep if bank options themselves are image and probe also image
      if (!(probeImageLike && _isImageLikeOptionSet(top.first.item.options))) {
        if (useOptions && top.first.oScore < 80) return null;
      }
    }

    final mapped = top
        .map((entry) {
          final item = entry.item;
          final alignment = QuizAnswerAligner.align(
            bankAnswer: item.correctAnswer,
            bankOptions: item.options,
            probeOptions: effectiveOptions,
          );
          // 对齐结果仍是图N且卷面非看图：丢弃
          if (!stemLooksImage &&
              !probeImageLike &&
              _isImageLikeAnswer(alignment.displayAnswer)) {
            return null;
          }
          var adjustedScore = useOptions
              ? (entry.score * alignment.confidenceFactor).round().clamp(0, 100)
              : entry.score;
          // 答案仍是「图N」且卷面是文字题：强制降置信
          if (_isImageLikeAnswer(alignment.displayAnswer) && probeTextLike) {
            adjustedScore = min(adjustedScore, 40);
          }
          if (!useOptions &&
              (_isImageLikeAnswer(alignment.displayAnswer) ||
                  _isImageLikeOptionSet(item.options))) {
            adjustedScore = min(adjustedScore, 40);
          }
          final displayAnswer = alignment.displayAnswer.isNotEmpty
              ? alignment.displayAnswer
              : item.correctAnswer;
          // correctAnswer 存裸答案（不含 A/B/C 字母前缀），供 UI 首行直接展示；
          // 带字母前缀的对齐详情保留在 text 中。对齐命中时用 probeOption（裸选项正文），
          // 未对齐 (bank_raw) 时退回题库原文。
          final bareAnswer = alignment.probeOption.trim().isNotEmpty
              ? alignment.probeOption.trim()
              : (item.correctAnswer.trim().isNotEmpty
                    ? item.correctAnswer.trim()
                    : displayAnswer);
          final formatted = _formatBankAnswer(
            item,
            adjustedScore,
            questionScore: entry.qScore,
            optionsScore: entry.oScore,
            hasProbeOptions: useOptions,
            optionTieBreak: useOptions,
            displayAnswer: displayAnswer,
            aligned: alignment.aligned,
            alignmentMethod: alignment.method,
          );
          return QuizAnswer(
            text: formatted,
            confidence: adjustedScore / 100,
            source: '本地题库',
            options: effectiveOptions.isNotEmpty
                ? effectiveOptions
                : item.options,
            correctAnswer: bareAnswer,
            analysis: item.analysis,
            imageUrl: item.imageUrl,
            alignedToProbe: alignment.aligned,
            alignmentMethod: alignment.method,
          );
        })
        .whereType<QuizAnswer>()
        .toList();
    if (mapped.isEmpty) return null;
    return mapped;
  }

  bool _stemLooksLikeImageQuestion(String raw) {
    final t = raw.replaceAll(RegExp(r'\s+'), '');
    if (t.isEmpty) return false;
    return t.contains('如图') ||
        t.contains('见图') ||
        t.contains('下图') ||
        t.contains('上图') ||
        t.contains('图中') ||
        t.contains('图片') ||
        RegExp(r'图\d').hasMatch(t);
  }

  bool _isImageLikeOption(String raw) {
    final n = QuizBankTextNormalizer.normalizeOption(raw);
    if (n.isEmpty) return false;
    return RegExp(r'^图\s*\d+$').hasMatch(n) ||
        RegExp(r'^图[一二三四五六七八九十]+$').hasMatch(n) ||
        RegExp(r'^图片\d*$').hasMatch(n) ||
        n == '如图' ||
        n == '见图';
  }

  bool _isImageLikeAnswer(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;
    final n = QuizBankTextNormalizer.normalizeOption(
      t.replaceFirst(RegExp(r'^[A-Ha-h][.、．:：)\s]*'), ''),
    );
    return _isImageLikeOption(n) ||
        RegExp(r'^[答案：:\s]*[A-Ha-h][.、．:：)\s]*图\s*\d+').hasMatch(t);
  }

  bool _isImageLikeOptionSet(List<String> options) {
    final cleaned = options.map((e) => e.trim()).where((e) => e.isNotEmpty);
    if (cleaned.isEmpty) return false;
    final imageCount = cleaned.where(_isImageLikeOption).length;
    return imageCount >= max(1, (cleaned.length + 1) ~/ 2);
  }

  bool _isTextLikeOptionSet(List<String> options) {
    final cleaned = options
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (cleaned.length < 2) return false;
    if (_isImageLikeOptionSet(cleaned)) return false;
    final avgLen =
        cleaned
            .map((e) => QuizBankTextNormalizer.normalizeOption(e).length)
            .fold<int>(0, (a, b) => a + b) /
        cleaned.length;
    return avgLen >= 6;
  }

  bool _optionShapeConflict(
    bool probeImageLike,
    bool probeTextLike,
    List<String> bankOptions,
  ) {
    if (bankOptions.isEmpty) return false;
    final bankImage = _isImageLikeOptionSet(bankOptions);
    final bankText = _isTextLikeOptionSet(bankOptions);
    if (probeTextLike && bankImage) return true;
    if (probeImageLike && bankText) return true;
    return false;
  }

  int _questionScore(String hay, String target) {
    if (hay == target) return 100;
    if (target.contains(hay) || hay.contains(target)) {
      final shorter = min(hay.length, target.length);
      final longer = max(hay.length, target.length);
      return longer == 0 ? 0 : (72 + shorter / longer * 24).round();
    }
    return _similarityScore(hay, target);
  }

  /// 试捕选项 vs 题库选项：交集占比 + 逐项最优相似度。
  int _optionsScore(Set<String> probeNorm, List<String> bankOptions) {
    if (probeNorm.isEmpty) return 0;
    final bankNorm = bankOptions
        .map(QuizBankTextNormalizer.normalizeOption)
        .where((e) => e.isNotEmpty)
        .toList();
    if (bankNorm.isEmpty) return 0;

    // 图选题 vs 文字题：直接 0 分，避免字符级噪声凑分
    if (_isImageLikeOptionSet(bankOptions) &&
        probeNorm.every((e) => !_isImageLikeOption(e))) {
      return 0;
    }
    if (!_isImageLikeOptionSet(bankOptions) &&
        probeNorm.every(_isImageLikeOption)) {
      return 0;
    }

    final bankSet = bankNorm.toSet();
    final inter = probeNorm.intersection(bankSet).length;
    final exactRatio = inter / max(probeNorm.length, bankSet.length);
    final exactScore = (exactRatio * 100).round();

    var softSum = 0;
    for (final p in probeNorm) {
      var best = 0;
      for (final b in bankNorm) {
        final s = _similarityScore(p, b);
        if (s > best) best = s;
      }
      softSum += best;
    }
    final softScore = softSum ~/ probeNorm.length;

    if (probeNorm.length == bankSet.length && inter == probeNorm.length) {
      return 100;
    }
    return max(exactScore, softScore);
  }

  String _formatBankAnswer(
    QuizBankItem item,
    int score, {
    int questionScore = 0,
    int optionsScore = 0,
    bool hasProbeOptions = false,
    bool optionTieBreak = false,
    String displayAnswer = '',
    bool aligned = true,
    String alignmentMethod = '',
  }) {
    final answerText = displayAnswer.trim().isNotEmpty
        ? displayAnswer.trim()
        : _resolveCorrectAnswerText(item);
    final simLine = optionTieBreak
        ? '相似度：$score%（题干优先 · 选项决胜 $optionsScore%）'
        : hasProbeOptions
        ? '相似度：$score%（题干$questionScore%）'
        : '相似度：$score%';
    final alignLine = !aligned && hasProbeOptions
        ? '对齐：未匹配到卷面选项（题库原文）'
        : (aligned &&
              (alignmentMethod == 'synonym' || alignmentMethod == 'similarity'))
        ? '对齐：已映射到卷面选项'
        : null;
    final lines = <String>[
      '匹配题目：${item.question}',
      if (answerText.isNotEmpty) '答案：$answerText',
      if (item.options.isNotEmpty) '选项：\n${item.options.join('\n')}',
      if ((item.analysis ?? '').trim().isNotEmpty) '解析：${item.analysis}',
      ?alignLine,
      simLine,
    ];
    return lines.join('\n');
  }

  String _resolveCorrectAnswerText(QuizBankItem item) {
    final alignment = QuizAnswerAligner.align(
      bankAnswer: item.correctAnswer,
      bankOptions: item.options,
    );
    if (alignment.displayAnswer.isNotEmpty) return alignment.displayAnswer;
    return item.correctAnswer.trim();
  }

  int _similarityScore(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final lcs = _longestCommonSubsequenceLength(a, b);
    final lcsScore = (lcs * 200 / (a.length + b.length)).round();
    final setA = a.split('').toSet();
    final setB = b.split('').toSet();
    final union = setA.union(setB).length;
    final inter = setA.intersection(setB).length;
    final jaccard = union == 0 ? 0 : (inter * 100 / union).round();
    // 字符集合重叠容易把“机动车/道路/正确/错误”等通用词误判，作为弱信号限幅。
    return max(lcsScore, min(jaccard, 72));
  }

  int _longestCommonSubsequenceLength(String a, String b) {
    final previous = List<int>.filled(b.length + 1, 0);
    final current = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        current[j] = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1)
            ? previous[j - 1] + 1
            : max(previous[j], current[j - 1]);
      }
      for (var j = 0; j <= b.length; j++) {
        previous[j] = current[j];
        current[j] = 0;
      }
    }
    return previous[b.length];
  }

  Future<QuizResult> _searchCustomApi(String question) async {
    final uri = Uri.parse(config.apiUrl).replace(
      queryParameters: {
        'question': question,
        if (config.apiKey.isNotEmpty) 'key': config.apiKey,
      },
    );

    final response = await http.get(uri).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      return QuizResult(
        question: question,
        error: 'API 返回 ${response.statusCode}',
      );
    }

    final body = jsonDecode(response.body);
    final answers = <QuizAnswer>[];

    if (body is Map) {
      final data = body['data'] ?? body['result'] ?? body['answer'];
      if (data is List) {
        for (final item in data) {
          if (item is Map) {
            final text =
                (item['answer'] ?? item['text'] ?? item['content'] ?? '')
                    .toString();
            final conf = (item['confidence'] as num?)?.toDouble() ?? 0.0;
            if (text.isNotEmpty) {
              answers.add(
                QuizAnswer(text: text, confidence: conf, source: 'API'),
              );
            }
          } else {
            answers.add(QuizAnswer(text: item.toString(), source: 'API'));
          }
        }
      } else if (data is String && data.isNotEmpty) {
        answers.add(QuizAnswer(text: data, source: 'API'));
      } else if (body['answer'] is String) {
        answers.add(QuizAnswer(text: body['answer'] as String, source: 'API'));
      }
    }

    return QuizResult(
      question: question,
      answers: answers,
      error: answers.isEmpty ? '未解析到答案' : null,
    );
  }

  Future<QuizResult> _searchBuiltIn(String question) async {
    const apis = [
      'https://api.oioweb.cn/api/ti',
      'https://api.66mz8.com/api/ti.php',
    ];

    for (final api in apis) {
      try {
        final uri = Uri.parse(
          api,
        ).replace(queryParameters: {'question': question, 'type': 'json'});
        final response = await http
            .get(uri, headers: {'User-Agent': 'Mozilla/5.0'})
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final answers = _parseBuiltInResponse(response.body);
          if (answers.isNotEmpty) {
            return QuizResult(
              question: question,
              answers: answers,
              error: null,
            );
          }
        }
      } catch (_) {
        continue;
      }
    }

    return QuizResult(question: question, error: '内置搜题无结果');
  }

  List<QuizAnswer> _parseBuiltInResponse(String body) {
    final answers = <QuizAnswer>[];
    try {
      final json = jsonDecode(body);
      if (json is Map) {
        for (final key in [
          'data',
          'result',
          'answer',
          'msg',
          'text',
          'content',
        ]) {
          final val = json[key];
          if (val is String && val.isNotEmpty) {
            for (final line in val.split('\n')) {
              final trimmed = line.trim();
              if (trimmed.isNotEmpty) {
                answers.add(
                  QuizAnswer(
                    text: trimmed,
                    source: '内置',
                    confidence: answers.isEmpty ? 0.9 : 0.5,
                  ),
                );
              }
            }
            if (answers.isNotEmpty) break;
          }
        }
        final data = json['data'];
        if (answers.isEmpty && data is Map) {
          for (final key in ['answer', 'result', 'text']) {
            final val = data[key];
            if (val is String && val.isNotEmpty) {
              answers.add(QuizAnswer(text: val, source: '内置', confidence: 0.8));
              break;
            }
          }
        }
      } else if (json is List) {
        for (final item in json) {
          if (item is String && item.isNotEmpty) {
            answers.add(QuizAnswer(text: item, source: '内置'));
          } else if (item is Map) {
            final text =
                (item['answer'] ?? item['text'] ?? item['content'] ?? '')
                    .toString();
            if (text.isNotEmpty) {
              answers.add(QuizAnswer(text: text, source: '内置'));
            }
          }
        }
      }
    } catch (_) {
      final lines = body
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && l.length > 2)
          .toList();
      if (lines.isNotEmpty) {
        answers.addAll(lines.map((l) => QuizAnswer(text: l, source: '内置')));
      }
    }
    return answers;
  }
}
