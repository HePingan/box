import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../utils/app_logger.dart';
import '../domain/quiz_config.dart';
import '../domain/quiz_bank.dart';
import '../domain/ocr_quiz_parser.dart';
import '../domain/quiz_answer_aligner.dart';
import '../domain/quiz_diag.dart';
import '../domain/quiz_vision_endpoint.dart';
import '../domain/quiz_match_scoring.dart';
import '../utils/ai_process_bridge.dart';

class QuizResult {
  const QuizResult({
    required this.question,
    this.answers = const [],
    this.error,
    this.elapsedMs = 0,
    this.source = '',
    this.imageUrl,
    this.stemExplosion = false,
    this.stemExplosionCount = 0,
  });

  final String question;
  final List<QuizAnswer> answers;
  final String? error;
  final int elapsedMs;
  final String source;
  final String? imageUrl;

  /// 同题干候选爆炸（题干无区分度、疑似标志图题）。
  ///
  /// 真机证据：题库中「这个标志是何含义？」独占 243 条、220 种互斥答案，
  /// 题干 qScore 全员满分导致题干维度失效，选项又对不上（标志题答案只在图里），
  /// 此时返回任意候选都是在误导用户。上层据此显示「请对照题图作答」，
  /// 而不是端出「陡坡路段」这类随机候选。
  final bool stemExplosion;
  final int stemExplosionCount;

  QuizResult copyWith({
    String? question,
    List<QuizAnswer>? answers,
    String? error,
    int? elapsedMs,
    String? source,
    String? imageUrl,
    bool? stemExplosion,
    int? stemExplosionCount,
  }) {
    return QuizResult(
      question: question ?? this.question,
      answers: answers ?? this.answers,
      error: error ?? this.error,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      source: source ?? this.source,
      imageUrl: imageUrl ?? this.imageUrl,
      stemExplosion: stemExplosion ?? this.stemExplosion,
      stemExplosionCount: stemExplosionCount ?? this.stemExplosionCount,
    );
  }

  bool get isSuccess => error == null && answers.isNotEmpty;
}

/// 从模型读屏输出的散文/JSON 混合文本中提取结构化答案。
///
/// 实测（2026-09-13，NewAPI 渠道 `deepseek`；2026-09-19 切换 `gemini-3-8-flash`
/// 后输出形态同样不稳定）模型输出有三种形态，解析器对全兼容：
///   1. 纯 JSON：`{"stem":...}`
///   2. ```json 围栏包裹
///   3. Markdown 散文（`## 分析` 之类标题）后跟 JSON
/// 故按「围栏 → 首个 JSON 对象」顺序宽松提取；**提取不到一律返回 null**，
/// 由调用方转为明确错误，绝不猜测答案。
Map<String, dynamic>? parseVisionJson(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return null;
  // 1) ```json ... ``` 围栏
  final fenced = RegExp(r'```(?:json)?\s*(\{[\s\S]*?\})\s*```');
  final m1 = fenced.firstMatch(trimmed);
  if (m1 != null) {
    final parsed = _tryDecodeJsonMap(m1.group(1)!);
    if (parsed != null) return parsed;
  }
  // 2) 首个完整 JSON 对象（贪婪失败则退回最长匹配）
  for (final m in RegExp(r'\{[\s\S]*\}').allMatches(trimmed)) {
    final parsed = _tryDecodeJsonMap(m.group(0)!);
    if (parsed != null) return parsed;
  }
  return null;
}

