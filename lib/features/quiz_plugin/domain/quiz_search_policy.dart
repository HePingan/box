import 'quiz_diag.dart';
import './quiz_bank.dart';

enum QuizResultSource { localBank, ocrLocalBank, externalApi, aiVision, unknown }

/// 搜题请求的质量门控：防重复检索，也允许半题命中被完整题纠正。
class QuizSearchPolicy {
  String _lockedStem = '';
  String _lockedOptions = '';
  String _lockedImageHash = '';
  QuizResultSource? _bestSource;

  /// 当前来源排名所属的题目指纹。用于防止「上一题的来源排名掐死下一题」
  /// （2026-09-12 三轮报障根因：「所有题 20 秒都不出答案」）。
  String _bestSourceStem = '';

  /// 切题时调用：清掉与上一题相关的全部决策状态。
  ///
  /// 尤其是 [_bestSource] —— 它决定 `canReplaceWith` 是否放行新结果。
  /// 若不清空，上一题命中 localBank(rank=4) 后，新题任何更低秩的来源
  /// （OCR 本地题库 rank=3、外部 API rank=2）都会被判为「降级」，
  /// 而调用方在**更新悬浮窗之前**就 return，悬浮窗于是永远停在「检索中」。
  void resetForNewQuestion() {
    _bestSource = null;
    _bestSourceStem = '';
    _attemptStem = '';
    _attemptOptions = '';
    _attemptAt = null;
    _attemptSucceeded = false;
  }

  /// 最近一次「已发起但尚未产出成功结果」的请求，用于冷启动节流。
  String _attemptStem = '';
  String _attemptOptions = '';
  DateTime? _attemptAt;
  bool _attemptSucceeded = false;

  /// 同题重复请求节流窗口。仅用于拦截「已有成功结果」的完全重复检索；
  /// 首次请求未成功时必须放行重试，否则悬浮窗会停在「检索中」。
  static const Duration attemptThrottleWindow = Duration(seconds: 3);
  DateTime Function() clock = DateTime.now;

  /// 题干指纹：来源排名与节流的统一键。
  ///
  /// 必须剥离「`|image:<dHash>`」后缀（2026-09-19 真机报障）：
  /// _runSearch 的 requestFingerprint 带该后缀（切题身份口径），而 AI 读屏链路
  /// recordSuccess 存的是无后缀指纹。后缀不剥离时 canReplaceWith 把**同一道题**
  /// 的第二次结果误判成「换题，旧排名作废」，rank 4 的题库候选（候选1/候选2
  /// 请人工确认卡）便顶掉已上屏的 rank 5 AI 答案——用户看到答案闪现 <1s 被
  /// 刷成候选。后缀只属于切题身份（generation/_activeQuestionFingerprint）
  /// 机制，排名/节流一律以纯题干为键。
  static String stemFingerprint(String raw) {
    var s = QuizBankTextNormalizer.stripQuestionPrefix(raw);
    // 只剥「|image:」+ 16 位 hex 的结尾后缀（dHash 由
    // _captureImageHashForDisambiguation 校验 ^[0-9a-f]{16}$ 才会拼接），
    // 普通题干文本不可能撞上该模式。
    s = s.replaceFirst(RegExp(r'\|image:[0-9a-f]{16}$'), '');
    return s.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  }

  static List<String> normalizedOptions(List<String> options) =>
      options
          .map(QuizBankTextNormalizer.normalizeOption)
          .where((e) => e.isNotEmpty)
          .toList()
        ..sort();

  static String _optionsKey(List<String> options) =>
      normalizedOptions(options).join('|');

  bool shouldSuppress({
    required String stem,
    required List<String> options,
    String? imageHash,
    bool manualRefresh = false,
  }) {
    if (manualRefresh) return false;
    final normalizedStem = stemFingerprint(stem);
    // 已有成功结果的完全重复才拦。逐条记「为什么放行」，因为历史上
    // 悬浮窗卡「检索中」正是被这里的静默 return false/true 组合坑过。
    if (normalizedStem.isEmpty || normalizedStem != _lockedStem) {
      QuizDiag.log(QuizDiagStage.throttle, 'suppress=no(非同题)',
          fields: {'same': normalizedStem == _lockedStem});
      return false;
    }
    // 选项补全/变化表示题目质量提升或同题干另一题，允许受控复搜。
    if (_lockedOptions != _optionsKey(options)) {
      QuizDiag.log(QuizDiagStage.throttle, 'suppress=no(选项变了)');
      return false;
    }
    // 交通标志等图片题常出现同题干同选项的多个变体；题图变化必须复搜。
    final normalizedImageHash = (imageHash ?? '').trim().toLowerCase();
    final hit = _lockedImageHash == normalizedImageHash;
    QuizDiag.log(QuizDiagStage.throttle,
        'suppress=${hit ? 'YES(完全重复，跳过检索)' : 'no(题图变了)'}');
    return hit;
  }

