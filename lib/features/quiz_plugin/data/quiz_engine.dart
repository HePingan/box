import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../domain/quiz_config.dart';
import '../domain/quiz_bank.dart';
import '../domain/ocr_quiz_parser.dart';
import '../domain/quiz_answer_aligner.dart';
import '../domain/quiz_match_scoring.dart';

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
    this.imageMatchHint = '',
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

  /// 题图消歧诊断：用于解释同题干多候选为何需要确认。
  final String imageMatchHint;
}

class QuizEngine {
  QuizEngine({required this.config});

  QuizConfig config;

  Future<QuizResult> search(
    String question, {
    bool forceExternalSearch = false,
    List<String> probeOptions = const [],
    String? imagePerceptualHash,
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
          imagePerceptualHash: imagePerceptualHash,
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
    String? imagePerceptualHash,
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
            int imageScore,
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
      // 判断题（卷面与题库都只有 2 个选项）改用选项优先加权。
      //
      // 原因：引擎里多处「选项已足够消歧」的快捷路径门槛都是
      // probeOptNorm.length >= 3，判断题整类被排除，只能吃 55/45 加权。
      // 但对判断题而言选项匹配才是最强信号（只有正确/错误两种可能，
      // 对上就是对上了），题干相似度反而最容易被 OCR 噪声污染
      // （屏幕噪声字符、错别字、长题干稀释）。55/45 下 oScore 满分时
      // 仍要求 qScore >= 45，导致「唯一命中却提示请人工确认」。
      //
      // 只在两侧选项数都为 2 且选项高度匹配时生效，选择题完全不受影响。
      final judgmentOptionFirst = QuizMatchScoring.judgmentOptionFirst(
        useOptions: useOptions,
        probeOptionCount: probeOptNorm.length,
        bankOptionCount: bankOptionCount,
        optionScore: oScore,
      );
      final baseScore = QuizMatchScoring.baseScore(
        useOptions: useOptions,
        questionScore: e.qScore,
        optionScore: oScore,
        shapeBonus: shapeBonus,
        optionFirst: judgmentOptionFirst,
      );
      final score = QuizMatchScoring.finalScore(
        base: baseScore,
        hasCompleteProbeOptions: hasCompleteProbeOptions,
        questionScore: e.qScore,
        optionScore: oScore,
      );
      final imageScore = _bestImageScore(imagePerceptualHash, e.item);
      scored.add((
        item: e.item,
        score: score.clamp(0, 100),
        qScore: e.qScore,
        oScore: oScore,
        shapeBonus: shapeBonus,
        imageScore: imageScore,
      ));
    }

    scored.sort((a, b) {
      // 同题干/同选项的候选若均有截图 dHash，先按视觉一致性消歧。
      // -1 代表本次或题库记录没有可用 hash，保留历史文字排序以兼容存量。
      if (a.imageScore >= 0 &&
          b.imageScore >= 0 &&
          a.imageScore != b.imageScore) {
        return b.imageScore.compareTo(a.imageScore);
      }
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

    final hasProbeImageHash = _isValidDHash(imagePerceptualHash);
    var imageMatchHint = '';
    // 图片消歧只在同题干多候选时启用，并且只接受同一题图区域产生的 hash。
    if (scored.length > 1 && hasProbeImageHash) {
      // 只有题库真实保存的题图区域 hash 才能证明区域消歧可用。
      // imageScore 也可能来自旧版整题 hash 回退，后者仅用于兼容排序，不能据此
      // 指责用户框选错误，或宣称题图消歧已经成功。
      final withRegion = scored
          .where((entry) => _isValidDHash(entry.item.imageRegionHash))
          .toList();
      if (withRegion.isEmpty) {
        imageMatchHint = '题库题图指纹缺失，请重新录入题图';
      } else {
        final bestImageScore = withRegion
            .map((entry) => entry.imageScore)
            .reduce((a, b) => a > b ? a : b);
        // dHash 相似度满分为 64。屏幕框选通常会比题库参考图多一点
        // UI 留白，不能只依赖 48 分绝对门槛；但也不能无限降阈值。
        // 低于绝对门槛时，要求至少 40 分且比第二名高 8 分，才把它当作
        // 有证据的相对消歧。旧整题 hash 回退不参与此判断。
        final regionScores =
            withRegion.map((entry) => entry.imageScore).toList()
              ..sort((a, b) => b.compareTo(a));
        final secondImageScore = regionScores.length > 1 ? regionScores[1] : -1;
        final imageFloor = bestImageScore >= 75
            ? max(75, bestImageScore - 12)
            : bestImageScore - 12;
        // 自动收敛必须有明确领先；仅分数高但彼此接近时保留候选确认，
        // 防止交通标志等同色同轮廓题被错误自动作答。
        final hasClearVisualWinner =
            bestImageScore >= 75 &&
            (secondImageScore < 0 || bestImageScore - secondImageScore >= 12);
        if (hasClearVisualWinner) {
          final imageFiltered = withRegion
              .where((entry) => entry.imageScore >= imageFloor)
              .toList();
          if (imageFiltered.isNotEmpty) {
            scored
              ..clear()
              ..addAll(imageFiltered);
            imageMatchHint = '题图消歧已启用';
          }
        } else {
          // 至少一个候选确有 region hash，但探针与它们都不匹配，才提示检查框选区域。
          imageMatchHint = '题图匹配不足：请确认框选的是完整题图';
        }
      }
    } else if (scored.length > 1) {
      // 多候选且本次也没有捕获图片指纹
      imageMatchHint = '题干选项相同，题图未参与匹配';
    }
    // C2: 候选答案清单不在此处拼接。此时的 scored 仍是宽松的同题干池，
    // 含选项集完全不同的变体（如「环形交叉路口预告」），后面会被完整选项过滤淘汰。
    // 清单统一在最终 selected 确定后再生成，避免把已淘汰变体展示给用户。

    // ④ 选项分消歧：最优候选选项分 ≥75 且与次优差距 ≥35，且卷面已有 ≥3 个完整选项时，
    //    选项本身已足够消歧，直接收敛为唯一候选，不再依赖图片指纹，也不触发 ambiguous 确认。
    if (scored.length > 1 &&
        useOptions &&
        probeOptNorm.length >= 3 &&
        scored[0].oScore >= 75 &&
        (scored[0].oScore - scored[1].oScore) >= 35) {
      final optWinner = scored[0];
      scored
        ..clear()
        ..add(optWinner);
      imageMatchHint = '';
    }

    // 新增：选项完全匹配且所有候选答案相同时，清除"题图匹配不足"提示
    // 适用场景：同一题的多个录入（答案相同，仅题图区域框选不同），用户实际框选了正确区域，
    // 但由于录入时的框选差异导致 dHash 分数不高。这时答案已确定，不应再要求用户检查框选。
    if (scored.length > 1 &&
        useOptions &&
        probeOptNorm.length >= 3 &&
        scored.every((e) => e.oScore >= 90)) {
      final answers = scored.map((e) => e.item.correctAnswer).toSet();
      if (answers.length == 1) {
        // 所有候选答案相同，选项分数都很高，清除"题图匹配不足"提示
        imageMatchHint = '';
      }
    }

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

    // 最终展示只能来自已通过完整选项过滤的变体。视觉状态不可在这里
    // 无差别清空：强模板/向量命中需要保留可审计诊断；低证据则必须把
    // 最终竞争答案交给悬浮窗确认，绝不能仅按排序第一条自动作答。
    if (hasExactCompleteVariant && selected.length == 1) {
      if (imageMatchHint.contains('题图匹配不足') ||
          imageMatchHint.contains('视觉模板相似') ||
          imageMatchHint.contains('视觉向量相似')) {
        imageMatchHint = '';
      }
    } else if (selected.length > 1) {
      final hintBase = imageMatchHint.split('\n候选答案：').first.trim();
      final finalSummary = _competingAnswerSummary(selected);
      imageMatchHint = finalSummary.isEmpty
          ? hintBase
          : hintBase.isEmpty
          ? finalSummary
          : '$hintBase\n$finalSummary';
    }

    // 配置的 bankMaxMatches 可限制常规匹配数量；但视觉/文字未收敛时，
    // 绝不能把多个真实竞争答案再截成第一条，否则悬浮窗会把排序结果误作
    // 确定答案。至少返回两条不同答案以触发确认态。
    final competingAnswerCount = selected
        .map(
          (entry) =>
              QuizBankTextNormalizer.normalizeOption(entry.item.correctAnswer),
        )
        .where((answer) => answer.isNotEmpty)
        .toSet()
        .length;
    final effectiveLimit = competingAnswerCount > 1
        ? max(config.bankMaxMatches, 2)
        : config.bankMaxMatches;
    final top = selected.take(effectiveLimit).toList();
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
            imageMatchHint: imageMatchHint,
          );
        })
        .whereType<QuizAnswer>()
        .toList();
    if (mapped.isEmpty) return null;
    return mapped;
  }

  int _dHashSimilarity(String? probeHash, String? bankHash) {
    final probe = probeHash?.trim().toLowerCase() ?? '';
    final bank = bankHash?.trim().toLowerCase() ?? '';
    // Android 原生当前产出 64 bit / 16 个十六进制字符；格式不完整时不参与排序。
    if (!RegExp(r'^[0-9a-f]{16}$').hasMatch(probe) ||
        !RegExp(r'^[0-9a-f]{16}$').hasMatch(bank)) {
      return -1;
    }
    var distance = 0;
    for (var i = 0; i < probe.length; i++) {
      final diff =
          int.parse(probe[i], radix: 16) ^ int.parse(bank[i], radix: 16);
      distance += diff.bitLength == 0 ? 0 : _popCount(diff);
    }
    return 64 - distance;
  }

  /// B1: 优先用题图区域 hash（imageRegionHash）比对；存量题回退到整题 hash。
  ///
  /// 探针（probe）来自独立框选的题图区域，精度远高于整题截图。
  /// 只要题库侧有 imageRegionHash，就只比 region；
  /// 若题库侧只有旧的整题 hash，则回退，但分数最高只取 imageScore 的 80%
  /// （打折反映整块 dHash 区分度较低，避免用低质量分数压掉文字匹配结果）。
  /// C2: 题图消歧失败时列出竞争候选的答案，让用户能自己核对选哪个。
  /// 只在候选答案确实不同时才有意义——答案一样的话选哪个都对，不必打扰用户。
  String _competingAnswerSummary(
    List<
      ({
        QuizBankItem item,
        int score,
        int qScore,
        int oScore,
        int shapeBonus,
        int imageScore,
      })
    >
    scored,
  ) {
    final seen = <String>{};
    final answers = <String>[];
    for (final entry in scored.take(4)) {
      final answer = entry.item.correctAnswer.trim();
      if (answer.isEmpty) continue;
      final key = QuizBankTextNormalizer.normalizeOption(answer);
      if (key.isEmpty || !seen.add(key)) continue;
      answers.add(answer.length > 24 ? '${answer.substring(0, 24)}…' : answer);
    }
    // 全部候选答案一致：无需让用户选择。
    if (answers.length < 2) return '';
    return '候选答案：${answers.join(' / ')}';
  }

  int _bestImageScore(String? probeHash, QuizBankItem item) {
    if (!_isValidDHash(probeHash)) return -1;
    final regionScore = _dHashSimilarity(probeHash, item.imageRegionHash);
    if (regionScore >= 0) return (regionScore * 100 / 64).round();
    return -1;
  }

  bool _isValidDHash(String? value) =>
      RegExp(r'^[0-9a-f]{16}$').hasMatch(value?.trim().toLowerCase() ?? '');

  int _popCount(int value) {
    var n = value;
    var count = 0;
    while (n != 0) {
      count += n & 1;
      n >>= 1;
    }
    return count;
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
