import 'dart:math';

import './quiz_bank.dart';

/// 将题库答案投影到「当前卷面选项」，避免显示题库异文导致用户对不上 A/B/C/D。
class QuizAnswerAlignment {
  const QuizAnswerAlignment({
    required this.displayAnswer,
    required this.aligned,
    required this.method,
    this.optionIndex,
    this.optionLetter,
    this.probeOption = '',
    this.bankAnswer = '',
    this.score = 0,
  });

  /// 供悬浮窗直接展示（通常已带「B. 停车等待」形态，不含「答案：」前缀）
  final String displayAnswer;

  /// 是否成功对齐到卷面某一选项
  final bool aligned;

  /// exact | letter | multi | contains | token | synonym | similarity | bank_raw | empty
  final String method;

  final int? optionIndex;
  final String? optionLetter;
  final String probeOption;
  final String bankAnswer;
  final int score;

  double get confidenceFactor {
    if (!aligned) return 0.70;
    switch (method) {
      case 'exact':
      case 'letter':
        return 1.0;
      case 'multi':
        return 0.95;
      case 'contains':
      case 'token':
        return 0.96;
      case 'synonym':
        return 0.92;
      case 'similarity':
        return score >= 92 ? 0.94 : 0.88;
      default:
        return 0.70;
    }
  }
}

class QuizAnswerAligner {
  QuizAnswerAligner._();

  /// 驾考高频同义簇（可继续扩充）
  static const List<Set<String>> _synonymClusters = [
    {'停车让行', '停车等待', '停车等候', '停让', '让行', '停车观察', '停车观望', '停在路口等待', '停车观望等待'},
    {'加速通过', '迅速通过', '尽快通过', '加速行驶通过', '直接通过', '无需观察加速通过', '无需观察，加速通过'},
    {'减速慢行', '减速行驶', '缓慢通过', '减速通过', '减速行驶通过', '减速慢行通过'},
    {'立即停车', '马上停车', '紧急停车', '靠边停车', '停车检查'},
    {'正确', '对', '是'},
    {'错误', '错', '否', '不对'},
    {'保持原车道', '继续行驶', '正常行驶', '照常行驶'},
    {'变换车道', '变更车道', '改道'},
    {'开启危险报警闪光灯', '开启危险报警灯', '打开危险报警闪光灯', '打开双闪', '开启双闪'},
    {'放置警告标志', '放置三角警告牌', '设置警告标志', '放置故障警告标志'},
    {'转移到安全区域', '转移到安全地点', '撤离到安全区域', '转移到安全地带'},
    {'未开启危险报警闪光灯', '未开启危险报警灯', '未打开双闪', '未开双闪'},
    {'警告标志放置距离不足', '警告标志距离不足', '三角牌距离不足', '放置距离不足'},
    {'车上人员未转移到安全区域', '人员未转移到安全区域', '未转移到安全区域', '未撤离到安全区域'},
  ];

