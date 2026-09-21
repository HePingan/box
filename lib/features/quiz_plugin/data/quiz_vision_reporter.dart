import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:typed_data';

import '../../account/data/account_store.dart';
import '../../policy/plugin_policy.dart';
import '../domain/quiz_bank.dart';
import '../domain/quiz_vision_candidate.dart';
import './quiz_cloud_push.dart';
import './quiz_vision_candidate_store.dart';

/// AI 读屏命中 → 静默上报后端待审核区的协调器。
///
/// 用户 2026-09-13 拍板四条（逐字）：
///   1. 「A 档不提交，保留该题的截图及 ai 识别的题目信息，后面我再手动补充」
///   2. 「命中静默」
///   3. 「conf 大于等于 0.9」
///   4. 「可以」（未登录静默禁用）
///
/// 设计约束：
///   - **静默**：本类任何方法都不向 UI 抛异常/弹提示。失败只记录，用户无感。
///   - **不阻塞**：调用方以 `unawaited(...)` 方式触发，悬浮窗渲染不等它。
///   - **必留档**：无论是否上报成功，截图 + 识别信息都先进本地队列。
class QuizVisionReporter {
  QuizVisionReporter({
    QuizCloudPushCoordinator? push,
    BoxAccountStore? accountStore,
    QuizVisionCandidateStore? store,
  }) : _push = push ?? QuizCloudPushCoordinator(),
       _accountStore = accountStore ?? BoxAccountStore();

  final QuizCloudPushCoordinator _push;
  final BoxAccountStore _accountStore;

  /// 记录一次读屏命中：先留档，再按闸门决定是否静默上报。
  ///
  /// [screenshot] 为原始截图 bytes（可为 null：手工触发时也可能拿不到图）。
  /// 返回落档后的候选（已带 id / imagePath），便于调用方展示。
  Future<QuizVisionCandidate> record({
    required String stem,
    required List<String> options,
    required String answer,
    required double confidence,
    Uint8List? screenshot,
    String? analysis,
  }) async {
    String? imagePath;
    if (screenshot != null && screenshot.isNotEmpty) {
      try {
        imagePath = await QuizVisionCandidateStore.persistScreenshot(screenshot);
      } catch (_) {
        imagePath = null; // 留档失败不影响上报判定
      }
    }

    // 读登录态与插件策略（全部静默，失败按最保守处理）。
    var loggedIn = false;
    var cloudPushAllowed = false;
    try {
      final session = await _accountStore.loadSession();
      loggedIn = session != null && session.token.trim().isNotEmpty;
    } catch (_) {
      loggedIn = false;
    }
    try {
      final denial = await PluginGate.denial(
        PluginIds.quizBankView,
        feature: PluginFeature.cloudPush,
      );
      cloudPushAllowed = denial == null;
    } catch (_) {
      cloudPushAllowed = false;
    }

    final id = _idFor(stem: stem, answer: answer, imagePath: imagePath);
    var candidate = QuizVisionCandidate(
      id: id,
      stem: stem,
      options: options,
      answer: answer,
      confidence: confidence,
      capturedAt: DateTime.now(),
      imagePath: imagePath,
      loggedIn: loggedIn,
      cloudPushAllowed: cloudPushAllowed,
      analysis: analysis,
    );

    try {
      await QuizVisionCandidateStore.add(candidate);
    } catch (_) {
      // 留档失败也不能影响答题主流程。
    }

    if (!candidate.canAutoSubmit) return candidate;

    // 满足全部闸门 → 静默上报。任何异常都吞掉（用户无感）。
    try {
      final item = candidate.toBankItem(id: id);
      // 上报前先把题写进本地题库，投稿元数据才有稳定 id 可挂。
      await QuizBankStorage.upsertItem(item);
      final result = await _push.pushItems([item], onProgress: null);
      final ok = result.submitted + result.merged > 0;
      candidate = candidate.copyWith();
      if (!ok) {
        // 未成功不打扰用户，留档仍在，后续可手动重投。
      }
    } catch (_) {
      // 静默：网络/服务端异常一律不打扰答题。
    }
    return candidate;
  }

  static String _idFor({
    required String stem,
    required String answer,
    String? imagePath,
  }) {
    final seed = '$stem|$answer|${imagePath ?? ''}';
    final digest = sha256.convert(utf8.encode(seed)).toString();
    return 'q_vision_${digest.substring(0, 16)}';
  }
}
