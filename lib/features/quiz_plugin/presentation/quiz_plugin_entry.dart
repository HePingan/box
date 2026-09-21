import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../account/data/account_store.dart';
import '../../account/domain/account_models.dart';
import '../../../design_system/app_tokens.dart';
import '../../../utils/app_logger.dart';
import '../../policy/plugin_policy.dart';
import '../domain/ocr_quiz_parser.dart';
import '../domain/quiz_bank.dart';
import '../data/quiz_cloud_pull.dart';
import '../data/quiz_cloud_auto_sync.dart';
import '../domain/quiz_capture_session.dart';
import '../domain/quiz_config.dart';
import '../data/quiz_engine.dart';
import '../data/quiz_ocr_client.dart';
import '../data/quiz_vision_reporter.dart';
import '../domain/quiz_diag.dart';
import '../domain/quiz_search_policy.dart';
import '../domain/quiz_vision_endpoint.dart';
import '../utils/ai_process_bridge.dart';

part 'quiz_plugin_config_widgets.part.dart';
part 'quiz_plugin_region_widgets.part.dart';
part 'quiz_plugin_cloud_widgets.part.dart';
part 'quiz_plugin_overlay_format.part.dart';

/// 答题插件 - MethodChannel 名称
const String _kChannel = 'top.hpa888.box/quiz_plugin';

class _OcrEntrySaveResult {
  const _OcrEntrySaveResult({required this.status, required this.message});

  final QuizBankWriteStatus status;
  final String message;
}

class QuizOverlayDecision {
  const QuizOverlayDecision({
    required this.status,
    this.answerKey,
    this.lowConfidence = false,
  });

  final String status;
  final String? answerKey;
  final bool lowConfidence;
}

/// 答题插件入口
///
/// 功能：
/// 1. 配置页：开启/关闭、设置 API、主题色
/// 2. 控制原生无障碍服务 + 悬浮窗
/// 3. 手动搜题预览
class QuizPluginEntry {
  QuizPluginEntry._();

  static const MethodChannel _channel = MethodChannel(_kChannel);

  // 一键批量录入状态
  static bool _batchRunning = false;
  static int _batchSuccessCount = 0;
  static int _batchFailCount = 0;

  /// 自动搜题引擎
  static QuizEngine? _engineForAutoSearch;

  // B2: 题图区域 dHash 短期缓存。
  //
  // 搜题与「OCR 录入保存」是两次独立的异步链路，两者之间用户可能已翻页，
  // 二次截屏拿到的会是下一题的题图。缓存让同一道题的搜题与入库共用同一枚指纹，
  // 同时避免连续调用重复走 MethodChannel 截屏。
  static String? _imageRegionHashCache;
  static DateTime? _imageRegionHashCachedAt;
  static const Duration _imageRegionHashTtl = Duration(milliseconds: 300);

  /// 题图指纹缓存命中判定（TTL 内视为同一道题）。
  static bool get _imageRegionHashCacheFresh {
    final at = _imageRegionHashCachedAt;
    if (at == null) return false;
    return DateTime.now().difference(at) < _imageRegionHashTtl;
  }

  /// 清空题图指纹缓存（切题时调用，防止跨题复用）。
  static void invalidateImageRegionHashCache() {
    _imageRegionHashCache = null;
    _imageRegionHashCachedAt = null;
  }

  /// 带 TTL 缓存的题图区域 dHash 捕获。
  static Future<String?> captureImageRegionHashCached({
    bool debug = false,
  }) async {
    if (_imageRegionHashCacheFresh) {
      if (debug) {
        debugPrint('[QuizImageHash] cache hit');
      }
      return _imageRegionHashCache;
    }
    final stopwatch = Stopwatch()..start();
    final hash = await captureImageRegionHash();
    stopwatch.stop();
    _imageRegionHashCache = hash;
    _imageRegionHashCachedAt = DateTime.now();
    if (debug) {
      final valid = RegExp(r'^[0-9a-f]{16}$').hasMatch(hash ?? '');
      debugPrint(
        '[QuizImageHash] capture ${stopwatch.elapsedMilliseconds}ms '
        'valid=$valid',
      );
    }
    return hash;
  }

  /// 启动一键批量录入（Flutter侧触发）
  static Future<bool> startBatchEntry() async {
    try {
      await _channel.invokeMethod('batchStart');
      _batchRunning = true;
      _batchSuccessCount = 0;
      _batchFailCount = 0;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 停止一键批量录入
  static Future<void> stopBatchEntry() async {
    try {
      await _channel.invokeMethod('batchStop');
    } catch (_) {}
    _batchRunning = false;
  }

  /// 获取批量录入状态
  static Map<String, dynamic> getBatchStatus() => {
    'running': _batchRunning,
    'success': _batchSuccessCount,
    'fail': _batchFailCount,
  };

  // 配置持久化
  static const String _configKey = 'quiz_plugin_config';

  /// 异步截图请求归属：防止 OCR 自动搜题、录入和区域试识互相使用对方的截图。
  static final QuizCaptureSessionCoordinator _coordinator =
      QuizCaptureSessionCoordinator();

  static Future<QuizConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_configKey);
    if (raw == null || raw.isEmpty) return const QuizConfig();
    try {
      final decoded = jsonDecode(raw);
      return QuizConfig.fromJson(decoded as Map<String, dynamic>);
    } catch (_) {
      return const QuizConfig();
    }
  }

  static Future<void> saveConfig(QuizConfig config) async {
    // 远程禁止时强制落盘为关闭，防止本地开关绕过
    var toSave = config;
    final denial = await PluginGate.denial(
      PluginIds.quizAnswer,
      feature: PluginFeature.overlay,
      highRisk: true,
    );
    if (denial != null && config.enabled) {
      toSave = config.copyWith(enabled: false);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, jsonEncode(toSave.toJson()));
    // 通知无障碍服务：按新配置重算「离开 App 自动考试模式」
    try {
      await _channel.invokeMethod('onConfigChanged');
    } catch (_) {}
  }