  static QuizAnswerAlignment align({
    required String bankAnswer,
    required List<String> bankOptions,
    List<String> probeOptions = const [],
  }) {
    final raw = bankAnswer.trim();
    if (raw.isEmpty) {
      return const QuizAnswerAlignment(
        displayAnswer: '',
        aligned: false,
        method: 'empty',
      );
    }

    // 展示优先用卷面选项；没有试捕选项时退回题库选项。
    final surface = probeOptions.where((e) => e.trim().isNotEmpty).toList();
    final options = surface.isNotEmpty
        ? surface
        : bankOptions.where((e) => e.trim().isNotEmpty).toList();
    final hasProbeSurface = surface.isNotEmpty;

    // 1) 纯字母 / 「B. xxx」
    // - 有卷面选项时：禁止纯字母按位硬贴（题库 B 与卷面 B 可能不是同义）
    // - 先解析到题库选项正文，再与卷面做 exact/contains/synonym/similarity
    // - 图选题答案不能贴到文字卷面
    final letter = _extractLetter(raw);
    final pureLetter = RegExp(r'^[答案：:\s]*[A-Ha-hＡ-Ｈ]$').hasMatch(raw.trim());
    if (letter != null) {
      final index = letter.codeUnitAt(0) - 'A'.codeUnitAt(0);
      final bankSurface = bankOptions
          .where((e) => e.trim().isNotEmpty)
          .toList();
      final bankOpt = (index >= 0 && index < bankOptions.length)
          ? bankOptions[index].trim()
          : '';
      // 题库自带选项、但答案字母越出其范围（或指向空正文）→ 属于脏数据：
      // 题库自己都无法确定答案是哪一项，按位硬贴卷面只会编造出一个
      // 高置信的错答案。此时放弃字母映射，交给后续文本匹配/bank_raw。
      // 注意：bankOptions 整体为空是「只存字母答案」的正常形态，仍允许映射。
      final letterOverrunsBank = bankSurface.isNotEmpty && bankOpt.isEmpty;
      final bankOptImage = bankOpt.isNotEmpty && _isImageLikeOption(bankOpt);
      final bankSetImage = _isImageLikeOptionSet(bankOptions);
      final surfaceTextLike = _isTextLikeOptionSet(options);
      final surfaceImageLike = _isImageLikeOptionSet(options);

      if (letterOverrunsBank) {
        // 不做任何字母映射；后续会安全降级为未对齐的 bank_raw。
      } else if ((bankOptImage || bankSetImage) && surfaceTextLike) {
        // 图选题答案不能贴到文字卷面
      } else if (index >= 0 && index < options.length) {
        final opt = options[index].trim();
        // 仅在无卷面试捕、或卷面同为图选题、或正文已一致时，才允许按字母映射。
        final canLetterMap =
            (!hasProbeSurface && pureLetter) ||
            bankOpt.isEmpty ||
            surfaceImageLike ||
            QuizBankTextNormalizer.normalizeOption(bankOpt) ==
                QuizBankTextNormalizer.normalizeOption(opt) ||
            _similarity(
                  QuizBankTextNormalizer.normalizeOption(bankOpt),
                  QuizBankTextNormalizer.normalizeOption(opt),
                ) >=
                80 ||
            _clusterKeys(QuizBankTextNormalizer.normalizeOption(bankOpt))
                .intersection(
                  _clusterKeys(QuizBankTextNormalizer.normalizeOption(opt)),
                )
                .isNotEmpty;
        if (canLetterMap) {
          return QuizAnswerAlignment(
            displayAnswer: '$letter. $opt',
            aligned: true,
            method: 'letter',
            optionIndex: index,
            optionLetter: letter,
            probeOption: opt,
            bankAnswer: raw,
            score: 100,
          );
        }
      }
    }

    if (options.isEmpty) {
      return QuizAnswerAlignment(
        displayAnswer: raw,
        aligned: false,
        method: 'bank_raw',
        bankAnswer: raw,
      );
    }

    var bankResolved = _stripAnswerPrefix(
      _resolveAgainstBankOptions(raw, bankOptions),
    );
    // 题库答案解析成图N，卷面却是文字题：直接失败，避免展示「A. 图1」
    if (_isImageLikeOption(bankResolved) && _isTextLikeOptionSet(options)) {
      return QuizAnswerAlignment(
        displayAnswer: bankResolved,
        aligned: false,
        method: 'bank_raw',
        bankAnswer: raw,
        score: 0,
      );
    }

    // 1.5) 多选/组合答案：①②③ / A+B / 123 等 → 投影到卷面对应项
    //
    // 但排序题的选项本身就是圈码序列（如「②①③④」），答案正文含多个圈码
    // 并不代表多选。判据：答案正文与某个选项完整相等时，它是单选答案，
    // 必须走精确匹配，否则会把四个选项全部投影展示。
    final multi = _answerEqualsSingleOption(bankResolved, bankOptions, options)
        ? null
        : _tryMultiSelectAlignment(
            raw: raw,
            bankResolved: bankResolved,
            bankOptions: bankOptions,
            options: options,
          );
    if (multi != null) return multi;

    final bankNorm = QuizBankTextNormalizer.normalizeOption(bankResolved);
    // 去掉卷面选项前缀后的正文（A./①/1.）再比
    final bankCore = _coreOptionText(bankResolved);

    // 2) 精确匹配
    for (var i = 0; i < options.length; i++) {
      final opt = options[i].trim();
      final optNorm = QuizBankTextNormalizer.normalizeOption(opt);
      final optCore = _coreOptionText(opt);
      if (optNorm.isEmpty) continue;
      if (bankNorm == optNorm ||
          bankCore == optCore ||
          bankNorm == optCore ||
          bankCore == optNorm) {
        final L = String.fromCharCode(0x41 + i);
        return QuizAnswerAlignment(
          displayAnswer: '$L. $opt',
          aligned: true,
          method: 'exact',
          optionIndex: i,
          optionLetter: L,
          probeOption: opt,
          bankAnswer: raw,
          score: 100,
        );
      }
    }

    // 3) 包含关系（短答案→长选项放宽门槛）
    var bestContains = -1;
    var bestContainsScore = 0;
    for (var i = 0; i < options.length; i++) {
      final opt = options[i].trim();
      final optNorm = QuizBankTextNormalizer.normalizeOption(opt);
      final optCore = _coreOptionText(opt);
      if (optNorm.isEmpty) continue;
      final score = _containmentScore(bankCore, optCore);
      if (score > bestContainsScore) {
        bestContainsScore = score;
        bestContains = i;
      }
    }
    // 短答案（≤6）对长选项：门槛 78；普通 85
    final containThreshold = bankCore.length <= 6 ? 78 : 85;
    if (bestContains >= 0 && bestContainsScore >= containThreshold) {
      final opt = options[bestContains].trim();
      final L = String.fromCharCode(0x41 + bestContains);
      return QuizAnswerAlignment(
        displayAnswer: '$L. $opt',
        aligned: true,
        method: 'contains',
        optionIndex: bestContains,
        optionLetter: L,
        probeOption: opt,
        bankAnswer: raw,
        score: bestContainsScore,
      );
    }

    // 4) 同义簇
    final bankKeys = _clusterKeys(bankCore);
    if (bankKeys.isNotEmpty) {
      for (var i = 0; i < options.length; i++) {
        final opt = options[i].trim();
        final optCore = _coreOptionText(opt);
        final optKeys = _clusterKeys(optCore);
        if (optKeys.isEmpty) continue;
        if (bankKeys.intersection(optKeys).isNotEmpty) {
          final L = String.fromCharCode(0x41 + i);
          return QuizAnswerAlignment(
            displayAnswer: '$L. $opt',
            aligned: true,
            method: 'synonym',
            optionIndex: i,
            optionLetter: L,
            probeOption: opt,
            bankAnswer: raw,
            score: 90,
          );
        }
      }
    }

    // 4.5) token 覆盖：题库短答的每个关键 token 都出现在某一卷面选项
    final tokenHit = _bestTokenCoverage(bankCore, options);
    if (tokenHit != null) return tokenHit;

    // 5) 相似度（短串门槛略降）
    var bestI = -1;
    var bestScore = 0;
    for (var i = 0; i < options.length; i++) {
      final opt = options[i].trim();
      final optCore = _coreOptionText(opt);
      if (optCore.isEmpty) continue;
      final s = _similarity(bankCore, optCore);
      if (s > bestScore) {
        bestScore = s;
        bestI = i;
      }
    }
    final simThreshold = bankCore.length <= 6 ? 78 : 82;
    if (bestI >= 0 && bestScore >= simThreshold) {
      final opt = options[bestI].trim();
      final L = String.fromCharCode(0x41 + bestI);
      return QuizAnswerAlignment(
        displayAnswer: '$L. $opt',
        aligned: true,
        method: 'similarity',
        optionIndex: bestI,
        optionLetter: L,
        probeOption: opt,
        bankAnswer: raw,
        score: bestScore,
      );
    }

    // 6) 失败：保留题库原文，并标明未对齐
    return QuizAnswerAlignment(
      displayAnswer: raw,
      aligned: false,
      method: 'bank_raw',
      bankAnswer: raw,
      score: bestScore,
    );
  }