  /// 被 [shouldSuppress] 拦下时，调用方是否**仍须重绘悬浮窗**。
  ///
  /// 真机 1.18.15 (238) 录屏（2026-09-13 11:55）暴露的真根因 —— 用户报障原话
  /// 「回滑就识别不出来」：
  ///
  ///   屏幕题干 = 图中地面标记表示（ ）        正确答 = 人行横道预告
  ///   悬浮窗   = 向侧滑的反方向转动方向盘适量修正   ← **后一题**（泥泞路侧滑）的答案
  ///
  /// 用户**回滑**（从当前题滑回上一题）到一道曾经命中并锁定的题时，
  /// `_handleCapturedQuestion` 里 `shouldSuppress` 返回 true 并**直接 return**，
  /// 跳过了答案重绘。于是悬浮窗永远停在后一题的答案上，看起来就是"识别不出来"。
  ///
  /// 语义区分（本方法的全部意义）：**节流该省的是"重新检索"（算力），
  /// 绝不能连带省掉"重绘"（纠正画面）**。同一道题重新出现在屏幕上，
  /// 即便不必再查题库，也必须把它自己的答案重新渲染一次。
  ///
  /// 返回 true 的充要条件：本题确有已锁定的答案、且当前画面可能不是它
  /// （即 stem/options/imageHash 与锁定态一致，属"同题重复捕获"）。
  /// 非同题返回 false —— 那条路径走完整检索，重绘自然发生。
  bool shouldRedrawOnRecapture({
    required String stem,
    required List<String> options,
    String? imageHash,
  }) {
    final normalizedStem = stemFingerprint(stem);
    if (normalizedStem.isEmpty || normalizedStem != _lockedStem) return false;
    if (_lockedOptions != _optionsKey(options)) return false;
    final normalizedImageHash = (imageHash ?? '').trim().toLowerCase();
    return _lockedImageHash == normalizedImageHash;
  }

  void recordSuccess({
    required String stem,
    required List<String> options,
    required QuizResultSource source,
    required int questionScore,
    required int optionScore,
    String? imageHash,
  }) {
    final isReliableLocal =
        source == QuizResultSource.localBank &&
        questionScore >= 95 &&
        (options.isEmpty || optionScore >= 90);
    _bestSource = source;
    _bestSourceStem = stemFingerprint(stem);
    QuizDiag.log(
      QuizDiagStage.source,
      'recordSuccess',
      fields: {
        'src': source.name,
        'q': questionScore,
        'o': optionScore,
        'reliable': isReliableLocal,
        'locked': isReliableLocal ? 'yes(已锁定,可节流)' : 'no(可被更高分覆盖)',
      },
    );
    if (isReliableLocal) {
      _lockedStem = stemFingerprint(stem);
      _lockedOptions = _optionsKey(options);
      _lockedImageHash = (imageHash ?? '').trim().toLowerCase();
    } else {
      _lockedStem = '';
      _lockedOptions = '';
      _lockedImageHash = '';
    }
    // 产出成功结果后，才允许窗口内的完全重复请求被节流。
    _attemptSucceeded = true;
  }

  /// 是否允许用 [incoming] 来源的结果替换当前展示。
  ///
  /// [stem] 为当前题指纹。**必须传入**：若与 [_bestSourceStem] 不同，
  /// 说明换了题，上一题的来源排名一律作废 —— 这是防止「跨题污染」的
  /// 第二道防线（第一道是切题时调用 [resetForNewQuestion]）。
  bool canReplaceWith(QuizResultSource incoming, {String stem = ''}) {
    if (_bestSource == null) return true;
    // 换了题：上一题的排名不适用于新题，直接放行。
    // 必须先走 stemFingerprint 归一化：调用方（_runSearch）传的
    // requestFingerprint 带「|image:<dHash>」切题后缀，直接和
    // _bestSourceStem 比较会把同题误判成换题、旧排名作废，
    // 低秩候选便可顶掉已上屏的 AI 答案（2026-09-19 报障根因）。
    final nextStem = stemFingerprint(stem);
    if (nextStem.isNotEmpty && nextStem != _bestSourceStem) {
      QuizDiag.log(QuizDiagStage.source, 'canReplace=YES(换题,旧排名作废)',
          fields: {'in': incoming.name, 'prev': _bestSource!.name});
      return true;
    }
    final ok = _rank(incoming) >= _rank(_bestSource!);
    // 这行是三轮报障的核心证据位：不允许替换时悬浮窗会保留旧内容，
    // 表现为「一直检索中」。
    QuizDiag.log(
      QuizDiagStage.source,
      'canReplace=${ok ? 'YES' : 'NO(被旧来源掐住!)'}',
      fields: {
        'in': '${incoming.name}(rank ${_rank(incoming)})',
        'best': '${_bestSource!.name}(rank ${_rank(_bestSource!)})',
      },
      level: ok ? LogLevel.info : LogLevel.warn,
    );
    return ok;
  }

