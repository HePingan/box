import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design_system/app_tokens.dart';
import 'ocr_quiz_parser.dart';
import 'quiz_bank.dart';
import 'quiz_capture_session.dart';
import 'quiz_config.dart';
import 'quiz_engine.dart';
import 'quiz_ocr_client.dart';
import 'quiz_search_policy.dart';

/// 答题插件 - MethodChannel 名称
const String _kChannel = 'com.example.box/quiz_plugin';

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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, jsonEncode(config.toJson()));
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
        if (answers != null) 'answers': answers,
        if (isSearching != null) 'isSearching': isSearching,
        'status': resolvedStatus,
        if (answerKey != null) 'answerKey': answerKey,
        if (similarity != null) 'similarity': similarity.clamp(0, 100),
        if (matchIndex != null) 'matchIndex': matchIndex,
        if (matchCount != null) 'matchCount': matchCount,
        if (answersList != null) 'answersList': answersList,
      });
    } catch (_) {}
  }

  static Future<void> openRegionSelector() async {
    try {
      await _channel.invokeMethod('openRegionSelector');
    } catch (_) {}
  }

  /// 设置答案悬浮窗透明度（0.3~1.0）。
  static Future<void> setOverlayOpacity(double opacity) async {
    try {
      await _channel.invokeMethod('setOverlayOpacity', {
        'opacity': opacity.clamp(0.3, 1.0),
      });
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

  /// 将引擎的结构化答案转成悬浮窗正文。
  /// 本地题库的 answer.text 是完整详情（首行常为「匹配题目」），
  /// 必须优先使用 correctAnswer，不能把整段详情硬加「答案：」前缀。
  /// 取引擎给出的相似度，作为原生标题栏的稳定状态信息。
  static int? _similarityForResult(QuizResult result) {
    if (!result.isSuccess || result.answers.isEmpty) return null;
    return similarityPercentForAnswer(result.answers.first);
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

  static String _withSimilarityMarker(String text, QuizResult result) {
    final similarity = _similarityForResult(result);
    if (similarity == null) return text;
    // 原生标题栏从正文提取相似度；隐藏 marker 不影响用户阅读，也不会重复显示。
    return '$text\n[[SIM:$similarity]]';
  }

  /// 悬浮窗正文只放答案本身。
  /// 相似度已在标题栏/摘要条展示；匹配题干/选项/解析不再塞进内容区。
  static String _overlayTextForAnswer(QuizAnswer answer) {
    final correct = answer.correctAnswer.trim();
    if (correct.isNotEmpty) {
      return correct.startsWith('答案') ? correct : '答案：$correct';
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

  static String _formatResultForOverlay(QuizResult result) {
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
  static List<String> _answersListForOverlay(QuizResult result) {
    if (!result.isSuccess) return const [];
    return result.answers
        .map(_overlayTextForAnswer)
        .where((t) => t.trim().isNotEmpty)
        .toList();
  }

  static String? _extractAnswerKey(QuizResult result) {
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

  static DateTime? _lastSearchAt;
  static String? _lastSearchQuestion;
  static int _searchGeneration = 0;
  static String _activeQuestionFingerprint = '';

  /// 高质量命中才短路同题刷新；半题/低分命中允许选项补齐后纠错。
  static final QuizSearchPolicy _searchPolicy = QuizSearchPolicy();
  static Timer? _captureDebounce;

  /// 题目指纹：题干优先，去掉空白/题号/选项行，避免选项逐步加载时误判新题。
  static String _questionFingerprint(String raw) {
    final parsed = OcrQuizParser.parse(raw);
    var q = parsed.question.trim();
    if (q.isEmpty) {
      q = raw
          .split('\n')
          .map((e) => e.trim())
          .firstWhere(
            (e) => e.isNotEmpty && !RegExp(r'^[A-HＡ-Ｈ][.、．:：)]').hasMatch(e),
            orElse: () => raw.trim(),
          );
    }
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

  /// 3 秒内同题不重复搜（防滚动刷屏）
  static bool _shouldSkipDuplicateSearch(String question, String method) {
    if (method == 'manualSearch') return false;
    final now = DateTime.now();
    final q = question.trim();
    if (_lastSearchQuestion == q &&
        _lastSearchAt != null &&
        now.difference(_lastSearchAt!) < const Duration(seconds: 3)) {
      return true;
    }
    _lastSearchQuestion = q;
    _lastSearchAt = now;
    return false;
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

  static String _formatDebugCapture(String captured) {
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

  static Future<void> _handleCapturedQuestion(
    String question,
    String method,
  ) async {
    final captured = question.trim();
    if (captured.isEmpty) return;
    final config = await loadConfig();
    if (!config.enabled && method != 'manualSearch') return;

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
    // 同题的可靠命中才抑制刷新；选项补齐/变化与用户手动刷新必须允许纠错。
    if (_searchPolicy.shouldSuppress(
      stem: fingerprint,
      options: captureOptions,
      manualRefresh: method == 'manualSearch',
    )) {
      return;
    }
    final isNewQuestion = fingerprint != _activeQuestionFingerprint;
    if (isNewQuestion) {
      // 新题立即让旧答案失效；任何旧请求回来都会因 generation 不一致被丢弃。
      _activeQuestionFingerprint = fingerprint;
      final generation = ++_searchGeneration;
      _captureDebounce?.cancel();
      await _showNewQuestionSearching(captured, config);
      // 等页面题干/选项稳定，避免翻题动画中抓到半截内容；远小于旧 900/1800ms 节流。
      _captureDebounce = Timer(const Duration(milliseconds: 240), () {
        _runSearch(
          question: captured,
          config: config,
          method: method,
          probeOptions: captureOptions,
          requestGeneration: generation,
          requestFingerprint: fingerprint,
        );
      });
      return;
    }

    // 同题内容变化（选项/解析渐进加载）不重新清答案，仍受重复保护。
    await _runSearch(
      question: captured,
      config: config,
      method: method,
      requestFingerprint: fingerprint,
    );
  }

  static void _recordSuccessfulResult({
    required String fingerprint,
    required List<String> probeOptions,
    required QuizResult result,
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
    );
  }

  /// 真正的搜题执行：按开关路由（无障碍文本 / OCR 截图），二者可并存。
  /// [probeOptions]：试捕解析出的选项，参与题库匹配与相似度计算。
  static Future<void> _runSearch({
    required String question,
    required QuizConfig config,
    required String method,
    bool fromOcr = false,
    List<String> probeOptions = const [],
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
        _searchGeneration++;
      }
      generation = _searchGeneration;
    }
    final currentGeneration = generation;
    if (!_isCurrentRequest(currentGeneration, fingerprint)) {
      return;
    }
    if (_shouldSkipDuplicateSearch(captured, method)) return;

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
        await _pushOverlay(
          question: config.debugCapture ? '调试捕获：正在用下方文本搜题' : captured,
          answers: config.debugCapture
              ? '${_formatDebugCapture(captured)}$optHint\n\n正在搜题（题干+选项）...'
              : '正在搜题（题干+选项）...',
          displayMode: config.displayMode,
          status: 'searching',
          isSearching: true,
        );
        final engine = _engineForAutoSearch ??= QuizEngine(config: config);
        engine.config = config;
        final result = await engine.search(
          captured,
          forceExternalSearch: method == 'manualSearch',
          probeOptions: probeOptions,
        );
        // 搜题期间已经切到新题：禁止旧结果覆盖当前“新题检索中”。
        if (!_isCurrentRequest(currentGeneration, fingerprint)) return;
        if (result.isSuccess) {
          final source = _sourceForResult(result);
          // 低优先级结果不能覆盖已展示的高质量命中（如外部 API 盖过本地题库）。
          if (!_searchPolicy.canReplaceWith(source)) {
            return;
          }
          _recordSuccessfulResult(
            fingerprint: fingerprint,
            probeOptions: probeOptions,
            result: result,
          );
          final list = _answersListForOverlay(result);
          await _pushOverlay(
            question: captured,
            answers: config.debugCapture
                ? '${_formatResultForOverlay(result)}\n\n--- 调试捕获文本 ---\n${_formatDebugCapture(captured)}'
                : (list.isNotEmpty
                      ? _withSimilarityMarker(list.first, result)
                      : _withSimilarityMarker(
                          _formatResultForOverlay(result),
                          result,
                        )),
            displayMode: config.displayMode,
            status: 'hit',
            answerKey: _extractAnswerKey(result),
            similarity: _similarityForResult(result),
            matchIndex: 0,
            matchCount: list.isNotEmpty
                ? list.length
                : result.answers.length.clamp(1, 9),
            answersList: list,
          );
          return;
        }
        // 文本未命中：若 OCR 开启则兜底，否则展示失败
        if (!config.ocrSearch) {
          await _pushOverlay(
            question: captured,
            answers: _formatResultForOverlay(result),
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
          if (!_searchPolicy.canReplaceWith(source)) {
            return;
          }
          _recordSuccessfulResult(
            fingerprint: fingerprint,
            probeOptions: probeOptions,
            result: ocrResult,
          );
        }
        final list = _answersListForOverlay(ocrResult);
        await _pushOverlay(
          question: ocrResult.question,
          answers: list.isNotEmpty
              ? _withSimilarityMarker(list.first, ocrResult)
              : _withSimilarityMarker(
                  _formatResultForOverlay(ocrResult),
                  ocrResult,
                ),
          displayMode: config.displayMode,
          status: ocrResult.isSuccess ? 'hit' : 'miss',
          answerKey: _extractAnswerKey(ocrResult),
          similarity: _similarityForResult(ocrResult),
          matchIndex: 0,
          matchCount: list.isNotEmpty
              ? list.length
              : ocrResult.answers.length.clamp(1, 9),
          answersList: list,
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
    final result = await engine.search(
      q,
      forceExternalSearch: false,
      probeOptions: opts,
    );
    if (!_isCurrentRequest(requestGeneration, requestFingerprint)) return null;
    return result.copyWith(
      question: q,
      source: result.source.isEmpty ? 'OCR' : '${result.source}·OCR',
    );
  }

  /// 初始化自动搜题监听（接收无障碍服务捕获的题目）
  static Future<void> initAutoSearch() async {
    // 允许重复设置 handler，避免 FlutterEngine 重建后因旧标记导致通道失效。
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onQuestionCaptured' ||
          call.method == 'manualSearch') {
        final args = call.arguments;
        final question = args is Map
            ? (args['question']?.toString() ?? '')
            : '';
        try {
          if (call.method == 'manualSearch') {
            await manualSearch(question);
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
            await _handleOcrEntrySave(Map<String, dynamic>.from(args));
            return {'ok': true, 'message': '已保存题库'};
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

  /// 从 MethodChannel invokeMethod 返回值中提取字节（兼容 Uint8List / List<int>）。
  static Uint8List? _bytesFromRaw(dynamic raw) {
    if (raw is Uint8List && raw.isNotEmpty) return raw;
    if (raw is List<int> && raw.isNotEmpty) return Uint8List.fromList(raw);
    return null;
  }

  /// 从 QuizResult.source 字符串推断来源优先级。
  static QuizResultSource _sourceForResult(QuizResult result) {
    if (!result.isSuccess || result.answers.isEmpty)
      return QuizResultSource.unknown;
    final src = result.answers.first.source.toLowerCase();
    if (src.contains('本地题库')) return QuizResultSource.localBank;
    if (src.contains('ocr')) return QuizResultSource.ocrLocalBank;
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
  static Future<void> _handleOcrEntrySave(Map<String, dynamic> args) async {
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
    );
    final status = await QuizBankStorage.insertIfAbsent(item);
    final total = (await QuizBankStorage.loadAll()).length;
    if (status == QuizBankWriteStatus.duplicateSkipped) {
      await _ocrEntrySetStatus('检测到完全相同的题，未写入题库（题库共 $total 条）');
      return;
    }
    await _ocrEntrySetStatus('已保存，题库共 $total 条');
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

  // 识别区域调节页入口
  static Future<void> showRegionSheet(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const _RegionSheetPage()));
  }
}

// ================================================
// 配置 Sheet
// ================================================

class _AccessibilityStatusCard extends StatefulWidget {
  final Future<void> Function() onRequestAccessibility;

  const _AccessibilityStatusCard({required this.onRequestAccessibility});

  @override
  State<_AccessibilityStatusCard> createState() =>
      _AccessibilityStatusCardState();
}

class _AccessibilityStatusCardState extends State<_AccessibilityStatusCard> {
  bool _enabled = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant _AccessibilityStatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refresh();
  }

  Future<void> _refresh() async {
    _enabled = await QuizPluginEntry.isAccessibilityEnabled();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final label = _checking
        ? '正在检测无障碍权限...'
        : _enabled
        ? '无障碍服务已启用'
        : '无障碍服务未启用';
    final color = _checking
        ? Colors.grey
        : _enabled
        ? AppTokens.success
        : AppTokens.danger;
    final action = _checking
        ? null
        : _enabled
        ? null
        : TextButton.icon(
            onPressed: () async {
              await widget.onRequestAccessibility();
              await _refresh();
            },
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('去开启'),
          );

    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        border: Border.all(color: AppTokens.divider),
      ),
      child: Row(
        children: [
          Icon(Icons.support_agent_rounded, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          if (action != null) action,
        ],
      ),
    );
  }
}

class _QuizConfigSheet extends StatefulWidget {
  final QuizConfig initial;
  final ValueChanged<QuizConfig> onResult;

  const _QuizConfigSheet({required this.initial, required this.onResult});

  @override
  State<_QuizConfigSheet> createState() => _QuizConfigSheetState();
}

class _QuizConfigSheetState extends State<_QuizConfigSheet> {
  late QuizConfig _cfg;
  bool _saving = false;
  late final TextEditingController _ocrEndpointController;
  late final TextEditingController _ocrTokenController;
  late final TextEditingController _apiUrlController;
  late final TextEditingController _apiKeyController;

  @override
  void initState() {
    super.initState();
    _cfg = widget.initial;
    _ocrEndpointController = TextEditingController(text: _cfg.ocrEndpoint);
    _ocrTokenController = TextEditingController(text: _cfg.ocrToken);
    _apiUrlController = TextEditingController(text: _cfg.apiUrl);
    _apiKeyController = TextEditingController(text: _cfg.apiKey);
  }

  @override
  void dispose() {
    _ocrEndpointController.dispose();
    _ocrTokenController.dispose();
    _apiUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = QuizConfig.themeColors;
    final colorOptions = [
      Colors.red,
      Colors.purple,
      Colors.blue,
      Colors.teal,
      Colors.orange,
      Colors.green,
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding:
            MediaQuery.of(context).viewInsets +
            const EdgeInsets.all(AppTokens.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('答题助手设置', style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.spaceLg),
            _AccessibilityStatusCard(
              onRequestAccessibility: () =>
                  QuizPluginEntry.requestAccessibility(),
            ),
            const SizedBox(height: AppTokens.spaceLg),
            SwitchListTile(
              title: const Text('启用答题助手'),
              subtitle: const Text('开启至少一种搜题方式即生效'),
              value: _cfg.enabled,
              onChanged: (v) => setState(
                () => _cfg = _cfg.copyWith(
                  enabled: v,
                  accessibilityCapture: v ? true : _cfg.accessibilityCapture,
                ),
              ),
            ),
            SwitchListTile(
              title: const Text('收到题目自动搜题'),
              subtitle: const Text('关闭后仅展示当前捕获内容，手动触发搜题'),
              value: _cfg.autoSearch,
              onChanged: (v) =>
                  setState(() => _cfg = _cfg.copyWith(autoSearch: v)),
            ),
            SwitchListTile(
              title: const Text('离开 App 自动考试模式'),
              subtitle: const Text(
                '切到其他 App 时自动缩小为「仅答案+相似度」；回到 box 恢复。改完点保存立即生效。',
              ),
              value: _cfg.autoExamOnLeaveApp,
              onChanged: (v) async {
                setState(() => _cfg = _cfg.copyWith(autoExamOnLeaveApp: v));
                // 立即落盘并通知原生，悬浮窗马上按新规则重算
                await QuizPluginEntry.saveConfig(_cfg);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        v ? '已开启：离开 App 自动进入考试模式' : '已关闭：不再自动进入考试模式',
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
            if (_cfg.autoExamOnLeaveApp) ...[
              TextFormField(
                initialValue: _cfg.autoExamPackages,
                decoration: const InputDecoration(
                  labelText: '自动考试模式包名白名单（可选）',
                  hintText: '空=全部第三方；多包用逗号或换行，如 com.xxx.driver',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
                onChanged: (v) =>
                    setState(() => _cfg = _cfg.copyWith(autoExamPackages: v)),
              ),
              const SizedBox(height: 10),
              const Text('考试模式悬浮窗大小'),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'small', label: Text('小')),
                  ButtonSegment(value: 'standard', label: Text('标准')),
                  ButtonSegment(value: 'large', label: Text('大')),
                ],
                selected: {_cfg.examOverlaySize},
                onSelectionChanged: (value) async {
                  final size = value.first;
                  setState(() => _cfg = _cfg.copyWith(examOverlaySize: size));
                  // 立即落盘并通知原生：当前考试窗立刻换尺寸。
                  await QuizPluginEntry.saveConfig(_cfg);
                },
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '标准：兼顾不挡题与答案可读性；考试窗仍只显示答案与相似度。',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            ],
            SwitchListTile(
              title: const Text('调试捕获文本'),
              subtitle: const Text(
                '开启后会把无障碍捕获到的屏幕文本先显示到通知/悬浮窗，用来判断是捕获问题还是题库匹配问题',
              ),
              value: _cfg.debugCapture,
              onChanged: (v) =>
                  setState(() => _cfg = _cfg.copyWith(debugCapture: v)),
            ),
            SwitchListTile(
              title: const Text('过滤无关文本'),
              subtitle: const Text('过滤设置、广告、上一题/下一题等界面噪声；调试时可临时关闭'),
              value: _cfg.filterNoise,
              onChanged: (v) =>
                  setState(() => _cfg = _cfg.copyWith(filterNoise: v)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('最大捕获行数'),
              subtitle: Slider(
                min: 1,
                max: 20,
                divisions: 19,
                label: '${_cfg.maxCaptureLines} 行',
                value: _cfg.maxCaptureLines.clamp(1, 20).toDouble(),
                onChanged: (v) => setState(
                  () => _cfg = _cfg.copyWith(maxCaptureLines: v.round()),
                ),
              ),
              trailing: Text('${_cfg.maxCaptureLines.clamp(1, 20)} 行'),
            ),
            SwitchListTile(
              title: const Text('允许外部网络搜题'),
              subtitle: const Text('默认关闭：关闭时只查本地题库，避免把题目发送到第三方 API'),
              value: _cfg.allowExternalApi,
              onChanged: (v) =>
                  setState(() => _cfg = _cfg.copyWith(allowExternalApi: v)),
            ),
            SwitchListTile(
              title: const Text('无障碍读屏搜题'),
              subtitle: const Text('由无障碍服务读取屏幕题目文本后搜题（抗屏蔽，推荐）。关闭后改用 OCR 截图搜题。'),
              value: _cfg.accessibilityCapture,
              onChanged: (v) => setState(
                () => _cfg = _cfg.copyWith(
                  accessibilityCapture: v,
                  enabled: v || _cfg.ocrSearch,
                ),
              ),
            ),
            SwitchListTile(
              title: const Text('OCR 截图搜题'),
              subtitle: const Text(
                '截屏识别区域→OCR→搜题，不依赖读屏文本，有些人觉得更快。需 Android 11+，对加密/防截屏页面无效。',
              ),
              value: _cfg.ocrSearch,
              onChanged: (v) => setState(
                () => _cfg = _cfg.copyWith(
                  ocrSearch: v,
                  enabled: v || _cfg.accessibilityCapture,
                ),
              ),
            ),
            if (_cfg.ocrSearch) ...[
              const SizedBox(height: AppTokens.spaceSm),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'OCR 服务地址',
                  hintText: 'https://ocr.hpa888.top',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                controller: _ocrEndpointController,
                onChanged: (v) => _cfg = _cfg.copyWith(ocrEndpoint: v),
              ),
              const SizedBox(height: AppTokens.spaceSm),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'OCR Token（可选）',
                  hintText: '留空则免密',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                obscureText: true,
                controller: _ocrTokenController,
                onChanged: (v) => _cfg = _cfg.copyWith(ocrToken: v),
              ),
            ],
            const SizedBox(height: AppTokens.spaceMd),
            Text('显示模式', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'accessibility',
                  label: Text('无障碍悬浮'),
                  icon: Icon(Icons.accessibility_new),
                ),
                ButtonSegment(
                  value: 'notification',
                  label: Text('通知'),
                  icon: Icon(Icons.notifications),
                ),
                ButtonSegment(
                  value: 'manual',
                  label: Text('手动'),
                  icon: Icon(Icons.edit_note),
                ),
              ],
              selected: {_cfg.displayMode},
              onSelectionChanged: (values) {
                setState(() => _cfg = _cfg.copyWith(displayMode: values.first));
              },
            ),
            const SizedBox(height: 6),
            Text(
              _displayModeHint(_cfg.displayMode),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTokens.textSecondary),
            ),
            const SizedBox(height: AppTokens.spaceMd),
            Text('主题色', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: colorOptions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final selected =
                      themeColors.isNotEmpty &&
                      themeColors[_cfg.themeColorIndex % themeColors.length]
                              .value ==
                          colorOptions[i].value;
                  return GestureDetector(
                    onTap: () => setState(
                      () => _cfg = _cfg.copyWith(themeColorIndex: i),
                    ),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colorOptions[i],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? AppTokens.textPrimary
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppTokens.spaceLg),
            Text('悬浮窗外观', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.opacity, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: _cfg.overlayOpacity,
                    min: 0.3,
                    max: 1.0,
                    divisions: 14,
                    label: '${(_cfg.overlayOpacity * 100).round()}%',
                    onChanged: (v) {
                      setState(() => _cfg = _cfg.copyWith(overlayOpacity: v));
                      QuizPluginEntry.setOverlayOpacity(v);
                    },
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '${(_cfg.overlayOpacity * 100).round()}%',
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              '位置/大小/字号：长按悬浮窗标题栏可拖动，右下角手柄缩放，标题栏「+」循环字号，「∧」折叠；设置会自动记忆。',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTokens.textSecondary),
            ),
            const SizedBox(height: AppTokens.spaceLg),
            Text('API 地址', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              enabled: _cfg.allowExternalApi,
              decoration: const InputDecoration(
                hintText: 'https://example.com/search',
                helperText: '需先开启“允许外部网络搜题”',
                border: OutlineInputBorder(),
              ),
              controller: _apiUrlController,
              onChanged: (v) => _cfg = _cfg.copyWith(apiUrl: v),
            ),
            const SizedBox(height: AppTokens.spaceMd),
            TextField(
              enabled: _cfg.allowExternalApi,
              decoration: const InputDecoration(
                hintText: 'API Key',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              controller: _apiKeyController,
              onChanged: (v) => _cfg = _cfg.copyWith(apiKey: v),
            ),
            const SizedBox(height: AppTokens.spaceXl),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _saving
                        ? null
                        : () async {
                            setState(() => _saving = true);
                            await QuizPluginEntry.showRegionSheet(context);
                            await QuizPluginEntry.saveConfig(_cfg);
                            if (mounted) {
                              Navigator.pop(context);
                              widget.onResult(_cfg);
                            }
                            setState(() => _saving = false);
                          },
                    child: const Text('设置识别区域'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _saving
                        ? null
                        : () async {
                            await QuizPluginEntry.saveConfig(_cfg);
                            if (_cfg.displayMode == 'notification') {
                              await QuizPluginEntry.requestNotificationPermission();
                            }
                            if (mounted) {
                              Navigator.pop(context);
                              widget.onResult(_cfg);
                            }
                          },
                    child: Text(_saving ? '保存中...' : '保存'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.spaceXl),
          ],
        ),
      ),
    );
  }
}

// ================================================
// 识别区域调节 Page
// ================================================

String _displayModeHint(String mode) {
  switch (mode) {
    case 'accessibility':
      return '推荐：由无障碍服务创建系统级悬浮窗展示答案，可绕过驾考宝典等 App 的悬浮窗屏蔽/考试模式限制；无需单独的悬浮窗权限，只要开启无障碍服务即可。无障碍未开启时自动降级为通知栏。';
    case 'manual':
      return '不主动弹出悬浮窗或通知，只保留应用内手动搜题。';
    default:
      return '用通知栏显示结果，稳定但需要下拉查看；适合无法开启无障碍服务时使用。';
  }
}

class _RegionSheetPage extends StatefulWidget {
  const _RegionSheetPage();

  @override
  State<_RegionSheetPage> createState() => _RegionSheetPageState();
}

class _RegionSheetPageState extends State<_RegionSheetPage> {
  Rect _region = const Rect.fromLTWH(50, 300, 400, 300);

  @override
  void initState() {
    super.initState();
    _syncToNative();
    QuizPluginEntry._regionPreviewNotifier.addListener(_onPreview);
  }

  @override
  void dispose() {
    QuizPluginEntry._regionPreviewNotifier.removeListener(_onPreview);
    super.dispose();
  }

  void _onPreview() {
    final r = QuizPluginEntry._regionPreviewNotifier.value;
    if (r != null && mounted) {
      // 原生框选拖动时实时联动数字（仅在没有正在编辑文本时覆盖）
      setState(() => _region = r);
    }
  }

  Future<void> _syncToNative() async {
    await QuizPluginEntry.updateRegion(_region);
  }

  Future<void> _openNativeSelector() async {
    await QuizPluginEntry.openRegionSelector();
  }

  void _applyPreset(Rect rectF) {
    setState(
      () => _region = Rect.fromLTWH(
        rectF.left * _screenW,
        rectF.top * _screenH,
        (rectF.right - rectF.left) * _screenW,
        (rectF.bottom - rectF.top) * _screenH,
      ),
    );
    QuizPluginEntry.applyRegionPreset(rectF);
    _syncToNative();
  }

  double get _screenW => MediaQuery.of(context).size.width;
  double get _screenH => MediaQuery.of(context).size.height;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('识别区域调节'),
        actions: [
          IconButton(
            onPressed: _openNativeSelector,
            icon: const Icon(Icons.crop_free_rounded),
            tooltip: '在悬浮窗中调节',
          ),
          IconButton(
            onPressed: () async {
              await _syncToNative();
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已同步到原生悬浮窗')));
              }
            },
            icon: const Icon(Icons.check),
            tooltip: '同步',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = constraints.maxHeight;
                // 预览按屏幕真实比例映射，所见即所得
                final scaleX = width / _screenW;
                final scaleY = height / _screenH;
                final previewRect = Rect.fromLTRB(
                  _region.left * scaleX,
                  _region.top * scaleY,
                  _region.right * scaleX,
                  _region.bottom * scaleY,
                );
                return RepaintBoundary(
                  child: CustomPaint(
                    size: Size(width, height),
                    painter: _RegionPainter(
                      region: previewRect,
                      maxSize: Size(width, height),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(AppTokens.spaceXl),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  blurRadius: 12,
                  color: Theme.of(context).shadowColor.withOpacity(0.1),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: () => _applyPreset(
                          const Rect.fromLTRB(0.02, 0.04, 0.98, 0.55),
                        ),
                        child: const Text('题干带'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _applyPreset(
                          const Rect.fromLTRB(0.04, 0.28, 0.96, 0.72),
                        ),
                        child: const Text('中部'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _applyPreset(
                          const Rect.fromLTRB(0.02, 0.04, 0.98, 0.96),
                        ),
                        child: const Text('全屏'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          label: 'Left',
                          value: _region.left.toInt(),
                          onChanged: (v) {
                            setState(
                              () => _region = Rect.fromLTWH(
                                v.toDouble(),
                                _region.top,
                                _region.width,
                                _region.height,
                              ),
                            );
                            _syncToNative();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          label: 'Top',
                          value: _region.top.toInt(),
                          onChanged: (v) {
                            setState(
                              () => _region = Rect.fromLTWH(
                                _region.left,
                                v.toDouble(),
                                _region.width,
                                _region.height,
                              ),
                            );
                            _syncToNative();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          label: 'Width',
                          value: _region.width.toInt(),
                          onChanged: (v) {
                            setState(
                              () => _region = Rect.fromLTWH(
                                _region.left,
                                _region.top,
                                v.toDouble(),
                                _region.height,
                              ),
                            );
                            _syncToNative();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          label: 'Height',
                          value: _region.height.toInt(),
                          onChanged: (v) {
                            setState(
                              () => _region = Rect.fromLTWH(
                                _region.left,
                                _region.top,
                                _region.width,
                                v.toDouble(),
                              ),
                            );
                            _syncToNative();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegionPainter extends CustomPainter {
  final Rect region;
  final Size maxSize;

  _RegionPainter({required this.region, required this.maxSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x33000000)
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = const Color(0xFF4F46E5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..isAntiAlias = true;

    canvas.drawRect(Offset.zero & maxSize, paint);
    canvas.drawRect(region, border);

    final texts = [
      '识别区域',
      'x: ${region.left.toInt()}, y: ${region.top.toInt()}',
      'w: ${region.width.toInt()}, h: ${region.height.toInt()}',
    ];
    final hintPaint = Paint()
      ..shader = LinearGradient(
        colors: [Colors.black, Colors.transparent],
      ).createShader(region)
      ..style = PaintingStyle.fill;
    final textPaint = TextPainter(
      text: const TextSpan(
        text: '',
        style: TextStyle(color: Colors.white, fontSize: 13),
      ),
      textDirection: TextDirection.ltr,
    );

    canvas.drawRect(
      Rect.fromLTWH(region.left, region.top, region.width, 48),
      hintPaint,
    );
    texts.asMap().forEach((i, line) {
      textPaint.text = TextSpan(
        text: line,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      );
      textPaint.layout();
      textPaint.paint(
        canvas,
        Offset(region.left + 12, region.top + 8 + i * 18),
      );
    });
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _Field extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _Field({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      controller: TextEditingController(text: value.toString())
        ..selection = TextSelection.fromPosition(
          TextPosition(offset: value.toString().length),
        ),
      onChanged: (v) {
        final n = int.tryParse(v);
        if (n != null) onChanged(n);
      },
    );
  }
}