  /// 答案正文是否与某个选项完整相等（题库侧或卷面侧任一命中即可）。
  ///
  /// 排序题的选项就是圈码序列本身，答案「②①③④」等于 B 选项正文。
  /// 这种情况下答案是单选，圈码不是多选标记，必须阻止多选投影。
  /// 而真正的多选答案（如「①③」，选项正文是文字）不会与任何选项相等。
  static bool _answerEqualsSingleOption(
    String bankResolved,
    List<String> bankOptions,
    List<String> options,
  ) {
    final answerNorm = QuizBankTextNormalizer.normalizeOption(bankResolved);
    if (answerNorm.isEmpty) return false;
    for (final list in [bankOptions, options]) {
      for (final o in list) {
        final optNorm = QuizBankTextNormalizer.normalizeOption(o);
        if (optNorm.isNotEmpty && optNorm == answerNorm) return true;
      }
    }
    return false;
  }

  /// 多选组合：①②③ / A+B / 123 / A、B、C
  static QuizAnswerAlignment? _tryMultiSelectAlignment({
    required String raw,
    required String bankResolved,
    required List<String> bankOptions,
    required List<String> options,
  }) {
    final indices = _extractMultiIndices(raw, bankOptions.length);
    if (indices == null || indices.length < 2) return null;
    // 先按题库选项正文投影到卷面；失败再按字母序硬投（仅当题库/卷面选项数一致）
    final projected = <int>{};
    for (final i in indices) {
      if (i < 0 || i >= bankOptions.length) continue;
      final bankOpt = bankOptions[i].trim();
      final hit = _bestMatchIndex(bankOpt, options);
      if (hit != null) {
        projected.add(hit);
      } else if (i < options.length && bankOptions.length == options.length) {
        // 同结构卷面才允许按位
        projected.add(i);
      }
    }
    if (projected.length < 2) return null;
    final sorted = projected.toList()..sort();
    final letters = sorted.map((i) => String.fromCharCode(0x41 + i)).join('');
    final texts = sorted.map((i) => options[i].trim()).join('；');
    return QuizAnswerAlignment(
      displayAnswer: '$letters. $texts',
      aligned: true,
      method: 'multi',
      optionIndex: sorted.first,
      optionLetter: letters,
      probeOption: texts,
      bankAnswer: raw,
      score: 95,
    );
  }