Map<String, dynamic>? _tryDecodeJsonMap(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
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

  /// `_searchBank` 的 out 参数：>0 表示触发了「同题干候选爆炸」护栏。
  /// `search()` 在调用后立即读取并转化为对用户可见的提示。
  int _lastStemExplosionCount = 0;

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
        _lastStemExplosionCount = 0;
        final bankResult = await _searchBank(
          trimmed,
          probeOptions: probeOptions,
          imagePerceptualHash: imagePerceptualHash,
        );
        if (_lastStemExplosionCount > 0) {
          // 同题干候选爆炸：题干无区分度（如题库中「这个标志是何含义？」独占 243 条、
          // 220 种互斥答案），此时任何候选都是随机误导，必须显式告诉用户看图作答。
          return QuizResult(
            question: question,
            error: '该题为图标题，请对照题图作答（同题干 $_lastStemExplosionCount 条，无法区分）',
            elapsedMs: stopwatch.elapsedMilliseconds,
            source: '本地题库',
            stemExplosion: true,
            stemExplosionCount: _lastStemExplosionCount,
          );
        }
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
    if (candidates.isEmpty) {
      // 诊断：区分「本地库为空/未同步完」与「库里有但召回为空」。
      // 前者是同步问题（题库页看覆盖率），后者是分词/归一化问题。
      //
      // 必须同时进 AppLogger——报障人看到的悬浮窗提示就是这句
      // 「本地题库未找到」，他在调试日志页搜「未找到」「bankSize」
      // 时要能搜到这一条，否则又是一轮「我找不到那个」。
      final bankSize = QuizBankCache.instance.items.length;
      final stem = hay.length > 40 ? '${hay.substring(0, 40)}…' : hay;
      AppLogger.instance.logTo(
        LogChannel.quiz,
        'no candidate: bankSize=$bankSize hay="$stem"',
        level: LogLevel.warn,
      );
      debugPrint('[QuizEngine] no candidate: bankSize=$bankSize hay="$stem"');
      return null;
    }

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
    QuizDiag.log(
      QuizDiagStage.match,
      'candidates scored',
      fields: {
        'cand': candidates.length,
        'passed': byQuestion.length,
        'bestQ': byQuestion.map((e) => e.qScore).reduce(max),
      },
    );

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
      // 权重是**连续**的（80→90 线性过渡），因为此前 89→90 的硬开关
      // 会让最终分跳 14~22 分，跨过 0.70 阈值造成真机误报。
      final judgmentOptionFirstWeight =
          QuizMatchScoring.judgmentOptionFirstWeightGated(
        useOptions: useOptions,
        probeOptionCount: probeOptNorm.length,
        bankOptionCount: bankOptionCount,
        optionScore: oScore,
        questionScore: e.qScore,
      );
      final baseScore = QuizMatchScoring.baseScoreWeighted(
        useOptions: useOptions,
        questionScore: e.qScore,
        optionScore: oScore,
        shapeBonus: shapeBonus,
        optionFirstWeight: judgmentOptionFirstWeight,
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
      // 逐候选真实打分。真机报「请人工确认」时，日志页可搜 `score=` 看到
      // 每个候选的真实 qScore/oScore/final 与选项优先权重，
      // 用于判断是「题干分低」还是「选项分掉下 90」还是「阈值本身」。
      QuizDiag.log(
        QuizDiagStage.match,
        'score=${score.clamp(0, 100)}',
        fields: {
          'q': e.qScore,
          'o': oScore,
          'w': judgmentOptionFirstWeight.toStringAsFixed(2),
          'base': baseScore,
          'shape': shapeBonus,
          'img': imageScore,
          'qid': e.item.id,
        },
        level: QuizMatchScoring.isLowConfidence(score.clamp(0, 100))
            ? LogLevel.warn
            : LogLevel.info,
      );
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

    // ④ 同题干爆炸护栏：题干无区分度时，禁止把互斥答案当候选端出去。
    //
    // 真机证据（2026-09-13 12:43，App 1.18.16 (239)）：
    //   PARSE qLen=9 opts=4 q="这个标志是何含义？"
    //   MATCH candidates scored cand=243 passed=243 bestQ=100
    //   → 悬浮窗端出「候选 1：提醒车辆驾驶人前方有向上的陡坡路段」等无关答案
    //
    // 真实题库 3616 条中「这个标志是何含义？」独占 243 条（220 种互斥答案，仅 4 条有图）。
    // 题干逐字相同 → 全员 qScore=100 → 题干维度完全失效；而标志题的答案**只在图里**，
    // 选项是「T形交叉路口 / 下陡坡 / 右侧通行」这种按图而异的文字，卷面 OCR 通常只抓到
    // 1~2 个（真机即 probeOptNorm.length < 3），选项消歧快捷路径全部跳过。
    // 此时若仍返回 top 候选，用户看到的必然是**分数靠前的随机答案**，且极易被误当作
    // 系统已确认的答案 —— 这是比「未命中」严重得多的误导。
    //
    // 判据（两个条件同时成立才生效，避免误伤正常题）：
    //   ① 同题干候选数量 >= stemExplosionThreshold（题干几乎无区分度）；
    //   ② 最优候选不足以唯一决胜：要么选项分过低（< stemExplosionMinOptionScore），
    //      要么存在**多个并列最高分且答案互斥**（分不出赢家）。
    // 满足则视为标志图题：不返回候选，由上层提示对照题图作答。
    //
    // 【为什么②要加「并列最高分」这一支】
    // 真机证据（2026-09-13 13:32，App 1.18.17）：
    //   题「驾驶电动汽车，图中指示灯亮起表示（ ）。」答案=充电系统故障
    //   卷面 A正在充电 B动力蓄电池故障 C低荷电状态警告 D充电系统故障
    //   → 题库该题干共 9 条 / 9 种互斥答案，其中 4 条选项集与卷面**完全相同**
    //   → 4 条并列 100 分，bestO=100 不满足旧条件①的 <60 → 旧护栏漏过
    //   → 端出「候选1：减速慢行信号 / 候选2：变道信号」这类毫不相关的答案。
    // 同理还有「这个标志是什么含义？」17 条、「图中交通标志是指（ ）」16 条、
    // 「机动车仪表板上如图所示指示灯亮表示什么？」14 条等一大票图题，
    // 条数在 9~17 档，全部被「>=60 条」的旧阈值漏掉。
    // 因此把判据从「条数极大」修正为「**分不出唯一赢家**」——这才是真正的失配信号。
    //
    // 不误伤的保证：正常题（含「限速」超过/高于/低于这类多变体）卷面选项能对齐时，
    // 最高分候选唯一且明显高于次席（gap 大）→ ②不成立 → 不受影响。
    // 调参方向：stemExplosionMinWinGap 调大→更激进（并列更宽也拒绝）；调小→更保守。
    const stemExplosionThreshold = 8;
    const stemExplosionMinOptionScore = 60;
    const stemExplosionMinWinGap = 8;

    // 并列最高分检测：取最高分，统计与它相差 < gap 的候选里有多少种互斥答案。
    final topScore = scored.first.score;
    final topAnswers = <String>{};
    for (final c in scored) {
      if (topScore - c.score >= stemExplosionMinWinGap) break;
      final a = c.item.correctAnswer.trim();
      if (a.isNotEmpty) topAnswers.add(a);
    }
    final noUniqueWinner = topAnswers.length > 1;
    final weakOptions = scored.first.oScore < stemExplosionMinOptionScore;

    if (scored.length >= stemExplosionThreshold &&
        (weakOptions || noUniqueWinner) &&
        !hasProbeImageHash) {
      QuizDiag.warn(
        QuizDiagStage.match,
        '拒绝：同题干候选爆炸（疑似标志图题），不端候选答案',
        fields: {
          'cand': scored.length,
          'bestQ': scored.first.qScore,
          'bestO': scored.first.oScore,
          'tieAnswers': topAnswers.length,
          'probeOpts': probeOptNorm.length,
        },
      );
      AppLogger.instance.logTo(
        LogChannel.quiz,
        'MATCH REJECT stemExplosion cand=${scored.length} '
            'bestQ=${scored.first.qScore} bestO=${scored.first.oScore} '
            'probeOpts=${probeOptNorm.length} —— 题干无区分度，需对照题图',
        level: LogLevel.warn,
      );
      // 返回空列表 + out 参数标记 stemExplosion：上层据此显示
      // 「该题为图标题，请对照题图作答」，而不是把 220 种互斥答案中的某一条端给用户。
      _lastStemExplosionCount = scored.length;
      return const [];
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
        QuizDiag.warn(QuizDiagStage.match, '拒绝：卷面选项全部对不上题库',
            fields: {'probeOpts': probeOptNorm.length, 'cand': scored.length});
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
      QuizDiag.warn(QuizDiagStage.match, '拒绝：低于最终闸门',
          fields: {
            'top': top.length,
            'q': top.isEmpty ? '-' : top.first.qScore,
            'o': top.isEmpty ? '-' : top.first.oScore,
          });
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
      QuizDiag.warn(QuizDiagStage.match, '拒绝：非看图题却命中「图N」答案');
      return null;
    }
    // 卷面文字题却只命中图选题答案（图1/图2）：当作未命中，避免误导
    if (_isImageLikeAnswer(top.first.item.correctAnswer) &&
        (probeTextLike ||
            (!_isImageLikeOptionSet(top.first.item.options) && useOptions))) {
      // keep if bank options themselves are image and probe also image
      if (!(probeImageLike && _isImageLikeOptionSet(top.first.item.options))) {
        if (useOptions && top.first.oScore < 80) {
          QuizDiag.warn(QuizDiagStage.match,
              '拒绝：文字题命中图选答案且选项分偏低',
              fields: {'o': top.first.oScore});
          return null;
        }
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
    // 命中现场：这条日志和上面的「拒绝」日志成对出现，一眼能看出
    // 这一题是「根本没进到打分」还是「打分后被某个闸门拒了」。
    QuizDiag.log(
      QuizDiagStage.match,
      'HIT',
      fields: {
        'n': mapped.length,
        'score': mapped.first.confidence,
      },
    );
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

  /// 外部「AI 读屏」搜题的模型名。
  ///
  /// 固定 `deepseek`：NewAPI 渠道（https://newapi.hpa888.top/v1）的 /models
  /// 只暴露这一个 ID，真实上游模型被渠道名掩盖（实测返回 model 字段为
  /// "Deepseek"，能力等价 deepseek-v4-vision）。
  /// 2026-09-19 用户拍板：box 项目识图维持原 deepseek；gemini-3.8 仅用于
  /// Hermes 辅助视觉（vision_analyze），不混入 box 客户端。
  static const String visionModel = 'deepseek';
  /// 实测（2026-09-13，NewAPI 渠道 `deepseek`）模型输出形态不稳定，
  /// 三种都出现：纯 JSON / ```json 围栏 / Markdown 散文后跟 JSON，
  /// 解析器对全兼容；**提取不到一律返回 null**（不编造答案）。

  /// 方案丙提示词：要求模型**独立作答**，明确禁止参考界面上已选的答案。
  ///
  /// 为什么必须写死这段约束：截图里往往带着用户已选的选项（对勾/高亮），
  /// 模型天然倾向「复述界面」。实测（2026-09-13）两题上模型确实给出了
  /// 独立判断（confidence 0.98/0.9），但**尚无「用户选错」的反例证伪**，
  /// 因此这里用最强约束把「照抄界面」的道路堵死。
  static const String visionPrompt = '你是机动车驾驶人考试（科目一/科目四）答题专家。\n'
      '\n'
      '请阅读这张手机截图，完成以下任务：\n'
      '1. 逐字提取题干原文（去掉 App 界面上的无关文字，如"收藏""交卷""VIP""张老师"等）\n'
      '2. 提取所有选项原文\n'
      '3. 独立给出正确答案\n'
      '\n'
      '【重要】不要参考截图中用户已选的答案或界面显示的答案标记，你必须自己独立判断正确答案。\n'
      '【重要】只输出 JSON，不要输出任何其他解释文字。JSON 格式：\n'
      '{"stem":"题干原文","options":["A. xxx","B. xxx"],"answer":"A","confidence":0.95}\n'
      '\n'
      // ⚠️ 实测（2026-09-13）该上游渠道对「像真题的复杂截图」会钻进代码解释器：
      // finish_reason=tool_calls、content=null，reasoning 里在联网抓别的图片、
      // 跑 numpy，单次 30s+ 且必然拿不到答案。下面这段是最强约束，用于堵死
      // 「调用工具」这条路 —— 明确告知：你只能看图、必须一次给出答案。
      '【绝对禁止】禁止调用任何工具、函数、代码解释器、联网检索、外部链接。\n'
      '你没有任何工具可用。你唯一的能力就是"直接看这张图"。\n'
      '【禁止】禁止分批、禁止"先分析再看下一块"、禁止输出思考过程或计划。\n'
      '【必须】看完图后立刻一次性输出上述 JSON，第一个字符就是 {。';

  /// 外部「AI 读屏」搜题（B 档）。
  ///
  /// 链路：截图 bytes → base64 内联 → OpenAI 兼容 POST /chat/completions
  ///       → 解析结构化 JSON → QuizResult(source: 'AI读屏')。
  ///
  /// 只对**本地题库未命中**的题调用（用户 2026-09-13 拍板"所有本地未命中的题"）。
  ///
  /// 兜底策略（全部来自真实实测，非臆测）：
  ///   - 503 `system_cpu_overloaded` / 429 / 500 → 指数退避重试（实测退避后成功）
  ///   - 总超时 45s（实测读大图单次 3~15s，15s 上限不够）
  ///   - 解析失败 → 返回 error，**绝不编造答案**
  Future<QuizResult> searchVisionApi(
    Uint8List imageBytes, {
    String? hintQuestion,
  }) async {
    final stopwatch = Stopwatch()..start();
    final question = (hintQuestion ?? '').trim();
    if (imageBytes.isEmpty) {
      return QuizResult(question: question, error: '读屏截图为空');
    }
    if (config.apiUrl.trim().isEmpty) {
      return QuizResult(question: question, error: '未配置 API 地址');
    }

    // 压缩：手机截图常 1~3MB，base64 再膨胀 33%，不压会显著拉长延迟。
    // 注意：_compressForVision 输出的是 PNG（dart:ui 无 JPEG 编码器）。
    final compressed = await _compressForVision(imageBytes);
    final b64 = base64Encode(compressed);

    // ── AI 搜题诊断日志（用户 2026-09-13 要求「把 AI 搜题过程写入调试日志，
    //    我分析一下」）。落在 LogChannel.quiz，可在 抽屉→更多→调试日志→题库 查。
    //    只记**尺寸/字节数/耗时/结论**，不记图片内容与 API Key，避免泄露。
    final tag = 'VISION#${DateTime.now().millisecondsSinceEpoch % 100000}';
    _visionLog(
      '$tag ▶ 开始 model=$visionModel '
      '原图=${imageBytes.length}B 压缩后=${compressed.length}B '
      'b64=${b64.length}B prompt=${visionPrompt.length}字',
    );
    // AI 作答过程（用户要求「ai回答时在答题悬浮窗下面显示作答过程」）。
    // 只推送可核对的阶段事实（压缩比/尝试次数/耗时/结论），不推模型思维链原文：
    // 上游 reasoning 是英文且常夹带无关检索，直接展示会误导用户。
    final proc = <String>[];
    void pushProc() {
      AiProcessBridge.push(proc.join('\n'));
    }

    proc.add('① 读屏截图 ${imageBytes.length ~/ 1024}KB → 压缩至 '
        '${compressed.length ~/ 1024}KB');
    proc.add('② 提交模型 $visionModel（禁工具直答）');
    pushProc();

    final base = config.apiUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/chat/completions');
    // 代理模式判定：base 指向平台 /api/quiz/vision 时 401/403/429 语义不同
    // （session 过期 / 代理未开 / 日限额），文案走 visionHttpErrorText 代理分支。
    final viaProxy = base.contains(QuizVisionEndpoint.proxyPathSegment);
    final body = jsonEncode({
      'model': visionModel,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': visionPrompt},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/png;base64,$b64'},
            },
          ],
        },
      ],
      'max_tokens': 1200,
      'temperature': 0,
      // ⚠️ 实测（2026-09-13）：关思考的参数被该渠道忽略，真正有效的是
      // tool_choice=none —— 从 API 层直接禁止工具调用，比提示词约束更硬。
      // 未注册工具的渠道会忽略该字段，不影响既有行为。
      'tool_choice': 'none',
      'parallel_tool_calls': false,
      'enable_thinking': false,
      'chat_template_kwargs': {'thinking': false},
    });

    // 指数退避：实测 503 会连续命中数次，退避窗口取 2s/5s/10s/15s。
    const backoffsMs = [2000, 5000, 10000, 15000];
    const hardTimeout = Duration(seconds: 45);
    Object? lastError;
    var lastAuthFlaky = false; // 401/403「渠道鉴权不稳」标志（循环内赋值，循环后用）
    final stopwatchStart = stopwatch.elapsed;
    for (var attempt = 0; attempt <= backoffsMs.length; attempt++) {
      // ⚠️ 历史坑（用户 2026-09-13 报障「AI 搜题几分钟没反应」的根因）：
      // 旧代码只在这里检查 elapsed，而下面 `.timeout(hardTimeout)` 是**每次**
      // 都重新起算 45 秒 —— 最坏情况 5 次尝试 = 45×5 + 退避(2+5+10+15) ≈ 257 秒
      // （4 分钟以上），用户看到的就是「一直转没反应」。
      // 现改为按**剩余预算**签发单次超时：总时长硬封顶 45 秒。
      final remaining = hardTimeout - (stopwatch.elapsed - stopwatchStart);
      if (remaining <= Duration.zero) {
        lastError = '读屏超时（已耗时 ${stopwatch.elapsed.inSeconds}s）';
        _visionLog('$tag ✖ 预算耗尽，放弃重试（已 ${stopwatch.elapsed.inSeconds}s）', warn: true);
        break;
      }
      final attemptStart = stopwatch.elapsedMilliseconds;
      _visionLog('$tag → 第${attempt + 1}次请求 剩余预算=${remaining.inSeconds}s');
      proc.add('③ 第${attempt + 1}次请求（预算 ${remaining.inSeconds}s）');
      pushProc();
      try {
        final response = await http
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json; charset=utf-8',
                if (config.apiKey.trim().isNotEmpty)
                  'Authorization': 'Bearer ${config.apiKey.trim()}',
              },
              body: body,
            )
            // 单次超时 = 剩余预算，保证「多次重试」不会把总耗时拖成几分钟。
            .timeout(remaining);

        if (response.statusCode == 200) {
          // 显式按 UTF-8 解码：中文题干若走 latin-1 会变乱码。
          final decoded = jsonDecode(utf8.decode(response.bodyBytes));
          final attemptMs = stopwatch.elapsedMilliseconds - attemptStart;
          _visionLog(
            '$tag ← HTTP200 ${attemptMs}ms finish=${_visionFinishReason(decoded)} '
            '${_visionBriefReply(decoded)}',
          );
          final parsed = _parseVisionPayload(decoded);
          if (parsed == null) {
            // ⚠️ 实测（2026-09-13）：该上游渠道对「像真题的复杂截图」会进入
            // 代码解释器循环 —— finish_reason=tool_calls、content=null，
            // reasoning 里在尝试联网取别的图片/跑 numpy，单次耗时 30s 且
            // **必然拿不到 content**。这时给「无法解析」会误导用户反复重试。
            lastError = _isDegenerateVisionResponse(decoded)
                ? 'AI 读图失败（模型未给出答案），可重试或改用手动录入'
                : '读屏返回无法解析';
            AppLogger.instance.logTo(
              LogChannel.quiz,
              'vision parse failed: finish=${_visionFinishReason(decoded)} '
                  '${response.body.length} chars '
                  '${stopwatch.elapsedMilliseconds}ms',
              level: LogLevel.warn,
            );
            break;
          }
          final result = _visionResultToQuizResult(parsed, question);
          if (result == null) {
            // 模型给了 JSON 但里面没有可用 answer → 明确报错，不编造。
            lastError = '读屏未返回答案';
            AppLogger.instance.logTo(
              LogChannel.quiz,
              'vision missing answer field',
              level: LogLevel.warn,
            );
            break;
          }
          AppLogger.instance.logTo(
            LogChannel.quiz,
            'vision ok: answer="${result.answers.first.correctAnswer}" '
                'conf=${result.answers.first.confidence} '
                '${stopwatch.elapsedMilliseconds}ms',
          );
          proc.add('④ 识别成功，用时 ${stopwatch.elapsedMilliseconds}ms');
          pushProc();
          _visionLog(
            '$tag ✔ 成功 stem="${_truncate(result.question, 40)}" '
            'answer=${result.answers.first.correctAnswer} '
            'conf=${result.answers.first.confidence} '
            '总耗时=${stopwatch.elapsedMilliseconds}ms',
          );
          return result.copyWith(elapsedMs: stopwatch.elapsedMilliseconds);
        }

        // 4xx 鉴权/参数错：只有 401/403（渠道鉴权瞬态抽风）值得重试，
        // 纯参数/内容错（400 等）直接失败。
        // ⚠️ 代理模式例外（2026-09-19 方案 A）：代理的 401/403/429 是确定性
        // 结论（session 过期 / 代理未开 / 日限额），重试 4 次只会白烧 32s
        // 退避预算，让用户多等半分钟才看到同一句话 —— 立即失败。
        if (viaProxy &&
            const {401, 403, 429}.contains(response.statusCode)) {
          lastError = visionHttpErrorText(response.statusCode, viaProxy: true);
          _visionLog('$tag ✖ 代理 HTTP${response.statusCode} 确定性失败，不重试',
              warn: true);
          break;
        }
        final retryable =
            const {500, 502, 503, 504, 429, 401, 403}.contains(
              response.statusCode,
            );
        _visionLog(
          '$tag ← HTTP${response.statusCode} '
          '${stopwatch.elapsedMilliseconds - attemptStart}ms body前200=${_truncate(response.body, 200)}',
          warn: true,
        );
        if (!retryable) {
          lastError = visionHttpErrorText(response.statusCode, viaProxy: viaProxy);
          _visionLog('$tag ✖ HTTP${response.statusCode} 不可重试，直接失败', warn: true);
          break;
        }
        // 401/403 是「渠道鉴权不稳」而非「key 真无效」（同一 key 间歇 200/401）。
        // 全失败后给用户明确提示，避免误以为是题不会。
        lastAuthFlaky = response.statusCode == 401 || response.statusCode == 403;
        lastError = visionHttpErrorText(response.statusCode, viaProxy: viaProxy);
        AppLogger.instance.logTo(
          LogChannel.quiz,
          'vision retry: status=${response.statusCode} attempt=$attempt',
          level: LogLevel.warn,
        );
      } catch (e) {
        lastError = '读屏请求异常：$e';
        _visionLog('$tag ✖ 异常 ${stopwatch.elapsedMilliseconds - attemptStart}ms: $e', warn: true);
      }
      if (attempt < backoffsMs.length) {
        await Future<void>.delayed(Duration(milliseconds: backoffsMs[attempt]));
      }
    }

    _visionLog(
      '$tag ■ 失败：${lastError?.toString() ?? '读屏失败'} '
      'authFlaky=${lastAuthFlaky ? 'y' : 'n'} '
      '总耗时=${stopwatch.elapsedMilliseconds}ms',
      warn: true,
    );
    proc.add('✖ 失败：${lastError?.toString() ?? '读屏失败'}'
        '（用时 ${stopwatch.elapsedMilliseconds}ms）');
    pushProc();
    return QuizResult(
      question: question,
      error: lastError?.toString() ?? '读屏失败',
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
  }

  /// AI 搜题过程日志。统一走 LogChannel.quiz，用户可在
  /// 「抽屉 → 更多 → 调试日志」筛「题库」看到完整链路。
  void _visionLog(String message, {bool warn = false}) {
    AppLogger.instance.logTo(
      LogChannel.quiz,
      message,
      level: warn ? LogLevel.warn : LogLevel.info,
    );
  }

  /// 摘要模型回复，便于日志分析时一眼看出「答空 / 走了工具 / 输出形态」。
  ///
  /// 实测关注三个信号：finish_reason、content 是否为空、是否只有 reasoning。
  /// 只截取前 160 字，避免日志被长文本淹没。
  String _visionBriefReply(Object? decoded) {
    if (decoded is! Map) return 'reply=?';
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return 'choices=空';
    final first = choices.first;
    if (first is! Map) return 'choice0=?';
    final message = first['message'];
    if (message is! Map) return 'message=?';
    final content = message['content'];
    final reasoning = message['reasoning_content'];
    final toolCalls = message['tool_calls'];
    final parts = <String>[];
    parts.add(
      content is String && content.trim().isNotEmpty
          ? 'content="${_truncate(content, 160)}"'
          : 'content=空',
    );
    if (reasoning is String && reasoning.isNotEmpty) {
      parts.add('reasoning=${reasoning.length}字');
    }
    if (toolCalls is List && toolCalls.isNotEmpty) {
      parts.add('tool_calls=${toolCalls.length}个');
    }
    final usage = decoded['usage'];
    if (usage is Map) {
      parts.add(
        'tokens(p=${usage['prompt_tokens']},c=${usage['completion_tokens']})',
      );
    }
    return parts.join(' ');
  }

  String _truncate(String s, int max) {
    final oneLine = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return oneLine.length <= max ? oneLine : '${oneLine.substring(0, max)}…';
  }

  /// 取 choices[0].finish_reason（诊断用，拿不到返回空串）。
  String _visionFinishReason(Object? decoded) {
    if (decoded is! Map) return '';
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return '';
    final first = choices.first;
    if (first is! Map) return '';
    return (first['finish_reason'] ?? '').toString();
  }

  /// 判定「退化响应」：模型没给 content，而是走了工具/代码解释器调用。
  ///
  /// 实测该形态 = `finish_reason: "tool_calls"` 且 `content: null`，
  /// reasoning 里在尝试联网取图/跑 numpy。此形态下重试必然复现，
  /// 只应让上层快速失败，而不是继续耗时间。
  bool _isDegenerateVisionResponse(Object? decoded) {
    if (decoded is! Map) return false;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return false;
    final first = choices.first;
    if (first is! Map) return false;
    final message = first['message'];
    if (message is! Map) return false;
    final content = message['content'];
    final hasContent = content is String && content.trim().isNotEmpty;
    final toolCalls = message['tool_calls'];
    final hasToolCalls = toolCalls is List && toolCalls.isNotEmpty;
    return !hasContent && hasToolCalls;
  }

  /// 从模型返回体中提取结构化读屏结果。
  ///
  /// 实测模型输出形态不稳定：纯 JSON / ```json 围栏 / Markdown 散文夹 JSON
  /// 三种都出现过，故按「围栏 → 首个 JSON 对象」顺序宽松提取。
  Map<String, dynamic>? _parseVisionPayload(Object? decoded) {
    if (decoded is! Map) return null;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final message = first['message'];
    if (message is! Map) return null;
    final content = message['content'];
    // ⚠️ 历史坑（用户 2026-09-13 报障「以前10秒不到可以出，现在半天出不了」的
    // 根因之一）：该上游渠道返回 DeepSeek 推理模型，实测经常
    //   finish_reason=tool_calls 且 content=null，把 JSON 塞在 reasoning_content 里，
    //   reasoning 还带大量思考过程。
    // 旧代码只读 content，一旦为 null 就判定失败 → 触发退避重试 → 每次 30s+，
    // 预算瞬间耗尽，用户看到的就是「转半天出不来」。
    // 现在：content 为空时回落到 reasoning_content，并从中提取 JSON。
    final rawContent = content is String ? content : '';
    final reasoning = (message['reasoning_content'] ?? '').toString();
    final merged = rawContent.trim().isNotEmpty ? rawContent : reasoning;
    if (merged.trim().isEmpty) return null;
    final parsed = parseVisionJson(merged);
    if (parsed != null) return parsed;
    // content 有值但没解析出 JSON 时，再试一次 reasoning（模型嘴里答对了、
    // 正式 content 却给空/散文的情况确实出现过）。
    if (rawContent.trim().isNotEmpty && reasoning.trim().isNotEmpty) {
      return parseVisionJson(reasoning);
    }
    return null;
  }

  /// 把模型 JSON 转成 QuizResult。
  ///
  /// 关键：`stem` 用于回显题干（已验证模型读得准），`answer` 作为正确答案，
  /// `confidence` 透传给 UI 做可信度提示。解析不到 answer 一律返回 null
  /// （上层转成 error），**不得猜测**。
  QuizResult? _visionResultToQuizResult(
    Map<String, dynamic> parsed,
    String fallbackQuestion,
  ) {
    final answer = (parsed['answer'] ?? '').toString().trim();
    if (answer.isEmpty) return null;
    final stem = (parsed['stem'] ?? '').toString().trim();
    final options = <String>[];
    final rawOptions = parsed['options'];
    if (rawOptions is List) {
      for (final o in rawOptions) {
        final t = o.toString().trim();
        if (t.isNotEmpty) options.add(t);
      }
    }
    final conf = (parsed['confidence'] as num?)?.toDouble() ?? 0.0;
    final question = stem.isNotEmpty ? stem : fallbackQuestion;
    return QuizResult(
      question: question,
      source: 'AI读屏',
      answers: [
        QuizAnswer(
          text: answer,
          correctAnswer: answer,
          confidence: conf,
          source: 'AI读屏',
          options: options,
        ),
      ],
    );
  }

  /// 读屏前压缩：长边压到 [visionMaxEdge]，重编码为 PNG。
  ///
  /// 为什么必须压：实测原图 209KB → base64 279KB，而手机截图常 1~3MB，
  /// 不压会明显拉长请求与模型处理时间。压缩参数是启发式，若真机发现
  /// 小字读不准，**调大 visionMaxEdge**；若嫌请求体积大则调小。
  ///
  /// 编码格式说明：`dart:ui` 的 [ui.ImageByteFormat] 只提供 rawRgba / png
  /// 两种输出，**没有 JPEG 编码器**，所以这里输出 PNG（无损、体积比 JPEG
  /// 略大但清晰度更好，利于读小字）。[visionJpegQuality] 因此**当前未被使用**，
  /// 保留常量是为了将来接入 JPEG 编码器（如 image 包）时无需改调用点。
  ///
  /// 只用 dart:ui（项目既有约定，见 quiz_question_image_store.computeDHash），
  /// 不引入额外图像包。
  ///
  /// ⚠️ 实测（2026-09-13，curl 直连 newapi.hpa888.top）：
  ///   小图（8KB base64）→ **2.8s** 返回；真实截图（长边1280）→ **36.0s** 返回。
  /// 延迟随像素量飙升，且该渠道模型会「长篇思考」把 max_tokens 烧在思维链上，
  /// 导致 content 为空。因此这里把长边从 1280 下调到 960：
  ///   - 像素数降到 56%，实测读题小字仍可辨认（科目一题干字号较大）。
  ///   - 若真机发现小字读不准，**调大 visionMaxEdge**；嫌慢则**调小**。
  static const int visionMaxEdge = 960;

  /// 预留：接入 JPEG 编码器后才生效。当前压缩走 PNG（见上）。
  static const int visionJpegQuality = 75;

  Future<Uint8List> _compressForVision(Uint8List bytes) async {
    try {
      // 先读原图尺寸，判断是否需要降采样。
      final probe = await ui.instantiateImageCodec(bytes);
      final probeFrame = await probe.getNextFrame();
      final srcW = probeFrame.image.width;
      final srcH = probeFrame.image.height;
      probeFrame.image.dispose();
      probe.dispose();
      if (srcW <= 0 || srcH <= 0) return bytes;

      final longEdge = srcW > srcH ? srcW : srcH;
      final codec = longEdge > visionMaxEdge
          ? await ui.instantiateImageCodec(
              bytes,
              targetWidth: srcW >= srcH ? visionMaxEdge : null,
              targetHeight: srcH > srcW ? visionMaxEdge : null,
            )
          : await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        codec.dispose();
        if (data == null) return bytes;
        return data.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } catch (_) {
      return bytes;
    }
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