  /// 记录一次「即将发起」的检索请求。
  ///
  /// 关键（2026-09-12 二次报障修正）：**同题的重复 attempt 必须保留既有的
  /// 成功状态**。旧的实现无条件 `_attemptSucceeded = false`，导致已经命中过的
  /// 题目在同题重复捕获（无障碍 repeat / OCR 兜底 / 试捕 attempt+1 /
  /// 页面渐进加载）时被误判为「未成功」而全部放行，每题都重复全量检索，
  /// 原本秒出的题因此变卡、甚至因并发串结果而答不出。
  ///
  /// 因此这里只在「换了题（题干或选项不同）」时才重置成功标记。
  void recordAttempt({required String stem, required List<String> options}) {
    final nextStem = stemFingerprint(stem);
    final nextOptions = _optionsKey(options);
    final sameQuestion = nextStem == _attemptStem && nextOptions == _attemptOptions;
    _attemptStem = nextStem;
    _attemptOptions = nextOptions;
    _attemptAt = clock();
    // 同题重复请求不清成功标记；换题才重置。
    if (!sameQuestion) _attemptSucceeded = false;
    QuizDiag.log(
      QuizDiagStage.throttle,
      'recordAttempt',
      fields: {
        'sameQ': sameQuestion,
        'succeeded': _attemptSucceeded,
        'stmt': nextStem.length > 24 ? '${nextStem.substring(0, 24)}…' : nextStem,
      },
    );
  }

  /// 冷启动节流判定：仅当「同题同选项」在窗口内且**上一次已成功**时才拦截。
  ///
  /// 关键：未成功的首次请求绝不能拦掉重试——题库冷启动时第一次检索可能
  /// 因缓存未加载完而返回空，若把紧随其后的重试/OCR 兜底静默吞掉，
  /// 悬浮窗会永久停在「检索中」（用户报障现象）。
  bool shouldSuppressThrottled({
    required String stem,
    required List<String> options,
  }) {
    final normalizedStem = stemFingerprint(stem);
    if (normalizedStem.isEmpty) return false;
    final at = _attemptAt;
    if (at == null) return false;
    if (!_attemptSucceeded) return false;
    if (normalizedStem != _attemptStem) {
      // 换题了：上一题的 attempt/success 状态对本新题没有意义，必须作废。
      //
      // 真机 1.18.9 (232) 日志（2026-09-12T21:19:22.990）：
      //   THROTTLE 指纹不匹配：attempt=51 now=4
      // 51 = 上一题（已命中 localBank）的 _attemptStem 长度，
      // 4  = 本题（解析页噪声「本题技巧」）的指纹长度。
      // 调用顺序是 shouldSuppressThrottled（:697）先于 recordAttempt（:703），
      // 所以这里必然拿「上一题的 _attemptStem」去比「本题的 normalizedStem」，
      // 一旦跨题就恒不相等 —— 节流静默失效，每题重复全量检索。
      //
      // 注意：这里**只清 attempt 状态，不降阈值、不改 success 语义**，
      // 属消除断崖的最小改动。
      final wasSucceeded = _attemptSucceeded;
      _attemptStem = normalizedStem;
      _attemptOptions = _optionsKey(options);
      _attemptSucceeded = false;
      _attemptAt = null;
      QuizDiag.log(QuizDiagStage.throttle, '换题：attempt 状态已作废',
          fields: {
            'prevSucceeded': wasSucceeded,
            'nowLen': normalizedStem.length,
          });
      return false;
    }
    if (_optionsKey(options) != _attemptOptions) return false;
    final within = clock().difference(at) < attemptThrottleWindow;
    if (within) {
      QuizDiag.log(QuizDiagStage.throttle, 'THROTTLED(跳过重复检索)',
          fields: {'ms': clock().difference(at).inMilliseconds});
    }
    return within;
  }

  /// 标记上一次请求已产出成功结果，之后窗口内的完全重复才会被节流。
  ///
  /// 注意：全局 grep 显示**没有任何调用点**（死代码）。真正的成功标记由
  /// [recordSuccess] 内部的 `_attemptSucceeded = true` 完成。保留是为了
  /// 兼容既有测试，勿据此认为节流链路正常。
  void markAttemptSucceeded() {
    _attemptSucceeded = true;
  }

  /// 来源排名。数值越大越可信、越有权覆盖已展示结果。
  ///
  /// [aiVision]（大模型读屏）排在最前（rank 5）：它**只在本地题库未命中时**
  /// 才被调用（2026-09-13 用户拍板「所有本地未命中的题」），因此它出现时
  /// 本身就意味着更高可信来源已经失败；若排在 localBank(4) 之后，它在
  /// 「同一题先命中本地、后又走读屏」等边界上会被静默丢弃，悬浮窗停在
  /// 「检索中」—— 这正是历史上三轮报障的成因，必须避免重演。
  int _rank(QuizResultSource source) => switch (source) {
    QuizResultSource.aiVision => 5,
    QuizResultSource.localBank => 4,
    QuizResultSource.ocrLocalBank => 3,
    QuizResultSource.externalApi => 2,
    QuizResultSource.unknown => 1,
  };
}