  static List<int>? _extractMultiIndices(String raw, int optionCount) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final found = <int>{};

    // ①②③ / ⑴⑵ / 1.2.3 / 1、2、3
    final circled = {
      '①': 0,
      '②': 1,
      '③': 2,
      '④': 3,
      '⑤': 4,
      '⑥': 5,
      '⑦': 6,
      '⑧': 7,
      '⑴': 0,
      '⑵': 1,
      '⑶': 2,
      '⑷': 3,
    };
    for (final entry in circled.entries) {
      if (t.contains(entry.key)) found.add(entry.value);
    }

    // A+B / A、B / AB / A B
    final letters = RegExp(r'[A-Ha-hＡ-Ｈ]')
        .allMatches(t)
        .map((m) {
          final ch = _halfWidthLetter(m.group(0)!);
          return ch.codeUnitAt(0) - 'A'.codeUnitAt(0);
        })
        .where((i) => i >= 0 && i < max(optionCount, 8));
    for (final i in letters) {
      found.add(i);
    }

    // 纯数字组合 123 / 1 2 3（至少两位数字且无长正文）
    final digitsOnly = t.replaceAll(RegExp(r'[\s,，、+/和及与]'), '');
    if (RegExp(r'^[1-8]{2,8}$').hasMatch(digitsOnly)) {
      for (final ch in digitsOnly.split('')) {
        final i = int.parse(ch) - 1;
        if (i >= 0 && i < max(optionCount, 8)) found.add(i);
      }
    }

