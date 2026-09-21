import 'quiz_bank.dart';

/// AI 读屏命中的「待上报候选」。
///
/// 用户 2026-09-13 拍板（逐字）：
///   1. 「A 档不提交，保留该题的截图及 ai 识别的题目信息，后面我再手动补充」
///   2. 「命中静默」
///   3. 「conf 大于等于 0.9」
///   4. 「可以」（未登录静默禁用）
///
/// 因此本模型承担两件事：
///   - 决策：这条命中该不该静默上报后端待审核区（[autoSubmitDecision]）
///   - 留档：**无论是否上报**，截图路径 + 题干/选项/答案/置信度都要完整保留，
///          供用户后续手动补充后投稿（A 档的核心诉求）。
class QuizVisionCandidate {
  QuizVisionCandidate({
    required this.stem,
    required this.options,
    required this.answer,
    required this.confidence,
    required this.capturedAt,
    this.imagePath,
    this.loggedIn = false,
    this.cloudPushAllowed = false,
    this.analysis,
    this.id,
  });

  /// 上报门槛：置信度必须 ≥ 此值（用户拍板「conf 大于等于 0.9」）。
  ///
  /// 调大 → 上报更少但更准（审核负担轻）；调小 → 上报更多但噪音大。
  static const double confidenceThreshold = 0.9;

  /// 单选题需至少这么多个选项（与后端 validationError 对齐）。
  static const int minOptionCount = 2;

  final String stem;
  final List<String> options;
  final String answer;
  final double confidence;
  final DateTime capturedAt;

  /// 读屏截图的本地落盘路径。A 档留档的关键——即使用户手动补充也要有图。
  final String? imagePath;

  /// 决策时的登录态快照（未登录静默禁用）。
  final bool loggedIn;

  /// 决策时的插件策略快照（云推送是否被允许）。
  final bool cloudPushAllowed;

  final String? analysis;

  /// 落盘主键；为空表示尚未持久化。
  final String? id;

  QuizVisionCandidate copyWith({
    String? id,
    String? stem,
    List<String>? options,
    String? answer,
    double? confidence,
    String? imagePath,
    String? analysis,
  }) => QuizVisionCandidate(
    id: id ?? this.id,
    stem: stem ?? this.stem,
    options: options ?? this.options,
    answer: answer ?? this.answer,
    confidence: confidence ?? this.confidence,
    capturedAt: capturedAt,
    imagePath: imagePath ?? this.imagePath,
    loggedIn: loggedIn,
    cloudPushAllowed: cloudPushAllowed,
    analysis: analysis ?? this.analysis,
  );

  /// 有效选项（去空白，与后端口径一致）。
  List<String> get effectiveOptions => options
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);

  /// 不能上报的原因；可上报时返回 null。
  ///
  /// 顺序即优先级：身份问题 → 登录/权限 → 内容完整性 → 置信度。
  String? get keepReason {
    if (stem.trim().isEmpty) return '题干为空，无法上报（留档待补）';
    if (answer.trim().isEmpty) return '答案为空，无法上报（留档待补）';
    if (effectiveOptions.length < minOptionCount) {
      return '选项不足 $minOptionCount 项，无法上报（留档待补）';
    }
    if (!loggedIn) return '未登录，静默跳过上报（留档待补）';
    if (!cloudPushAllowed) return '云推送未开放，静默跳过上报（留档待补）';
    if (confidence < confidenceThreshold) {
      return '置信度 ${confidence.toStringAsFixed(2)} 低于 '
          '${confidenceThreshold.toStringAsFixed(1)}，留档待人工确认';
    }
    return null;
  }

  /// 上报决策。命中静默：调用方据此决定是否**异步**提交，绝不阻塞悬浮窗。
  QuizVisionSubmitDecision get autoSubmitDecision =>
      keepReason == null
      ? QuizVisionSubmitDecision.autoSubmit
      : QuizVisionSubmitDecision.keepLocalOnly;

  bool get canAutoSubmit =>
      autoSubmitDecision == QuizVisionSubmitDecision.autoSubmit;

  /// 转成本地题库条目，供用户补充后走既有投稿链路
  /// （`QuizCloudPushCoordinator.pushItems`）。
  QuizBankItem toBankItem({required String id}) => QuizBankItem(
    id: id,
    question: stem.trim(),
    type: QuizQuestionType.singleChoice,
    options: effectiveOptions,
    correctAnswer: answer.trim(),
    analysis: analysis,
    source: 'AI读屏',
    createdAt: capturedAt,
    imageUrl: imagePath,
    syncStatus: QuizSyncStatus.localOnly,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'stem': stem,
    'options': options,
    'answer': answer,
    'confidence': confidence,
    'capturedAt': capturedAt.toIso8601String(),
    'imagePath': imagePath,
    'analysis': analysis,
    'keepReason': keepReason,
  };

  static QuizVisionCandidate fromJson(Map<String, dynamic> json) =>
      QuizVisionCandidate(
        id: json['id']?.toString(),
        stem: json['stem']?.toString() ?? '',
        options:
            (json['options'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        answer: json['answer']?.toString() ?? '',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        capturedAt:
            DateTime.tryParse(json['capturedAt']?.toString() ?? '') ??
            DateTime.now(),
        imagePath: json['imagePath']?.toString(),
        analysis: json['analysis']?.toString(),
      );
}

/// 上报决策结果。
enum QuizVisionSubmitDecision {
  /// 满足全部闸门 → 静默异步上报后端待审核区。
  autoSubmit,

  /// 不满足闸门 → 只落本地留档，等用户手动补充。
  keepLocalOnly,
}