  // 原生交互
  static Future<bool> isAccessibilityEnabled() async {
    try {
      return await _channel.invokeMethod('isAccessibilityEnabled') as bool;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestAccessibility() async {
    try {
      await _channel.invokeMethod('requestAccessibility');
    } catch (_) {}
  }

  static Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (_) {}
  }

  static Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod('requestNotificationPermission');
    } catch (_) {}
  }

  static Future<bool> setOverlayVisible(
    bool visible, {
    String displayMode = 'overlay',
  }) async {
    try {
      final result = await _channel.invokeMethod('setOverlayVisible', {
        'visible': visible,
        'displayMode': displayMode,
      });
      // 新版返回诊断 Map；兼容旧版返回 bool
      if (result is Map) {
        return result['visible'] as bool? ?? false;
      }
      return result as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 返回诊断信息（可见性 + 权限/失败原因），用于精准提示。
  static Future<Map<String, dynamic>> setOverlayVisibleWithDiag(
    bool visible, {
    String displayMode = 'overlay',
  }) async {
    try {
      final result = await _channel.invokeMethod('setOverlayVisible', {
        'visible': visible,
        'displayMode': displayMode,
      });
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {'visible': (result as bool? ?? false)};
    } catch (e) {
      return {'visible': false, 'reason': 'exception:$e'};
    }
  }

  static Future<bool> isOverlayVisible() async {
    try {
      return await _channel.invokeMethod('isOverlayVisible') as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasOverlayPermission() async {
    try {
      return await _channel.invokeMethod('hasOverlayPermission') as bool? ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> updateOverlayContent({
    required String question,
    String? answers,
    bool? isSearching,
    String displayMode = 'overlay',
    String? status,
    String? answerKey,
    int? similarity,
    int? matchIndex,
    int? matchCount,
    List<String>? answersList,
  }) async {
    try {
      // 关闭答题助手时不推送内容，避免答案悬浮窗再次弹出干扰 OCR 录入
      final cfg = await loadConfig();
      if (!cfg.enabled) return;
      final denial = await PluginGate.denial(
        PluginIds.quizAnswer,
        feature: PluginFeature.overlay,
      );
      if (denial != null) return;

      // status: idle | searching | hit | miss
      final resolvedStatus =
          status ??
          (isSearching == true
              ? 'searching'
              : (answers == null || answers.trim().isEmpty)
              ? 'idle'
              : (answers.contains('未找到') ||
                        answers.contains('失败') ||
                        answers.contains('未开启') ||
                        answers.contains('未命中')
                    ? 'miss'
                    : 'hit'));
      await _channel.invokeMethod('updateOverlayContent', {
        'question': question,
        'displayMode': displayMode,
        'answers': ?answers,
        'isSearching': ?isSearching,
        'status': resolvedStatus,
        'answerKey': ?answerKey,
        if (similarity != null) 'similarity': similarity.clamp(0, 100),
        'matchIndex': ?matchIndex,
        'matchCount': ?matchCount,
        'answersList': ?answersList,
      });
    } catch (_) {}
  }

  /// 拉起原生悬浮窗框选。返回 false 表示无障碍服务未运行、无法进入框选。
  static Future<bool> openRegionSelector() async {
    try {
      final opened = await _channel.invokeMethod('openRegionSelector');
      return opened == true;
    } catch (_) {
      return false;
    }
  }

  /// 推送 AI 作答过程文本到答题悬浮窗（显示在答案下方）。
  /// 传空串可清空并隐藏该区块。
  static Future<void> pushAiProcess(String text) =>
      AiProcessBridge.push(text);

  /// 设置答案悬浮窗透明度（0.3~1.0）。
  static Future<void> setOverlayOpacity(double opacity) async {
    try {
      await _channel.invokeMethod('setOverlayOpacity', {
        'opacity': opacity.clamp(0.3, 1.0),
      });
    } catch (_) {}
  }

  /// 设置普通答题悬浮窗宽高（逻辑像素 dp），考试模式由独立档位控制。
  static Future<void> setOverlaySize(double widthDp, double heightDp) async {
    try {
      await _channel.invokeMethod('setOverlaySize', {
        'widthDp': widthDp.clamp(240, 640),
        'heightDp': heightDp.clamp(140, 720),
      });
    } catch (_) {}
  }

  static Future<void> resetOverlaySize() async {
    try {
      await _channel.invokeMethod('resetOverlaySize');
    } catch (_) {}
  }

  /// 请无障碍服务截屏识别区域，返回 PNG 字节（失败返回 null）。
  ///
  /// 原生在同一个 MethodChannel 调用完成时回传本次字节；Dart 侧再用
  /// [QuizCaptureSessionCoordinator] 校验 requestId，防止并发 OCR/录入/试识串图。
  static Future<Uint8List?> captureRegionScreenshot() async {
    final requestId = _coordinator.begin();
    try {
      final raw = await _channel.invokeMethod('captureRegionScreenshot', {
        'requestId': requestId,
      });
      if (raw == null) return null;
      // 原生侧返回 {bytes: Uint8List, dHash: String}
      if (raw is Map) {
        final bytes = _bytesFromRaw(raw['bytes']);
        if (bytes == null || bytes.isEmpty) return null;
        if (!_coordinator.accept(requestId, bytes)) return null;
        final taken = _coordinator.take(requestId);
        if (taken == null || taken.isEmpty) return null;
        return Uint8List.fromList(taken);
      }
      final bytes = _bytesFromRaw(raw);
      if (bytes == null || bytes.isEmpty) return null;
      if (!_coordinator.accept(requestId, bytes)) return null;
      final taken = _coordinator.take(requestId);
      if (taken == null || taken.isEmpty) return null;
      return Uint8List.fromList(taken);
    } catch (_) {
      // 截图不可用由调用方展示对应状态。
    }
    return null;
  }

  /// 请无障碍服务截屏识别区域，返回 PNG 字节 + dHash（失败返回 null）。
  static Future<MapEntry<Uint8List?, String?>?>
  captureRegionScreenshotWithHash() async {
    final requestId = _coordinator.begin();
    try {
      final raw = await _channel.invokeMethod('captureRegionScreenshot', {
        'requestId': requestId,
      });
      if (raw == null || raw is! Map) return null;
      final bytesRaw = raw['bytes'];
      final dHash = raw['dHash'] as String?;
      final bytes = _bytesFromRaw(bytesRaw);
      if (bytes == null || bytes.isEmpty) return null;
      if (!_coordinator.accept(requestId, bytes)) return null;
      final taken = _coordinator.take(requestId);
      if (taken == null || taken.isEmpty) return null;
      return MapEntry(Uint8List.fromList(taken), dHash);
    } catch (_) {
      // 截图不可用由调用方展示对应状态。
    }
    return null;
  }

  /// 更新识别区域。
  static Future<void> updateRegion(Rect region) async {
    try {
      await _channel.invokeMethod('updateRegion', {
        'left': region.left.toDouble(),
        'top': region.top.toDouble(),
        'right': region.right.toDouble(),
        'bottom': region.bottom.toDouble(),
      });
    } catch (_) {}
  }

  /// 应用识别区域预设（比例 0~1）。
  static Future<void> applyRegionPreset(Rect rectF) async {
    try {
      await _channel.invokeMethod('applyRegionPreset', {
        'left': rectF.left,
        'top': rectF.top,
        'right': rectF.right,
        'bottom': rectF.bottom,
      });
    } catch (_) {}
  }

  /// 标题相似度取结构化置信度，正文正则仅为旧数据兼容回退。
  static int? similarityPercentForAnswer(QuizAnswer answer) {
    final confidence = answer.confidence;
    if (confidence.isFinite && confidence > 0) {
      return (confidence * 100).round().clamp(0, 100);
    }
    return int.tryParse(
      RegExp(r'相似度\s*[:：]?\s*(\d{1,3})').firstMatch(answer.text)?.group(1) ??
          '',
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // 悬浮窗标题栏排版（2026-09-13 用户拍板 B 档）
  //
  // 真因：AI 读屏按钮加成第 5 个后，标题栏固定需求 216dp（徽章 56 + 5×(26+4)
  // + 右内边距 6），而悬浮窗在真机上只有 137~175dp（defaultOverlaySize 的
  // coerceIn 用了像素而非 dp），最右侧「小眼睛」被裁掉。
  //
  // 修法：相似度徽章搬离标题栏，标题栏只留 AI读屏/眼睛/关闭，
  // 「区域」「录入」收进溢出菜单。下方常量与 Kotlin 侧 quiz_overlay.xml 必须
  // 保持一致 —— 改一处要改两处，单测是防止漂移的唯一护栏。
  // ───────────────────────────────────────────────────────────────────────

  /// 单个标题栏按钮宽度（dp）。与 `quiz_overlay.xml` 中 ImageButton 一致。
  static const int overlayTitleButtonDp = 26;

  /// 标题栏按钮之间的间距（dp）。
  static const int overlayTitleButtonMarginDp = 2;

  /// 标题栏右内边距（dp）。
  static const int overlayTitleBarPaddingEndDp = 4;

  /// 紧凑标题栏按钮顺序：眼睛必须留栏内（用户拍板：点击眼睛隐藏悬浮窗）。
  static const List<String> overlayTitleBarKeys = <String>[
    'aiVision',
    'hideOverlay',
    'close',
  ];

  /// 收进溢出菜单的低频动作：区域选择、一键录入。
  static const List<String> overlayOverflowMenuKeys = <String>[
    'area',
    'quizEntry',
  ];

  /// 紧凑标题栏固定宽度需求（dp）＝ 3×26 + 3×2 + 4 = 88。
  static int get overlayTitleBarWidthDp =>
      overlayTitleBarKeys.length *
              (overlayTitleButtonDp + overlayTitleButtonMarginDp) +
          overlayTitleBarPaddingEndDp;

  /// 旧布局（徽章 56 + 5 键）固定宽度需求，仅用于回归测试留证。
  static int get overlayLegacyTitleBarWidthDp =>
      56 + 4 + 5 * (26 + 4) + 6;

  /// 标题栏在给定悬浮窗宽度下是否放得下（左侧拖动留白可压缩到 0）。
  ///
  /// [widthDp] 默认取紧凑布局需求，可传旧布局值做回归对照。
  static bool overlayTitleBarFits({
    required double windowWidthDp,
    int? widthDp,
  }) {
    final need = widthDp ?? overlayTitleBarWidthDp;
    return windowWidthDp >= need;
  }

  /// 标题栏富余宽度（dp），负数表示溢出（眼睛会被裁掉）。
  static double overlayTitleBarSlackDp({
    required double windowWidthDp,
    int? widthDp,
  }) =>
      windowWidthDp - (widthDp ?? overlayTitleBarWidthDp);

  // ───────────────────────────────────────────────────────────────────────
  // 大模型读屏进度文案（2026-09-13 用户拍板 A 档）
  //
  // 最坏要等满 45s（截图 → 压缩 → 退避 2s/5s/10s/15s 重试）。
  // 静态一句「最长约 45 秒」用户会以为卡死，按已等待时长分三档给预期。
  // ───────────────────────────────────────────────────────────────────────

  /// 已等待秒数（徽章倒计时用）。未满 1 秒不进位，避免 0s 直接跳 1s。
  static int visionElapsedSeconds(Duration elapsed) {
    final s = elapsed.inMilliseconds / 1000;
    return s < 0 ? 0 : s.floor();
  }

  /// 按已等待时长给出阶段文案；任何时长都返回非空兜底。
  static String visionProgressText(Duration elapsed) {
    final s = visionElapsedSeconds(elapsed);
    if (s < 3) {
      return '正在识别题目…';
    }
    if (s < 15) {
      return '正在请求大模型（首次较慢，请稍候）…';
    }
    if (s < 45) {
      return '仍在重试（网络波动，最长约 45 秒）…';
    }
    return '等待超时，可重新点击 AI 读屏重试。';
  }

  // ───────────────────────────────────────────────────────────────────────
  // 悬浮窗第二轮视觉优化（2026-09-13 用户反馈「有点丑」+「AI 按钮没显示」）
  // ───────────────────────────────────────────────────────────────────────

  /// 未命中引导文案：本地/OCR 都没搜到时的正文提示，明确指向 AI 读屏。
  ///
  /// 用户诉求原话：「搜不出这道题时，加入提示请点击大模型按钮进行联网搜题」。
  /// 关键：必须说清**按钮在哪 + 长什么样**（右上角紫色「AI」胶囊），
  /// 正在读屏时不能再说「点击」，否则用户会重复点导致重复请求。
  static String visionMissHint({required bool isVisionRunning}) {
    if (isVisionRunning) {
      return '正在用 AI 联网读屏识别，请稍候…';
    }
    return '未搜到答案。点右上角紫色 AI 按钮，用 AI 联网搜题。';
  }

  /// 标题栏内联相似度胶囊文案。取代原独立 `status_row`（那条白底+蓝块很割裂）。
  ///
  /// 约束：必须短（≤6 字符），否则窄机型标题栏又被挤爆（本轮已修过一次）。
  static String similarityPillText(int? percent,
      {required bool hit, bool searching = false}) {
    if (searching) {
      return '读屏中';
    }
    if (!hit || percent == null) {
      return '未命中';
    }
    return '$percent%';
  }

  /// 胶囊品牌色（随状态变化，让用户扫一眼就知道结果好坏）。
  /// 返回 ARGB 十六进制字符串，Kotlin 侧直接 `Color.parseColor`。
  static String similarityPillColor(int? percent,
      {required bool hit, bool searching = false}) {
    if (searching) {
      return '#F59E0B'; // 琥珀：与读屏进度条同色，表示进行中
    }
    if (!hit || percent == null) {
      return '#98A2B3'; // 中性灰：无结果
    }
    return '#12B76A'; // 绿：命中
  }

  static int _searchGeneration = 0;
  static String _activeQuestionFingerprint = '';

  /// 高质量命中才短路同题刷新；半题/低分命中允许选项补齐后纠错。
  static final QuizSearchPolicy _searchPolicy = QuizSearchPolicy();
  static Timer? _captureDebounce;

  /// 题目指纹：题干优先，去掉空白/题号/选项行，避免选项逐步加载时误判新题。
  /// 由 OCR 原始文本推导「搜索指纹/题干」。
  ///
  /// 可见性放开（原 `_questionFingerprint`）仅为让单测直接覆盖真实实现，
  /// 避免测试里复制一份等价逻辑导致口径漂移（历史缺陷：同类逻辑散落多处）。
  @visibleForTesting
  static String questionFingerprint(String raw) => _questionFingerprint(raw);

  static String _questionFingerprint(String raw) {
    final parsed = OcrQuizParser.parse(raw);
    var q = parsed.question.trim();
    if (q.isEmpty) {
      // 真机 1.18.9 (232) 日志（2026-09-12T21:19:20~21:19:28）暴露的真根因：
      // 用户答完题后 App 跳到「解析页」，采集抓到该帧。此时屏幕上**没有题干**，
      // 解析器已正确判空；但原兜底会取「第一个非选项行」→ 拿到「本题技巧」
      // 这类页面区块标记，产出 fp=本题技巧 去全量检索：必然不中，
      // 且把假指纹写进节流状态（日志里 THROTTLE 指纹不匹配 attempt=51 now=4）。
      //
      // 正确语义：整帧只剩解析页结构文字时，**放弃本次检索**，返回空指纹，
      // 由调用方（_runSearch 的 fingerprint.isEmpty 分支）静默跳过。
      // 宁可不搜，也不要拿假题干去搜 —— 假题干只会污染状态并误导后续判断。
      if (OcrQuizParser.hasNoQuestionCandidate(raw)) return '';
      q = OcrQuizParser.firstQuestionCandidateLine(raw);
    }
    if (q.isEmpty) return '';
    return QuizBankTextNormalizer.cleanForMatch(q);
  }

  static bool _isCurrentRequest(int generation, String fingerprint) =>
      generation == _searchGeneration &&
      fingerprint.isNotEmpty &&
      fingerprint == _activeQuestionFingerprint;

  /// 新题第一时间废弃旧答案，考试模式会显示「新题 · 检索中」。
  static Future<void> _showNewQuestionSearching(
    String question,
    QuizConfig config,
  ) {
    // 新题开始检索 → 先清掉上一题的 AI 作答过程，避免串题（用户会以为
    // 过程属于当前这题）。若本次走 AI 搜题，quiz_engine 随后会重新推送。
    AiProcessBridge.clear();
    return _pushOverlay(
      question: question,
      answers: '新题 · 检索中…',
      displayMode: config.displayMode,
      status: 'searching',
      isSearching: true,
      answerKey: '',
      matchIndex: 0,
      matchCount: 1,
      answersList: const [],
    );
  }

  /// 同题重复检索节流：委托给 QuizSearchPolicy（单一事实源）。
  ///
  /// 只拦截「已有成功结果」的完全重复请求。首次请求失败/未完成时必须放行，
  /// 否则冷启动时题库未加载完的首搜会连同紧随的重试一起被吞掉，
  /// 悬浮窗永久停在「检索中」——这正是「第一题一直不出答案」的根因。
  static bool _shouldSkipDuplicateSearch(
    String question,
    String method,
    List<String> probeOptions,
  ) {
    if (method == 'manualSearch') return false;
    return _searchPolicy.shouldSuppressThrottled(
      stem: question,
      options: probeOptions,
    );
  }

  static Future<void> _pushOverlay({
    required String question,
    required String answers,
    required String displayMode,
    required String status,
    String? answerKey,
    int? similarity,
    int matchIndex = 0,
    int matchCount = 1,
    bool isSearching = false,
    List<String>? answersList,
  }) {
    return updateOverlayContent(
      question: question,
      answers: answers,
      isSearching: isSearching,
      displayMode: displayMode,
      status: status,
      answerKey: answerKey,
      similarity: similarity,
      matchIndex: matchIndex,
      matchCount: matchCount,
      answersList: answersList,
    );
  }

  static Future<void> _handleCapturedQuestion(
    String question,
    String method,
  ) async {
    final captured = question.trim();
    if (captured.isEmpty) return;
    final config = await loadConfig();
    if (!config.enabled && method != 'manualSearch') return;
    final denial = await PluginGate.denial(
      PluginIds.quizAnswer,
      feature: PluginFeature.search,
    );
    if (denial != null) {
      if (method == 'manualSearch') {
        await updateOverlayContent(
          question: captured,
          answers: denial,
          isSearching: false,
          displayMode: config.displayMode,
        );
      }
      return;
    }

    final shouldSearch = method == 'manualSearch' || config.autoSearch;
    if (!shouldSearch) {
      await updateOverlayContent(
        question: captured,
        answers: '已捕获题目，自动搜题已关闭',
        isSearching: false,
        displayMode: config.displayMode,
      );
      return;
    }

    final fingerprint = _questionFingerprint(captured);
    if (fingerprint.isEmpty) return;
    final parsedCapture = OcrQuizParser.parse(captured);
    final captureOptions = parsedCapture.options;
    // 图片题常有相同题干和选项，切题身份必须包含当前题图指纹。
    // 捕获入口强制刷新一次，避免快速翻题复用上一题的短时缓存。
    invalidateImageRegionHashCache();
    final capturedImageHash = await _captureImageHashForDisambiguation(config);
    final requestFingerprint = capturedImageHash == null
        ? fingerprint
        : '$fingerprint|image:$capturedImageHash';
    // 同题的可靠命中才抑制刷新；选项补齐/变化、题图变化与手动刷新允许纠错。
    //
    // 真机 1.18.15 (238) 录屏（2026-09-13 11:55）修「回滑就识别不出来」：
    // 用户回滑到一道**曾命中并锁定**的题时，shouldSuppress 返回 true 并直接
    // return —— 但此刻悬浮窗里装的可能是**后一题**的答案（录屏实证：屏幕题干
    // 是「图中地面标记表示」，悬浮窗却是「向侧滑的反方向转动方向盘适量修正」）。
    // 跳过检索可以，但**不能连重绘一起跳过**，否则悬浮窗永远停在别题答案上。
    //
    // 语义修正：节流省的是"重新检索"（算力），不是"重绘"（画面正确性）。
    // 回滑到已锁定题时，走一次重绘 —— 该题在本题库命中（日志实测 7ms、src=localBank），
    // 代价可忽略，换来画面与题干始终一致。
    final isRecapture = _searchPolicy.shouldRedrawOnRecapture(
      stem: fingerprint,
      options: captureOptions,
      imageHash: capturedImageHash,
    );
    if (_searchPolicy.shouldSuppress(
      stem: fingerprint,
      options: captureOptions,
      imageHash: capturedImageHash,
      manualRefresh: method == 'manualSearch',
    )) {
      if (!isRecapture) return;
      // 回滑重绘：绕过节流，把这一题自己的答案重新渲染（内部仍走题库本地命中）。
      QuizDiag.log(QuizDiagStage.throttle, '回滑重绘：同题重复捕获，跳过检索但强制刷新画面');
    }
    final isNewQuestion = requestFingerprint != _activeQuestionFingerprint;
    if (isNewQuestion) {
      // 新题立即让旧答案失效；任何旧请求回来都会因 generation 不一致被丢弃。
      _activeQuestionFingerprint = requestFingerprint;
      final generation = ++_searchGeneration;
      _captureDebounce?.cancel();
      await _showNewQuestionSearching(captured, config);
      // 等页面题干/选项稳定，避免翻题动画中抓到半截内容；远小于旧 900/1800ms 节流。
      _captureDebounce = Timer(const Duration(milliseconds: 240), () {
        _runSearch(
          question: captured,
          config: config,
          method: method,
          forceRedraw: isRecapture,
          probeOptions: captureOptions,
          imageHash: capturedImageHash,
          requestGeneration: generation,
          requestFingerprint: requestFingerprint,
        );
      });
      return;
    }

    // 同题内容变化（选项/解析渐进加载）不重新清答案，仍受重复保护。
    await _runSearch(
      question: captured,
      config: config,
      method: method,
      forceRedraw: isRecapture,
      probeOptions: captureOptions,
      imageHash: capturedImageHash,
      requestFingerprint: requestFingerprint,
    );
  }

  static void _recordSuccessfulResult({
    required String fingerprint,
    required List<String> probeOptions,
    required QuizResult result,
    String? imageHash,
  }) {
    final detail = result.answers.isEmpty ? '' : result.answers.first.text;
    final qScore =
        RegExp(r'相似度\s*[:：]?\s*(\d{1,3})').firstMatch(detail)?.group(1) ?? '0';
    final optionScore =
        RegExp(r'选项(?:决胜)?\s*(\d{1,3})%').firstMatch(detail)?.group(1) ?? '0';
    final source = result.source.contains('本地题库')
        ? QuizResultSource.localBank
        : result.source.contains('OCR')
        ? QuizResultSource.ocrLocalBank
        : QuizResultSource.externalApi;
    _searchPolicy.recordSuccess(
      stem: fingerprint,
      options: probeOptions,
      source: source,
      questionScore: (int.tryParse(qScore) ?? 0).clamp(0, 100).toInt(),
      optionScore: (int.tryParse(optionScore) ?? 0).clamp(0, 100).toInt(),
      imageHash: imageHash,
    );
  }

  /// 真正的搜题执行：按开关路由（无障碍文本 / OCR 截图），二者可并存。
  /// [probeOptions]：试捕解析出的选项，参与题库匹配与相似度计算。
  static Future<void> _runSearch({
    required String question,
    required QuizConfig config,
    required String method,
    bool fromOcr = false,
    bool forceRedraw = false,
    List<String> probeOptions = const [],
    String? imageHash,
    int? requestGeneration,
    String? requestFingerprint,
  }) async {
    final captured = question.trim();
    if (captured.isEmpty) return;
    final fingerprint = requestFingerprint ?? _questionFingerprint(captured);
    if (fingerprint.isEmpty) return;
    var generation = requestGeneration;
    if (generation == null) {
      // 手动/试捕入口也纳入版本控制，避免与自动捕获的旧请求串结果。
      if (fingerprint != _activeQuestionFingerprint) {
        _activeQuestionFingerprint = fingerprint;
        // B2: 切题时失效题图 dHash 缓存，防止跨题复用上一题的指纹。
        invalidateImageRegionHashCache();
        // 切题必须清掉上一题的来源排名/节流状态，否则上一题命中
        // localBank(rank=4) 后，新题更低秩的来源会被 canReplaceWith 拦掉，
        // 悬浮窗永远停在「检索中」（2026-09-12 三轮报障根因）。
        _searchPolicy.resetForNewQuestion();
        _searchGeneration++;
      }
      generation = _searchGeneration;
    }
    final currentGeneration = generation;
    if (!_isCurrentRequest(currentGeneration, fingerprint)) {
      return;
    }
    // 回滑重绘必须绕过节流：本题已有锁定答案，节流会把它当"完全重复"吞掉，
    // 而此刻悬浮窗显示的可能正是别的题的答案。
    if (!forceRedraw && _shouldSkipDuplicateSearch(fingerprint, method, probeOptions)) {
      return;
    }
    // 记录「本次即将发起」的请求。只有它产出成功结果后，窗口内的完全重复
    // 才会被节流；未成功时放行重试，避免首题卡在「检索中」。
    // 注意：与 `_recordSuccessfulResult` 必须传**同一个口径**的指纹
    // （都用 _questionFingerprint 的结果），否则两边归一化不同
    // （原始文本会带上 A./B. 选项行）会让节流判定恒不相等而彻底失效。
    _searchPolicy.recordAttempt(stem: fingerprint, options: probeOptions);

    if (!fromOcr) {
      // 试捕 / 手动搜 / 无障碍捕获：有文本就先走题库（题干+选项）
      final preferText =
          method == 'manualSearch' ||
          method == 'searchWithProbeText' ||
          config.accessibilityCapture;
      if (preferText) {
        final optHint = probeOptions.isEmpty
            ? ''
            : '\n试捕选项 ${probeOptions.length} 个：${probeOptions.take(4).join(' / ')}';
        // 回滑重绘：本题答案已知，**不要**再闪一次"检索中" ——
        // 用户报障的观感正是"回滑后悬浮窗还停在检索中/别题答案"。直接复用本地命中结果。
        if (!forceRedraw) {
          await _pushOverlay(
            question: config.debugCapture ? '调试捕获：正在用下方文本搜题' : captured,
            answers: config.debugCapture
                ? '${_formatDebugCapture(captured)}$optHint\n\n正在搜题（题干+选项）...'
                : '正在搜题（题干+选项）...',
            displayMode: config.displayMode,
            status: 'searching',
            isSearching: true,
          );
        }
        final engine = _engineForAutoSearch ??= QuizEngine(config: config);
        engine.config = config;
        imageHash ??= await _captureImageHashForDisambiguation(config);
        if (!_isCurrentRequest(currentGeneration, fingerprint)) return;
        QuizDiag.log(QuizDiagStage.result, 'engine.search 发起',
            fields: {'fp': fingerprint, 'probeOpts': probeOptions.length});
        final sw = Stopwatch()..start();
        final result = await engine.search(
          captured,
          forceExternalSearch: method == 'manualSearch',
          probeOptions: probeOptions,
          imagePerceptualHash: imageHash,
        );
        sw.stop();
        QuizDiag.log(
          QuizDiagStage.result,
          'engine.search 返回',
          fields: {
            'ok': result.isSuccess,
            'ms': sw.elapsedMilliseconds,
            'src': result.isSuccess ? _sourceForResult(result).name : '-',
          },
          level: result.isSuccess ? LogLevel.info : LogLevel.warn,
        );
        // 搜题期间已经切到新题：禁止旧结果覆盖当前“新题检索中”。
        if (!_isCurrentRequest(currentGeneration, fingerprint)) {
          QuizDiag.warn(QuizDiagStage.result, '丢弃：检索期间已切题',
              fields: {'fp': fingerprint});
          return;
        }
        if (!result.isSuccess) {
          QuizDiag.warn(QuizDiagStage.result, '无结果：引擎未命中，悬浮窗停在检索中');
        }
        if (result.isSuccess) {
          final source = _sourceForResult(result);
          // 低优先级结果不能覆盖已展示的高质量命中（如外部 API 盖过本地题库）。
          if (!_searchPolicy.canReplaceWith(source, stem: fingerprint)) {
            // 这里静默 return 是「一直检索中」的直接成因，必须留痕。
            QuizDiag.warn(QuizDiagStage.result,
                '丢弃：低优先级来源不得覆盖已展示结果（悬浮窗保持原样）',
                fields: {'src': source.name, 'fp': fingerprint});
            return;
          }
          _recordSuccessfulResult(
            fingerprint: _questionFingerprint(captured),
            probeOptions: probeOptions,
            result: result,
            imageHash: imageHash,
          );
          final list = _answersListForOverlay(result);
          final ambiguity = overlayDecisionForResult(result, list);
          final ambiguousText = ambiguity.status == 'ambiguous'
              ? ambiguousCandidatesForOverlay(result)
              : null;
          // 同题干爆炸（标志图题）：不端任何候选，明确要求对照题图作答。
          final imageQuestionText = ambiguity.status == 'imageQuestion'
              ? imageQuestionOverlayBody(result)
              : null;
          final overlayList = imageQuestionText != null
              ? <String>[imageQuestionText]
              : ambiguousText == null
                  ? list
                  : <String>[ambiguousText];
          final overlayAnswers = imageQuestionText ??
              ambiguousText ??
              (overlayList.isNotEmpty
                  ? _withSimilarityMarker(overlayList.first, result)
                  : _withSimilarityMarker(
                      _formatResultForOverlay(result),
                      result,
                    ));
          await _pushOverlay(
            question: captured,
            answers: config.debugCapture
                ? '$overlayAnswers\n\n--- 调试捕获文本 ---\n${_formatDebugCapture(captured)}'
                : overlayAnswers,
            displayMode: config.displayMode,
            status: ambiguity.status,
            answerKey: ambiguity.answerKey,
            similarity: _similarityForResult(result),
            matchIndex: 0,
            matchCount: overlayList.isNotEmpty
                ? overlayList.length
                : result.answers.length.clamp(1, 9),
            answersList: overlayList,
          );
          return;
        }
        // 文本未命中：若 OCR 开启则兜底，否则展示失败
        if (!config.ocrSearch) {
          // OCR 未开启也要给读屏一次机会（用户拍板：所有本地未命中的题）。
          if (config.allowExternalApi && config.apiUrl.trim().isNotEmpty) {
            final visionOnly = await _tryVisionFallback(
              config,
              _engineForAutoSearch ??= QuizEngine(config: config),
              hintQuestion: captured,
              requestGeneration: currentGeneration,
              requestFingerprint: fingerprint,
            );
            if (!_isCurrentRequest(currentGeneration, fingerprint)) return;
            if (visionOnly != null && visionOnly.isSuccess) {
              await _pushOverlay(
                question: visionOnly.question.isNotEmpty
                    ? visionOnly.question
                    : captured,
                answers: _withSimilarityMarker(
                  _answersListForOverlay(visionOnly).isNotEmpty
                      ? _answersListForOverlay(visionOnly).first
                      : _formatResultForOverlay(visionOnly),
                  visionOnly,
                ),
                displayMode: config.displayMode,
                status: overlayDecisionForResult(
                  visionOnly,
                  _answersListForOverlay(visionOnly),
                ).status,
                answerKey: overlayDecisionForResult(
                  visionOnly,
                  _answersListForOverlay(visionOnly),
                ).answerKey,
                similarity: _similarityForResult(visionOnly),
                matchIndex: 0,
                matchCount: _answersListForOverlay(visionOnly).length.clamp(1, 9),
                answersList: _answersListForOverlay(visionOnly),
              );
              return;
            }
          }
          await _pushOverlay(
            question: captured,
            answers: _visionFailureHint(null),
            displayMode: config.displayMode,
            status: 'miss',
          );
          return;
        }
      } else if (!config.ocrSearch) {
        await _pushOverlay(
          question: captured,
          answers: '未开启任何搜题方式',
          displayMode: config.displayMode,
          status: 'miss',
        );
        return;
      }
    }

    // OCR 截图链路（兜底）
    if (config.ocrSearch) {
      final ocrResult = await _tryOcrFallback(
        config,
        _engineForAutoSearch ??= QuizEngine(config: config),
        seedOptions: probeOptions,
        requestGeneration: currentGeneration,
        requestFingerprint: fingerprint,
      );
      if (!_isCurrentRequest(currentGeneration, fingerprint)) return;
      if (ocrResult != null) {
        if (ocrResult.isSuccess) {
          final source = _sourceForResult(ocrResult);
          if (!_searchPolicy.canReplaceWith(source, stem: fingerprint)) {
            QuizDiag.warn(QuizDiagStage.result,
                '丢弃：OCR 兜底结果被来源排名拦下',
                fields: {'src': source.name, 'fp': fingerprint});
            return;
          }
          _recordSuccessfulResult(
            fingerprint: _questionFingerprint(captured),
            probeOptions: probeOptions,
            result: ocrResult,
            imageHash: imageHash,
          );
        }
        final list = _answersListForOverlay(ocrResult);
        final ambiguity = overlayDecisionForResult(ocrResult, list);
        final ambiguousText =
            ocrResult.isSuccess && ambiguity.status == 'ambiguous'
            ? ambiguousCandidatesForOverlay(ocrResult)
            : null;
        final overlayList = ambiguousText == null
            ? list
            : <String>[ambiguousText];
        final overlayAnswers =
            ambiguousText ??
            (overlayList.isNotEmpty
                ? _withSimilarityMarker(overlayList.first, ocrResult)
                : _withSimilarityMarker(
                    _formatResultForOverlay(ocrResult),
                    ocrResult,
                  ));
        await _pushOverlay(
          question: ocrResult.question,
          answers: overlayAnswers,
          displayMode: config.displayMode,
          status: ocrResult.isSuccess ? ambiguity.status : 'miss',
          answerKey: ocrResult.isSuccess ? ambiguity.answerKey : null,
          similarity: _similarityForResult(ocrResult),
          matchIndex: 0,
          matchCount: overlayList.isNotEmpty
              ? overlayList.length
              : ocrResult.answers.length.clamp(1, 9),
          answersList: overlayList,
        );
        return;
      }
      if (!config.accessibilityCapture) {
        await _pushOverlay(
          question: captured,
          answers: 'OCR 识别失败，且未开启无障碍读屏搜题',
          displayMode: config.displayMode,
          status: 'miss',
        );
        return;
      }
    }

    // AI 读屏兜底（B 档）：走到这里说明题干搜本地库未命中、OCR 文字搜也未命中。
    // 用户 2026-09-13 拍板「所有本地未命中的题」都交给大模型读屏。
    final visionResult = await _tryVisionFallback(
      config,
      _engineForAutoSearch ??= QuizEngine(config: config),
      hintQuestion: captured,
      requestGeneration: currentGeneration,
      requestFingerprint: fingerprint,
    );
    if (!_isCurrentRequest(currentGeneration, fingerprint)) return;
    if (visionResult != null && visionResult.isSuccess) {
      final source = _sourceForResult(visionResult);
      if (!_searchPolicy.canReplaceWith(source, stem: fingerprint)) {
        QuizDiag.warn(QuizDiagStage.result, '丢弃：读屏结果被来源排名拦下',
            fields: {'src': source.name, 'fp': fingerprint});
        return;
      }
      _recordSuccessfulResult(
        fingerprint: _questionFingerprint(captured),
        probeOptions: probeOptions,
        result: visionResult,
        imageHash: imageHash,
      );
      final list = _answersListForOverlay(visionResult);
      final ambiguity = overlayDecisionForResult(visionResult, list);
      final ambiguousText = ambiguity.status == 'ambiguous'
          ? ambiguousCandidatesForOverlay(visionResult)
          : null;
      final overlayList = ambiguousText == null
          ? list
          : <String>[ambiguousText];
      final overlayAnswers = ambiguousText ??
          (overlayList.isNotEmpty
              ? _withSimilarityMarker(overlayList.first, visionResult)
              : _withSimilarityMarker(
                  _formatResultForOverlay(visionResult),
                  visionResult,
                ));
      await _pushOverlay(
        question: visionResult.question.isNotEmpty ? visionResult.question : captured,
        answers: overlayAnswers,
        displayMode: config.displayMode,
        status: ambiguity.status,
        answerKey: ambiguity.answerKey,
        similarity: _similarityForResult(visionResult),
        matchIndex: 0,
        matchCount: overlayList.isNotEmpty
            ? overlayList.length
            : visionResult.answers.length.clamp(1, 9),
        answersList: overlayList,
      );
      return;
    }

    // 读屏也未产出：如实告知，绝不编造答案。
    await _pushOverlay(
      question: captured,
      answers: _visionFailureHint(visionResult),
      displayMode: config.displayMode,
      status: 'miss',
    );
  }

  /// 读屏失败时给用户看的兜底文案。
  ///
  /// 刻意区分「未开启」与「已开启但失败」：前者是配置问题（引导去设置），
  /// 后者是链路问题（如实说明原因，不能让用户以为题库没这道题）。
  ///
  /// 2026-09-13 报障教训：原先无论何种原因都显示「未搜到答案（本地题库未命中）」，
  /// 用户据此以为「开关开了但没工作」—— 其实当时是 `apiUrl` 为空被静默跳过。
  /// 现在一律区分：是**没开启**、**没拿到截图**、还是**模型真的没答出来**。
  static String _visionFailureHint(QuizResult? visionResult) {
    final err = visionResult?.error ?? '';
    if (err.isEmpty) {
      // 用户 2026-09-13 诉求：「搜不出这道题时，加入提示请点击大模型按钮进行联网搜题」。
      // 只说「未搜到」用户不知道下一步做什么，必须指路到 AI 按钮。
      return visionMissHint(isVisionRunning: false);
    }
    return 'AI 读屏未成功：$err\n可稍后重试，或点右上角紫色 AI 按钮联网搜题。';
  }

  /// 手动搜索（悬浮窗搜索按钮）：把题目带回 Dart 真正执行搜题。
  static Future<void> manualSearch(
    String question, {
    List<String> probeOptions = const [],
  }) async {
    final config = await loadConfig();
    await _runSearch(
      question: question,
      config: config,
      method: 'manualSearch',
      probeOptions: probeOptions,
    );
  }

  /// 手动 AI 读屏（悬浮窗「AI 读屏」按键）：跳过本地/OCR，直接截图交给大模型。
  ///
  /// 用户诉求原话：「答题悬浮窗上面加一个按键，手动启用大模型搜题」。
  /// 设计要点：
  ///   - **不读 `autoSearch`**：手动键就是用户明确要求，必须执行；
  ///   - **不做本地预搜**：用户点这个键的场景就是本地搜不到，再搜一遍纯浪费 3~15s；
  ///   - **仍需 `allowExternalApi`**：读屏是外部请求 + 花钱，必须用户显式授权过；
  ///     未授权时如实提示去设置开启，不静默失败（这正是本次报障的成因）。
  static Future<void> visionSearch(
    String question, {
    List<String> probeOptions = const [],
  }) async {
    final captured = question.trim();
    if (captured.isEmpty) return;
    final config = await loadConfig();
    if (!visionFallbackEnabled(config)) {
      await _pushOverlay(
        question: captured,
        answers: '请在「设置 → 答题插件 → 允许外部网络搜题」中开启后重试。',
        displayMode: config.displayMode,
        status: 'miss',
      );
      return;
    }

    // 与 manualSearch 同口径：接入既有请求版本控制，避免与自动捕获串结果。
    // 走 _runSearch 的 generation 分支（传 requestGeneration: null），
    // 由它负责切题失效缓存 / 重置来源排名 / 递增 _searchGeneration。
    _activeQuestionFingerprint = _questionFingerprint(captured);
    final fingerprint = _activeQuestionFingerprint;
    if (fingerprint.isEmpty) return;
    invalidateImageRegionHashCache();
    _searchPolicy.resetForNewQuestion();
    _searchGeneration++;
    final generation = _searchGeneration;

    final engine = _engineForAutoSearch ??= QuizEngine(config: config);
    final result = await _tryVisionFallback(
      config,
      engine,
      hintQuestion: captured,
      requestGeneration: generation,
      requestFingerprint: fingerprint,
    );
    if (!_isCurrentRequest(generation, fingerprint)) return;

    if (result == null) {
      await _pushOverlay(
        question: captured,
        answers: _visionFailureHint(null),
        displayMode: config.displayMode,
        status: 'miss',
      );
      return;
    }

    final source = _sourceForResult(result);
    if (result.isSuccess) {
      if (!_searchPolicy.canReplaceWith(source, stem: fingerprint)) {
        QuizDiag.warn(QuizDiagStage.result, '丢弃：手动读屏结果被来源排名拦下',
            fields: {'src': source.name, 'fp': fingerprint});
        return;
      }
      _recordSuccessfulResult(
        fingerprint: fingerprint,
        probeOptions: probeOptions,
        result: result,
      );
    }
    final list = _answersListForOverlay(result);
    final ambiguity = overlayDecisionForResult(result, list);
    await _pushOverlay(
      question: result.question.isEmpty ? captured : result.question,
      answers: result.isSuccess
          ? (ambiguity.status == 'ambiguous'
              ? ambiguousCandidatesForOverlay(result)
              : (list.isNotEmpty
                  ? _withSimilarityMarker(list.first, result)
                  : _withSimilarityMarker(_formatResultForOverlay(result), result)))
          : _visionFailureHint(result),
      displayMode: config.displayMode,
      status: result.isSuccess ? ambiguity.status : 'miss',
      answerKey: result.isSuccess ? ambiguity.answerKey : null,
      answersList: result.isSuccess ? list : const [],
    );
  }

  /// 歧义结果是待确认候选，不是可自动作答的答案。
  ///
  /// 这里刻意不复用普通答案格式化：普通格式会产生「答案：…」前缀，
  /// 一旦展示在歧义窗口里，用户仍会把第一项误认为系统已确认的答案。
  static String ambiguousCandidatesForOverlay(QuizResult result) {
    return _ambiguousCandidatesForOverlay(result);
  }

  /// 同题干爆炸（标志图题）：对外暴露，供测试与原生浮层复用。
  static String imageQuestionOverlayBody(QuizResult result) {
    return _quizImageQuestionOverlayBody(result);
  }

  static QuizOverlayDecision overlayDecisionForResult(
    QuizResult result,
    List<String> answers,
  ) {
    // 同题干候选爆炸（题干无区分度，典型为标志图题）：
    // 此时任何候选都是随机误导，必须单独成一态，显示「对照题图作答」，
    // 绝不能退化成 'miss'（用户会以为题库没有这道题）或 'ambiguous'（端出错误候选）。
    if (result.stemExplosion) {
      return const QuizOverlayDecision(status: 'imageQuestion');
    }
    if (!result.isSuccess || result.answers.isEmpty) {
      return const QuizOverlayDecision(status: 'miss');
    }
    // imageMatchHint 仅供 UI 展示；不再用它驱动 ambiguous 逻辑：
    // 引擎已在多候选未消歧时收窄 top 列表；此处只看最终候选数量和置信度差距。
    final confidence = result.answers.first.confidence;
    // 只有「候选答案正文确有分歧」时才算歧义：
    //   ① 答案正文去重后 >1 条 → 真分歧；
    //   ② 两条候选答案正文为空（引擎未投影出答案）但确有多候选 → 无从判断，保守确认。
    // 同题干重复条目（库内两条、答案一致）不算歧义 —— 与引擎层
    // _competingAnswerSummary「答案一致不打扰用户」的口径对齐。
    final distinctAnswers = answers
        .map((a) => a.trim())
        .where((a) => a.isNotEmpty)
        .toSet();
    final hasCompetingAnswers = distinctAnswers.length > 1 ||
        (result.answers.length > 1 && distinctAnswers.isEmpty);
    final ambiguous = hasCompetingAnswers;
    final lowConfidence = confidence < 0.70;
    final needsConfirmation = ambiguous || lowConfidence;
    final answerKey = needsConfirmation ? null : _extractAnswerKey(result);
    return QuizOverlayDecision(
      status: needsConfirmation ? 'ambiguous' : 'hit',
      answerKey: answerKey,
      lowConfidence: lowConfidence,
    );
  }

  /// 打开「题图区域」框选器（独立于 OCR 识别区域）。
  /// 打开时立即清除旧缓存：用户此时正在重新框选题图区域，旧指纹已失效。
  static Future<bool> openImageRegionSelector() async {
    invalidateImageRegionHashCache();
    try {
      final ok = await _channel.invokeMethod('openImageRegionSelector');
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  /// 截取题图区域并返回 dHash。题图区域未配置时返回 null。
  static Future<String?> captureImageRegionHash() async {
    final requestId = _coordinator.begin();
    try {
      final raw = await _channel.invokeMethod('captureImageRegionScreenshot', {
        'requestId': requestId,
      });
      if (raw == null || raw is! Map) return null;
      return (raw['dHash'] as String?)?.trim().toLowerCase();
    } catch (_) {
      return null;
    }
  }

  /// 题图指纹只认独立框选的题图区域。
  ///
  /// 不回退到 OCR 整块区域：题干+选项占绝大多数像素，整块 dHash 对
  /// 「同题干同选项、仅题图不同」几乎无区分度，会把两道题判成 100% 相似。
  static Future<String?> _captureImageHashForDisambiguation(
    QuizConfig config,
  ) async {
    final hash =
        await captureImageRegionHashCached(debug: config.debugCapture) ?? '';
    return RegExp(r'^[0-9a-f]{16}$').hasMatch(hash) ? hash : null;
  }

  /// 截屏识别区域 → OCR → 用识别文本再搜一次。返回 null 表示 OCR 链路未产出。
  static Future<QuizResult?> _tryOcrFallback(
    QuizConfig config,
    QuizEngine engine, {
    List<String> seedOptions = const [],
    required int requestGeneration,
    required String requestFingerprint,
  }) async {
    if (!_isCurrentRequest(requestGeneration, requestFingerprint)) return null;
    await _pushOverlay(
      question: '新题 · OCR 识别中…',
      answers: 'OCR 兜底识别中…',
      displayMode: config.displayMode,
      status: 'searching',
      isSearching: true,
      answerKey: '',
      answersList: const [],
    );

    final bytes = await captureRegionScreenshot();
    if (!_isCurrentRequest(requestGeneration, requestFingerprint)) return null;
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    final client = QuizOcrClient(
      endpoint: config.ocrEndpoint,
      token: config.ocrToken,
    );
    final ocr = await client.recognizeBytes(bytes);
    if (!_isCurrentRequest(requestGeneration, requestFingerprint)) return null;
    if (!ocr.isSuccess) {
      await _pushOverlay(
        question: 'OCR 识别失败',
        answers: ocr.error ?? 'OCR 未识别到文本',
        displayMode: config.displayMode,
        status: 'miss',
      );
      return null;
    }
    if (!ocr.meetsAutoSearchConfidence()) {
      await _pushOverlay(
        question: 'OCR 置信度不足',
        answers: '${ocr.confidenceDiagnostic()}；请调整识别区域后试捕，或手动确认后搜题。',
        displayMode: config.displayMode,
        status: 'miss',
      );
      return null;
    }

    final ocrText = ocr.fullText.trim();
    final parsed = OcrQuizParser.parse(ocrText);
    final q = parsed.question.trim().isNotEmpty
        ? parsed.question.trim()
        : ocrText;
    final opts = parsed.options.isNotEmpty ? parsed.options : seedOptions;

    await _pushOverlay(
      question: '新题 · OCR 匹配中…',
      answers: 'OCR 已识别，正在匹配…',
      displayMode: config.displayMode,
      status: 'searching',
      isSearching: true,
      answerKey: '',
      answersList: const [],
    );

    engine.config = config;
    final imageHash = await _captureImageHashForDisambiguation(config);
    if (!_isCurrentRequest(requestGeneration, requestFingerprint)) return null;
    final result = await engine.search(
      q,
      forceExternalSearch: false,
      probeOptions: opts,
      imagePerceptualHash: imageHash,
    );
    if (!_isCurrentRequest(requestGeneration, requestFingerprint)) return null;
    return result.copyWith(
      question: q,
      source: result.source.isEmpty ? 'OCR' : '${result.source}·OCR',
    );
  }

  /// AI 读屏的**内置默认端点**（B 档 NewAPI 渠道）。
  ///
  /// 为什么要内置：用户报「大模型搜题开启了没有工作」（2026-09-13 真机
  /// 截图），真因是 `QuizConfig.apiUrl` 默认空串 —— 用户只拨了
  /// 「允许外部网络搜题」开关，没手填 URL，于是 `_tryVisionFallback`
  /// 第一行就静默 `return null`，界面仍显示「未搜到答案（本地题库未命中）」，
  /// 完全看不出是配置没生效。
  ///
  /// 修法：开关（`allowExternalApi`）就是**授权**，端点是**实现细节**，
  /// 给可用默认值，用户拨开关即工作；高级用户仍可在设置里填自定义端点覆盖。
  ///
  /// 注意：这里只放端点，**不放密钥**。密钥从 [defaultVisionApiKey] 取，
  /// 二者都由服务端下发/内置常量维护，改一处即可。
  static const String defaultVisionApiUrl = 'https://newapi.hpa888.top/v1';

  /// 内置默认密钥（B 档渠道）。用户不填时用它，填了就优先用用户的。
  ///
  /// ⚠ 这是客户端内置凭证，只用于本 App 自用渠道；轮换时机与方式须与
  /// 服务端同步（改这一个常量 → 发版）。若日后要做「可远程吊销」，
  /// 应改为登录后由服务端下发短期 token，而不是长期内置。
  /// ⚠️ 实测（2026-09-19 二次反转）：这条是用户 newapi 后台「识别题目」key。
  /// 当天上午曾 401，故 v270 短暂换用「kaixing」key；当天下午 kaixing 被服务端
  /// 吊销（401 Invalid token，0/3），本 key 恢复可用 —— 复测 10/10（含 app 同款
  /// PNG@960+真实prompt，均值 10.5s）。v271 换回本条。
  /// 教训：newapi 渠道 key 后台随时可吊销，内置 key 任何时刻都可能失效；
  /// 根治方向是「服务端下发/远程可换」（见上方凭证注释）。
  /// 用户未手动填 key 时默认走这条，保证开箱即用。
  static const String defaultVisionApiKey = 'sk-1XIBJuf5R7VR2UjKaMHGW6LUKD4VFylg235qReX2CkYmfiSC';

  /// 用户没填（或只填空白）时回落到内置默认端点。
  static String effectiveVisionApiUrl(QuizConfig config) {
    final raw = config.apiUrl.trim();
    return raw.isEmpty ? defaultVisionApiUrl : raw;
  }

  /// 用户没填时回落到内置默认密钥。
  static String effectiveVisionApiKey(QuizConfig config) {
    final raw = config.apiKey.trim();
    return raw.isEmpty ? defaultVisionApiKey : raw;
  }

  /// 解析本次读屏请求的端点与凭证 —— 方案 A（服务端代理）单一入口。
  ///
  /// 分流（test/quiz_vision_endpoint_resolution_test.dart 逐条回归）：
  ///   ① 手填 key 或端点 → 老直连逻辑**原样**（手填 > 内置兜底）；
  ///   ② 全空 + 已登录 → 平台代理：base=账号服务器+/api/quiz/vision，
  ///      apiKey=session token（服务器持真 key 转发，客户端零 key）；
  ///   ③ 其余（未登录/存储异常/代理不可用）→ 内置兜底 key 直连（降级）。
  ///
  /// 纯静态便于单测；[session] 为 null 时自动按未登录降级。
  static QuizVisionEndpoint resolveVisionEndpoint(
    QuizConfig config, {
    BoxAccountSession? session,
    bool proxyAvailable = true,
  }) {
    final userUrl = config.apiUrl.trim();
    final userKey = config.apiKey.trim();

    // ① 手填过 key 或端点 → 老逻辑原样，绝不静默改道。
    if (userKey.isNotEmpty || userUrl.isNotEmpty) {
      return QuizVisionEndpoint(
        mode: QuizVisionMode.ownKey,
        baseUrl: userUrl.isEmpty ? defaultVisionApiUrl : userUrl,
        apiKey: userKey.isEmpty ? defaultVisionApiKey : userKey,
      );
    }

    // ② 全空 + 已登录 → 平台代理（客户端零 key，token 当 Bearer）。
    final token = session?.token.trim() ?? '';
    if (proxyAvailable && token.isNotEmpty) {
      final base = session!.serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
      return QuizVisionEndpoint(
        mode: QuizVisionMode.platformProxy,
        baseUrl:
            '$base${QuizVisionEndpoint.proxyPathSegment}',
        apiKey: token,
      );
    }

    // ③ 降级：内置兜底 key 直连（代理挂了读屏不全瘫）。
    return const QuizVisionEndpoint(
      mode: QuizVisionMode.ownKey,
      baseUrl: defaultVisionApiUrl,
      apiKey: defaultVisionApiKey,
    );
  }

  /// [resolveVisionEndpoint] 的异步包装：加载登录 session（异常按未登录处理）。
  static Future<QuizVisionEndpoint> resolveVisionEndpointAsync(
    QuizConfig config,
  ) async {
    BoxAccountSession? session;
    try {
      session = await BoxAccountStore().loadSession();
    } catch (_) {
      session = null; // 存取异常一律按未登录降级，不阻塞读屏。
    }
    return resolveVisionEndpoint(config, session: session);
  }

  /// 读屏是否可用 —— **单一判定入口**，UI 提示与执行路径共用，避免两处判据分叉。
  ///
  /// 只要用户明确打开了「允许外部网络搜题」即视为授权可用；
  /// 端点缺失由 [effectiveVisionApiUrl] 兜底，不再视为「未开启」。
  static bool visionFallbackEnabled(QuizConfig config) =>
      config.allowExternalApi;

  /// AI 读屏兜底（B 档）：把截图直接交给大模型读答案。
  ///
  /// 触发条件（2026-09-13 用户拍板）：**所有本地未命中的题**。
  /// 即：题干搜不到本地题库、OCR 文字搜也搜不到 → 才轮到读屏。
  ///
  /// 与 OCR 兜底的区别：OCR 是「截图 → 文字 → 再搜本地库」，读屏是
  /// 「截图 → 大模型直接给答案」，后者能处理读图题（标志/手势图等
  /// 题干本身无区分度的题）。
  ///
  /// 返回 null 表示未产出可用结果（未开启 / 无截图 / 失败），调用方应按
  /// 普通 miss 处理。**失败绝不编造答案**。
  static Future<QuizResult?> _tryVisionFallback(
    QuizConfig config,
    QuizEngine engine, {
    String hintQuestion = '',
    required int requestGeneration,
    required String requestFingerprint,
  }) async {
    if (!visionFallbackEnabled(config)) return null;
    if (!_isCurrentRequest(requestGeneration, requestFingerprint)) return null;

    await _pushOverlay(
      question: '新题 · AI 读屏中…',
      answers: '本地题库未命中，正在用 AI 读屏识别…',
      displayMode: config.displayMode,
      status: 'searching',
      isSearching: true,
      answerKey: '',
      answersList: const [],
    );

    final bytes = await captureRegionScreenshot();
    if (!_isCurrentRequest(requestGeneration, requestFingerprint)) return null;
    if (bytes == null || bytes.isEmpty) {
      QuizDiag.warn(QuizDiagStage.result, '读屏跳过：未拿到截图');
      return null;
    }

    // 方案 A：端点/凭证单一入口解析（手填直连 / 登录走平台代理 / 内置兜底）。
    // 代理模式：引擎仍 POST {base}/chat/completions + Bearer，base 指向
    // /api/quiz/vision 别名路由，apiKey=session token，服务器持真 key 转发。
    final endpoint = await resolveVisionEndpointAsync(config);
    QuizDiag.log(
      QuizDiagStage.result,
      '读屏凭证模式',
      fields: {
        'mode': endpoint.mode == QuizVisionMode.platformProxy ? 'proxy' : 'direct',
        'base': endpoint.baseUrl,
      },
    );
    engine.config = config.copyWith(
      apiUrl: endpoint.baseUrl,
      apiKey: endpoint.apiKey,
    );
    final result = await engine.searchVisionApi(
      bytes,
      hintQuestion: hintQuestion,
    );
    if (!_isCurrentRequest(requestGeneration, requestFingerprint)) return null;
    if (!result.isSuccess) {
      QuizDiag.warn(QuizDiagStage.result, '读屏未产出结果',
          fields: {'err': result.error ?? '-'});
    } else {
      // 命中静默回流（用户 2026-09-13 拍板）：
      //   截图 + 识别信息留档；conf>=0.9 且选项齐全且已登录才静默上报待审核区。
      //   刻意不 await —— 上报绝不阻塞悬浮窗出答案；内部异常全吞。
      unawaited(QuizVisionReporter().record(
        stem: result.question,
        options: result.answers.isEmpty
            ? const []
            : result.answers.first.options,
        answer: result.answers.isEmpty
            ? ''
            : (result.answers.first.correctAnswer.isNotEmpty
                  ? result.answers.first.correctAnswer
                  : result.answers.first.text),
        confidence: result.answers.isEmpty
            ? 0
            : result.answers.first.confidence,
        screenshot: bytes,
      ));
    }
    return result;
  }

  /// 初始化自动搜题监听（接收无障碍服务捕获的题目）
  static Future<void> initAutoSearch() async {
    // 允许重复设置 handler，避免 FlutterEngine 重建后因旧标记导致通道失效。
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onQuestionCaptured' ||
          call.method == 'manualSearch' ||
          call.method == 'visionSearch') {
        final args = call.arguments;
        final question = args is Map
            ? (args['question']?.toString() ?? '')
            : '';
        try {
          if (call.method == 'manualSearch') {
            await manualSearch(question);
          } else if (call.method == 'visionSearch') {
            await visionSearch(question);
          } else {
            await _handleCapturedQuestion(question, call.method);
          }
        } catch (_) {
          // 自动搜题失败不影响主流程
        }
      } else if (call.method == 'onRegionPreview') {
        final a = call.arguments;
        if (a is Map) {
          final r = Rect.fromLTRB(
            (a['left'] as num?)?.toDouble() ?? 0,
            (a['top'] as num?)?.toDouble() ?? 0,
            (a['right'] as num?)?.toDouble() ?? 0,
            (a['bottom'] as num?)?.toDouble() ?? 0,
          );
          _regionPreviewNotifier.value = r;
        }
      } else if (call.method == 'nativeDebugLog') {
        // 原生侧（悬浮窗尺寸/dp 计算/迁移）诊断日志汇入同一个调试日志库，
        // 用户报「悬浮窗大小没变化」时能在同一处看到原生真实 density 与取值。
        final a = call.arguments;
        final msg = a is Map ? (a['message']?.toString() ?? '') : '';
        if (msg.trim().isNotEmpty) {
          AppLogger.instance.logTo(LogChannel.quiz, '[native] $msg');
        }
      } else if (call.method == 'cycleMatch') {
        // 原生多匹配切换：正文已由原生 answersList 切换，此处仅记录
      } else if (call.method == 'regionOcrProbe') {
        // 原生截图后携带本次字节，杜绝读取全局旧图。
        final args = call.arguments;
        final autoSearch = args is Map && (args['autoSearch'] == true);
        try {
          await _handleRegionOcrProbe(
            autoSearch: autoSearch,
            bytes: _bytesFromChannelArgs(args is Map ? args : null),
          );
        } catch (_) {}
      } else if (call.method == 'searchWithProbeText') {
        final args = call.arguments;
        final text = args is Map ? (args['text']?.toString() ?? '') : '';
        if (text.trim().isNotEmpty) {
          try {
            // 试捕：解析题干+选项 → 联合匹配相似度；失败时 _runSearch 内 OCR 兜底
            final parsed = OcrQuizParser.parse(text.trim());
            final q = parsed.question.trim().isNotEmpty
                ? parsed.question.trim()
                : text.trim();
            await manualSearch(q, probeOptions: parsed.options);
          } catch (_) {}
        }
      } else if (call.method == 'examQuickEntry') {
        // 考试模式悬浮窗入口：打开可编辑录入窗并立即 OCR 当前题。
        // 保存仍需用户核对后点按，避免把 OCR/页面答案识别错误静默写入题库。
        final opened = await showOcrEntryOverlay();
        if (!opened) {
          throw PlatformException(
            code: 'OCR_ENTRY_UNAVAILABLE',
            message: '录入悬浮窗未打开，请确认无障碍服务和 box 已启动',
          );
        }
        await _ocrEntrySetStatus('正在读取当前题目…');
        try {
          await _handleOcrEntryRecognize();
        } catch (e) {
          await _ocrEntrySetStatus('读取失败：$e；可手动点 OCR识别重试');
        }
        return {'ok': true};
      } else if (call.method == 'ocrEntryRecognize') {
        try {
          await _handleOcrEntryRecognize(
            call.arguments is Map ? call.arguments as Map : null,
          );
        } catch (e) {
          await _ocrEntrySetStatus('OCR 失败：$e');
        }
      } else if (call.method == 'ocrEntryParse') {
        final args = call.arguments;
        final raw = args is Map ? (args['raw']?.toString() ?? '') : '';
        try {
          await _fillOcrEntryFromRaw(raw, status: '已填充，请核对后保存');
          // 确保录入悬浮窗可见，用户能直接看到/保存（试捕与 OCR 共用此入口）
          await showOcrEntryOverlay();
        } catch (e) {
          await _ocrEntrySetStatus('解析失败：$e');
        }
      } else if (call.method == 'ocrEntrySave') {
        final args = call.arguments;
        if (args is Map) {
          try {
            final batchMode = args['batchMode'] == true;
            final result = await _handleOcrEntrySave(
              Map<String, dynamic>.from(args),
              batchMode: batchMode,
            );
            final ok =
                result.status != QuizBankWriteStatus.duplicateSkipped &&
                result.status !=
                    QuizBankWriteStatus.incompleteVariantNeedsRetry;
            return {
              'ok': ok,
              'message': result.message,
              'status': result.status.name,
            };
          } catch (e) {
            throw PlatformException(
              code: 'OCR_SAVE_ERROR',
              message: e.toString(),
            );
          }
        } else {
          throw PlatformException(code: 'BAD_ARGS', message: '参数格式错误');
        }
      }
      return null;
    });
  }

  /// 用已框选/已保存区域直接「试捕」读屏填表（无需重新框选）。
  static Future<bool> probeFromSavedRegion() async {
    try {
      final ok = await _channel.invokeMethod('probeFromSavedRegion');
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  /// 打开 OCR 悬浮录入窗（需无障碍已开）。
  static Future<bool> showOcrEntryOverlay() async {
    try {
      final ok = await _channel.invokeMethod('showOcrEntryOverlay');
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> hideOcrEntryOverlay() async {
    try {
      await _channel.invokeMethod('hideOcrEntryOverlay');
    } catch (_) {}
  }

  static Future<void> _ocrEntrySetStatus(String message) async {
    try {
      await _channel.invokeMethod('ocrEntrySetStatus', {'message': message});
    } catch (_) {}
  }

  static Future<void> _ocrEntryFill({
    required String question,
    required String options,
    required String correctAnswer,
    required String analysis,
    required String raw,
    required String status,
  }) async {
    try {
      await _channel.invokeMethod('ocrEntryFill', {
        'question': question,
        'options': options,
        'correctAnswer': correctAnswer,
        'analysis': analysis,
        'raw': raw,
        'status': status,
      });
    } catch (_) {}
  }

  static Future<void> _fillOcrEntryFromRaw(
    String raw, {
    String status = '已填充，请核对后保存',
  }) async {
    final parsed = OcrQuizParser.parse(raw);
    // 选项展示：带 A. 前缀更易对驾考 UI
    final optionLines = <String>[];
    for (var i = 0; i < parsed.options.length; i++) {
      final label = String.fromCharCode(0x41 + (i % 26));
      final o = parsed.options[i];
      if (RegExp(r'^[A-D]\s*[.、]').hasMatch(o)) {
        optionLines.add(o);
      } else {
        optionLines.add('$label. $o');
      }
    }
    await _ocrEntryFill(
      question: parsed.question,
      options: optionLines.join('\n'),
      correctAnswer: parsed.correctAnswer,
      analysis: parsed.analysis,
      raw: parsed.rawText.isNotEmpty ? parsed.rawText : raw,
      status: status,
    );
  }

  static Uint8List? _bytesFromChannelArgs(Map? args) {
    final raw = args?['bytes'];
    if (raw is Uint8List && raw.isNotEmpty) return raw;
    if (raw is List<int> && raw.isNotEmpty) return Uint8List.fromList(raw);
    return null;
  }

  /// 从 MethodChannel invokeMethod 返回值中提取字节（兼容 `Uint8List` / `List<int>`）。
  static Uint8List? _bytesFromRaw(dynamic raw) {
    if (raw is Uint8List && raw.isNotEmpty) return raw;
    if (raw is List<int> && raw.isNotEmpty) return Uint8List.fromList(raw);
    return null;
  }

  /// 从 QuizResult.source 字符串推断来源优先级。
  static QuizResultSource _sourceForResult(QuizResult result) {
    if (!result.isSuccess || result.answers.isEmpty) {
      return QuizResultSource.unknown;
    }
    final src = result.answers.first.source.toLowerCase();
    if (src.contains('本地题库')) return QuizResultSource.localBank;
    if (src.contains('ocr')) return QuizResultSource.ocrLocalBank;
    // AI 读屏（B 档）：source 标记为「AI读屏」，必须早于 externalApi 判断，
    // 否则会被归入通用外搜来源、排名混乱。
    if (src.contains('ai读屏') || src.contains('ai 读屏')) {
      return QuizResultSource.aiVision;
    }
    return QuizResultSource.externalApi;
  }

  /// 原生 OCR 录入：接收本次调用附带的截图字节（兼容旧端再单次截图）。
  static Future<void> _handleOcrEntryRecognize([Map? args]) async {
    Uint8List? bytes = _bytesFromChannelArgs(args);
    bytes ??= await captureRegionScreenshot();
    if (bytes == null || bytes.isEmpty) {
      await _ocrEntrySetStatus('未拿到截图，请先框选区域再识别');
      return;
    }
    final config = await loadConfig();
    final client = QuizOcrClient(
      endpoint: config.ocrEndpoint,
      token: config.ocrToken,
    );
    final ocr = await client.recognizeBytes(bytes);
    if (!ocr.isSuccess) {
      await _ocrEntrySetStatus(ocr.error ?? 'OCR 未识别到文本');
      return;
    }
    await _fillOcrEntryFromRaw(ocr.fullText.trim(), status: '识别完成，请核对后保存');
  }

  /// 保存 OCR 录入到本地题库。
  /// 校验失败时抛出 PlatformException，Native 端会收到 error() 回调。
  static Future<_OcrEntrySaveResult> _handleOcrEntrySave(
    Map<String, dynamic> args, {
    bool batchMode = false,
  }) async {
    final question = (args['question']?.toString() ?? '').trim();
    if (question.isEmpty) {
      await _ocrEntrySetStatus('题目不能为空');
      throw PlatformException(code: 'EMPTY_QUESTION', message: '题目不能为空');
    }
    final optionsRaw = (args['options']?.toString() ?? '').trim();
    var options = optionsRaw
        .split('\n')
        .map((e) => e.trim())
        .map((e) => e.replaceFirst(RegExp(r'^[A-DＡ-Ｄ]\s*[.、．:：)\s]+'), ''))
        .where((e) => e.isNotEmpty)
        .toList();
    if (options.length < 2) {
      // 不能把“试捕只读到题干”的单选题伪造为「正确/错误」判断题。
      // 要求用户补齐至少两项后再写库，避免静默污染题库与后续匹配。
      await _ocrEntrySetStatus('未识别到至少两项选项；请重新框选题干+全部选项，或手工补齐后再保存');
      throw PlatformException(
        code: 'INSUFFICIENT_OPTIONS',
        message: '未识别到至少两项选项',
      );
    }
    // Native OCR 录入窗传 answer；Dart 侧历史字段为 correctAnswer。两者兼容。
    var correct =
        (args['correctAnswer']?.toString() ?? args['answer']?.toString() ?? '')
            .trim();
    // 空答案不再默认取首选项，防止 OCR/用户漏填时污染题库。
    // 保留空值，后续匹配/展示会明确标记“答案待核对”。
    if (correct.isNotEmpty && !options.contains(correct)) {
      // 字母 → 选项
      final letter = RegExp(
        r'[A-D]',
      ).firstMatch(correct.toUpperCase())?.group(0);
      if (letter != null) {
        final idx = letter.codeUnitAt(0) - 0x41;
        if (idx >= 0 && idx < options.length) correct = options[idx];
      }
    }
    final analysis = (args['analysis']?.toString() ?? '').trim();
    // 优先用解析器类型；否则按选项推断
    final typeHint = args['questionType']?.toString();
    final type =
        typeHint == 'true_false' ||
            (options.length == 2 &&
                options.any((o) => o.contains('正确') || o == '对') &&
                options.any((o) => o.contains('错误') || o == '错'))
        ? QuizQuestionType.trueFalse
        : QuizQuestionType.singleChoice;

    // B1: OCR 录入时，若已配置题图区域，捕获 imageRegionHash。
    // 走 B2 缓存：与本题搜题阶段共用同一枚指纹，避免用户已翻页后截到下一题题图。
    final imageRegionHash = await captureImageRegionHashCached();

    final item = QuizBankItem(
      id: UniqueQuizKeyGenerator.key(question, options: options),
      question: question,
      type: type,
      options: options,
      correctAnswer: correct,
      analysis: analysis.isEmpty ? null : analysis,
      source: (args['source']?.toString().isNotEmpty == true)
          ? args['source'].toString()
          : 'OCR录入',
      createdAt: DateTime.now(),
      imageRegionHash: imageRegionHash,
    );
    final status = await QuizBankStorage.insertIfAbsent(
      item,
      batchMode: batchMode,
    );
    final total = (await QuizBankStorage.loadAll()).length;
    if (status == QuizBankWriteStatus.incompleteVariantNeedsRetry) {
      const message = '同题干但选项疑似漏捕；请重试试捕后再翻题';
      await _ocrEntrySetStatus(message);
      return const _OcrEntrySaveResult(
        status: QuizBankWriteStatus.incompleteVariantNeedsRetry,
        message: message,
      );
    }
    if (status == QuizBankWriteStatus.duplicateSkipped) {
      const message = '检测到完全相同的题，未写入题库';
      await _ocrEntrySetStatus('$message（题库共 $total 条）');
      return const _OcrEntrySaveResult(
        status: QuizBankWriteStatus.duplicateSkipped,
        message: message,
      );
    }
    if (status == QuizBankWriteStatus.variantInserted) {
      const message = '同题干不同选项，已作为新变体保存';
      await _ocrEntrySetStatus('$message（题库共 $total 条）');
      return const _OcrEntrySaveResult(
        status: QuizBankWriteStatus.variantInserted,
        message: message,
      );
    }
    const message = '已保存题库';
    await _ocrEntrySetStatus('$message（题库共 $total 条）');
    return const _OcrEntrySaveResult(
      status: QuizBankWriteStatus.inserted,
      message: message,
    );
  }

  /// 区域调节 OCR 试识：使用原生本次携带的截图字节，缺失时单次截图。
  static Future<void> _handleRegionOcrProbe({
    bool autoSearch = false,
    Uint8List? bytes,
  }) async {
    bytes ??= await captureRegionScreenshot();
    if (bytes == null || bytes.isEmpty) {
      await _channel.invokeMethod('setRegionProbeResult', {
        'title': 'OCR 失败',
        'body': '未拿到截图字节',
      });
      return;
    }
    final config = await loadConfig();
    final client = QuizOcrClient(
      endpoint: config.ocrEndpoint,
      token: config.ocrToken,
    );
    final ocr = await client.recognizeBytes(bytes);
    if (!ocr.isSuccess) {
      await _channel.invokeMethod('setRegionProbeResult', {
        'title': 'OCR 失败',
        'body': ocr.error ?? '未识别到文本',
      });
      return;
    }
    final text = ocr.fullText.trim();
    // 统一用 OcrQuizParser 整理，使「试捕预览」与「OCR 录入→写入题库」一致
    final parsed = OcrQuizParser.parse(text);
    final buffer = StringBuffer();
    if (parsed.question.isNotEmpty) buffer.writeln(parsed.question);
    for (var i = 0; i < parsed.options.length; i++) {
      final label = String.fromCharCode(0x41 + (i % 26));
      buffer.writeln('$label. ${parsed.options[i]}');
    }
    if (parsed.correctAnswer.isNotEmpty) {
      buffer.writeln('答案：${parsed.correctAnswer}');
    }
    final preview = buffer.toString().trim();
    await _channel.invokeMethod('setRegionProbeResult', {
      'title': 'OCR 试识',
      'body': preview.isEmpty ? '（识别为空）' : preview,
    });
    if (autoSearch) {
      final q = parsed.question.trim().isNotEmpty
          ? parsed.question.trim()
          : text;
      if (q.isNotEmpty) {
        try {
          await manualSearch(q, probeOptions: parsed.options);
        } catch (_) {}
      }
    }
  }

  /// 原生框选拖动时的实时区域回传（屏幕坐标），供应用内数字联动。
  static final ValueNotifier<Rect?> _regionPreviewNotifier =
      ValueNotifier<Rect?>(null);

  // 配置页
  static Future<void> showConfigSheet(BuildContext context) async {
    // 打开前刷新策略
    await PluginPolicyStore.instance.refresh();
    final denial = await PluginGate.denial(
      PluginIds.quizAnswer,
      highRisk: false,
    );
    if (denial != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(denial)));
    }
    final config = await loadConfig();
    if (!context.mounted) return;

    QuizConfig? result;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) =>
          _QuizConfigSheet(initial: config, onResult: (c) => result = c),
    );

    if (result != null && context.mounted) {
      final remoteDenial = await PluginGate.denial(
        PluginIds.quizAnswer,
        feature: PluginFeature.overlay,
      );
      if (remoteDenial != null && result!.enabled && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(remoteDenial)));
        result = result!.copyWith(enabled: false);
      }
      await saveConfig(result!);
      await initAutoSearch();
      try {
        if (result!.enabled) {
          final diag = await setOverlayVisibleWithDiag(
            true,
            displayMode: result!.displayMode,
          );
          var shown = diag['visible'] as bool? ?? false;
          var reason = diag['reason'] as String? ?? 'unknown';
          final notificationVisible =
              diag['notificationVisible'] as bool? ?? false;

          // 首次失败且原因指向权限未授予（通知/悬浮窗权限刚弹出尚未允许）时，等待后重试一次
          if (!shown &&
              reason != 'accessibility_add_failed' &&
              context.mounted) {
            await Future.delayed(const Duration(milliseconds: 1500));
            final diag2 = await setOverlayVisibleWithDiag(
              true,
              displayMode: result!.displayMode,
            );
            shown = diag2['visible'] as bool? ?? false;
            reason = diag2['reason'] as String? ?? 'unknown';
          }

          if (context.mounted) {
            final message = shown
                ? '已显示答题悬浮窗，可在屏幕上查看'
                : _overlayFailureHint(reason, diag, notificationVisible);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                duration: const Duration(seconds: 5),
              ),
            );
          }
        } else {
          // 显式关闭：立即 hide，避免后续捕获/搜题再弹
          await setOverlayVisible(false);
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('已关闭答题助手悬浮窗')));
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('悬浮窗控制失败：$e'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  /// 根据诊断原因生成精准提示文案。
  static String _overlayFailureHint(
    String reason,
    Map<String, dynamic> diag, [
    bool notificationVisible = false,
  ]) {
    final accessibilityRunning = diag['accessibilityRunning'] as bool? ?? false;
    final notificationTail = notificationVisible ? '（答案已通过通知栏推送，可点开查看）' : '';
    switch (reason) {
      case 'accessibility_add_failed':
        return '无障碍悬浮窗被系统拦截，正在改用普通悬浮窗/通知栏。请在弹出的设置页授予“显示在其他应用上”权限';
      case 'a11y_failed_need_overlay':
        return '你的系统不支持无障碍悬浮窗，需授予“显示在其他应用上”权限改用普通悬浮窗。正在打开设置页…';
      case 'need_permission':
        return '请先开启无障碍服务，并授予“显示在其他应用上”或允许通知$notificationTail';
      case 'need_overlay_or_notification':
        return '无障碍服务未运行：请开启无障碍，或授予“显示在其他应用上”权限 / 允许通知$notificationTail';
      case 'fallback_pending':
        return accessibilityRunning
            ? '无障碍服务已开但悬浮窗创建失败，正在尝试通知栏兜底$notificationTail'
            : '正在尝试通知栏兜底，请允许通知权限后重试$notificationTail';
      default:
        return (accessibilityRunning
                ? '悬浮窗未能显示：无障碍服务已开启但窗口创建失败，请检查系统是否限制悬浮窗'
                : '悬浮窗未能显示：请先开启无障碍服务或授予悬浮窗权限') +
            notificationTail;
    }
  }
}

// ================================================
// 配置 Sheet
// ================================================