    if (found.length < 2) return null;
    final list = found.toList()..sort();
    return list;
  }

  static int? _bestMatchIndex(String bankOpt, List<String> options) {
    final bankCore = _coreOptionText(bankOpt);
    if (bankCore.isEmpty) return null;
    var bestI = -1;
    var best = 0;
    for (var i = 0; i < options.length; i++) {
      final optCore = _coreOptionText(options[i]);
      if (optCore.isEmpty) continue;
      if (bankCore == optCore) return i;
      final c = _containmentScore(bankCore, optCore);
      final s = _similarity(bankCore, optCore);
      final score = max(c, s);
      if (score > best) {
        best = score;
        bestI = i;
      }
    }
    if (bestI >= 0 && best >= 78) return bestI;
    final keys = _clusterKeys(bankCore);
    if (keys.isNotEmpty) {
      for (var i = 0; i < options.length; i++) {
        final optKeys = _clusterKeys(_coreOptionText(options[i]));
        if (keys.intersection(optKeys).isNotEmpty) return i;
      }
    }
    return null;
  }

  static String _coreOptionText(String raw) {
    var t = _stripAnswerPrefix(raw);
    // 去 A./①/1. 等前缀
    t = t
        .replaceFirst(RegExp(r'^[A-Ha-hＡ-Ｈ][.、．:：)）\s]+'), '')
        .replaceFirst(RegExp(r'^[1-8][.、．:：)）\s]+'), '')
        .trim();
    // 圈码前缀只在它确实是「编号 + 正文」时才剥。
    // 排序题的选项整体就是圈码序列（如「②①③④」），剥掉首个圈码会得到
    // 「①③④」，恰好与另一个选项相等，导致答案被贴到错误选项上。
    if (!_isEnumSequenceOnly(t)) {
      t = t.replaceFirst(RegExp(r'^[①②③④⑤⑥⑦⑧⑨⑩⑴⑵⑶⑷⑸]'), '').trim();
    }
    return QuizBankTextNormalizer.normalizeOption(t);
  }

  /// 文本是否整体只由圈码/序号标记组成（如「②①③④」）。
  /// 这类文本是排序题的答案序列本身，不含可剥离的编号前缀。
  static bool _isEnumSequenceOnly(String text) {
    final t = text.replaceAll(RegExp(r'[\s、,，+]'), '');
    if (t.isEmpty) return false;
    return RegExp(r'^[①②③④⑤⑥⑦⑧⑨⑩⑴⑵⑶⑷⑸]+$').hasMatch(t);
  }

  static int _containmentScore(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 100;
    if (!a.contains(b) && !b.contains(a)) {
      // 关键 token 覆盖：短串 token 全在长串中
      final short = a.length <= b.length ? a : b;
      final long = a.length <= b.length ? b : a;
      final tokens = _tokens(short);
      if (tokens.isNotEmpty && tokens.every(long.contains)) {
        final cover = tokens.join().length;
        return (78 + cover * 20 ~/ max(1, long.length)).clamp(78, 96);
      }
      return 0;
    }
    final shorter = min(a.length, b.length);
    final longer = max(a.length, b.length);
    if (longer == 0) return 0;
    // 短串≥2 且被长串包含：给更高分，避免「停车让行」被长度比压死
    if (shorter >= 2 && (a.contains(b) || b.contains(a))) {
      final base = 82 + shorter * 18 ~/ longer;
      return base.clamp(82, 99);
    }
    return (80 + shorter * 20 ~/ longer).clamp(0, 99);
  }

  static QuizAnswerAlignment? _bestTokenCoverage(
    String bankCore,
    List<String> options,
  ) {
    final tokens = _tokens(bankCore);
    if (tokens.isEmpty || bankCore.length < 2) return null;
    var bestI = -1;
    var bestScore = 0;
    for (var i = 0; i < options.length; i++) {
      final optCore = _coreOptionText(options[i]);
      if (optCore.isEmpty) continue;
      final hit = tokens.where(optCore.contains).length;
      if (hit == 0) continue;
      final score = (hit * 100 / tokens.length).round();
      // 全部 token 命中，或 ≥70% 且至少 2 个 token
      final ok = hit == tokens.length || (tokens.length >= 2 && score >= 70);
      if (ok && score > bestScore) {
        bestScore = score;
        bestI = i;
      }
    }
    if (bestI < 0) return null;
    final opt = options[bestI].trim();
    final L = String.fromCharCode(0x41 + bestI);
    return QuizAnswerAlignment(
      displayAnswer: '$L. $opt',
      aligned: true,
      method: 'token',
      optionIndex: bestI,
      optionLetter: L,
      probeOption: opt,
      bankAnswer: bankCore,
      score: bestScore,
    );
  }

  static List<String> _tokens(String norm) {
    if (norm.isEmpty) return const [];
    // 优先按常见分隔；否则按 2 字滑窗
    final parts = norm
        .split(RegExp(r'[，,、；;：:（）()\[\]【】\s]+'))
        .where((e) => e.trim().isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      return parts.where((e) => e.length >= 2).toList();
    }
    final t = parts.isEmpty ? norm : parts.first;
    if (t.length <= 4) return t.length >= 2 ? [t] : const [];
    final out = <String>[];
    for (var i = 0; i + 2 <= t.length; i += 2) {
      out.add(t.substring(i, min(i + 2, t.length)));
    }
    if (t.length.isOdd && t.length >= 3) {
      out.add(t.substring(t.length - 2));
    }
    return out.where((e) => e.length >= 2).toSet().toList();
  }

  static String _stripAnswerPrefix(String text) {
    return text
        .replaceFirst(RegExp(r'^答案[是为：:\s]*'), '')
        .replaceFirst(RegExp(r'^[答案：:\s]+'), '')
        .trim();
  }

  static String? _extractLetter(String raw) {
    final t = raw.trim();
    final m1 = RegExp(r'^[答案：:\s]*([A-Ha-hＡ-Ｈ])\b').firstMatch(t);
    if (m1 != null) return _halfWidthLetter(m1.group(1)!);
    final m2 = RegExp(r'^[答案：:\s]*([A-Ha-hＡ-Ｈ])[.、．:：)）]').firstMatch(t);
    if (m2 != null) return _halfWidthLetter(m2.group(1)!);
    if (RegExp(r'^[A-Ha-hＡ-Ｈ]$').hasMatch(t)) {
      return _halfWidthLetter(t);
    }
    return null;
  }

  static String _halfWidthLetter(String ch) {
    final c = ch.toUpperCase();
    if (c.codeUnitAt(0) >= 0xFF21 && c.codeUnitAt(0) <= 0xFF28) {
      return String.fromCharCode(c.codeUnitAt(0) - 0xFEE0);
    }
    return c;
  }

  static String _resolveAgainstBankOptions(
    String raw,
    List<String> bankOptions,
  ) {
    final letter = _extractLetter(raw);
    if (letter != null) {
      final index = letter.codeUnitAt(0) - 'A'.codeUnitAt(0);
      if (index >= 0 && index < bankOptions.length) {
        return bankOptions[index].trim();
      }
    }
    final stripped = _stripAnswerPrefix(raw);
    // 「A. 图1」→ 图1
    final m = RegExp(r'^[A-Ha-hＡ-Ｈ][.、．:：)）\s]+(.+)$').firstMatch(stripped);
    if (m != null) return m.group(1)!.trim();
    return stripped;
  }

  static bool _isImageLikeOption(String raw) {
    final n = QuizBankTextNormalizer.normalizeOption(raw);
    if (n.isEmpty) return false;
    return RegExp(r'^图\s*\d+$').hasMatch(n) ||
        RegExp(r'^图[一二三四五六七八九十]+$').hasMatch(n) ||
        RegExp(r'^图片\d*$').hasMatch(n) ||
        n == '如图' ||
        n == '见图';
  }

  static bool _isImageLikeOptionSet(List<String> options) {
    final cleaned = options.map((e) => e.trim()).where((e) => e.isNotEmpty);
    if (cleaned.isEmpty) return false;
    final imageCount = cleaned.where(_isImageLikeOption).length;
    return imageCount >= max(1, (cleaned.length + 1) ~/ 2);
  }

  static bool _isTextLikeOptionSet(List<String> options) {
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

  static Set<String> _clusterKeys(String normText) {
    final keys = <String>{};
    if (normText.isEmpty) return keys;
    for (var i = 0; i < _synonymClusters.length; i++) {
      final cluster = _synonymClusters[i];
      for (final term in cluster) {
        final tn = QuizBankTextNormalizer.normalizeOption(term);
        if (tn.isEmpty) continue;
        if (normText == tn || normText.contains(tn) || tn.contains(normText)) {
          keys.add('c$i');
          break;
        }
      }
    }
    return keys;
  }

  static int _similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 100;
    final lcs = _lcs(a, b);
    final lcsScore = (lcs * 200 / (a.length + b.length)).round();
    final setA = a.split('').toSet();
    final setB = b.split('').toSet();
    final union = setA.union(setB).length;
    final inter = setA.intersection(setB).length;
    final jaccard = union == 0 ? 0 : (inter * 100 / union).round();
    return max(lcsScore, min(jaccard, 90));
  }

  static int _lcs(String a, String b) {
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
}
