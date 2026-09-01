import '../../account/data/account_store.dart';
import '../../account/domain/account_models.dart';
import '../../policy/plugin_policy.dart';
import '../domain/quiz_bank.dart';
import './quiz_cloud_sync.dart';

/// 本地题投稿到云端审核队列的协调层。
///
/// 复用 [QuizCloudSyncService.submit] → `POST /api/quiz/submissions`，
/// 成功后只写本地 sync 元数据，不改变搜题 canonical id。
class QuizCloudPushCoordinator {
  QuizCloudPushCoordinator({
    QuizCloudSyncService? syncService,
    BoxAccountStore? accountStore,
  }) : _sync = syncService ?? QuizCloudSyncService(),
       _accountStore = accountStore ?? BoxAccountStore();

  final QuizCloudSyncService _sync;
  final BoxAccountStore _accountStore;

  /// 投稿前校验：题干非空、选项≥2、答案非空。
  static String? validateForPush(QuizBankItem item) {
    if (item.question.trim().isEmpty) return '题干不能为空';
    final options = item.options
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (options.length < 2) return '至少需要两个选项';
    if (item.correctAnswer.trim().isEmpty) return '正确答案不能为空（请先补答案）';
    return null;
  }

  Future<String> resolveServerUrl() async {
    final saved = await _accountStore.loadServerUrl();
    return BoxAccountDefaults.normalizeServerUrl(saved);
  }

  Future<BoxAccountSession?> loadSession() => _accountStore.loadSession();

  /// 批量投稿。云端镜像题跳过；校验失败计入 invalid。
  Future<QuizCloudPushResult> pushItems(
    List<QuizBankItem> items, {
    String? category,
    void Function(String message)? onProgress,
  }) async {
    final session = await loadSession();
    if (session == null || session.token.trim().isEmpty) {
      throw const QuizCloudPushException('未登录，请先在账号页登录后再推送云端');
    }
    final denial = await PluginGate.denial(
      PluginIds.quizBankView,
      feature: PluginFeature.cloudPush,
    );
    if (denial != null) {
      throw QuizCloudPushException(denial);
    }
    final serverUrl = BoxAccountDefaults.normalizeServerUrl(session.serverUrl);
    final fallbackCategory = (category ?? '').trim();

    var submitted = 0;
    var pending = 0;
    var merged = 0;
    var skippedCloud = 0;
    var invalid = 0;
    var failed = 0;
    final errors = <String>[];
    final mergedQuestionIds = <String>[];

    final targets = items.toList(growable: false);
    for (var i = 0; i < targets.length; i++) {
      final item = targets[i];
      onProgress?.call('推送 ${i + 1}/${targets.length}…');

      if (item.isCloud) {
        skippedCloud++;
        continue;
      }

      final validationError = validateForPush(item);
      if (validationError != null) {
        invalid++;
        if (errors.length < 8) {
          errors.add('${_shortQuestion(item.question)}：$validationError');
        }
        await QuizBankStorage.updateSyncMeta(
          item.id,
          syncStatus: item.syncStatus == QuizSyncStatus.pendingReview
              ? QuizSyncStatus.pendingReview
              : QuizSyncStatus.localOnly,
          lastSubmitAt: DateTime.now(),
          lastSubmitError: validationError,
        );
        continue;
      }

      try {
        final cat = item.category.trim().isNotEmpty
            ? item.category.trim()
            : fallbackCategory;
        final result = await _sync.submit(
          serverUrl: serverUrl,
          token: session.token,
          item: item,
          category: cat,
        );
        final remoteStatus = result.status.trim().toLowerCase();
        final localStatus = remoteStatus == 'merged'
            ? QuizSyncStatus.merged
            : remoteStatus == 'rejected'
            ? QuizSyncStatus.rejected
            : QuizSyncStatus.pendingReview;
        await QuizBankStorage.updateSyncMeta(
          item.id,
          syncStatus: localStatus,
          lastSubmitAt: DateTime.now(),
          lastSubmitError: null,
          remoteSubmissionId: result.id,
          clearLastSubmitError: true,
        );
        submitted++;
        if (localStatus == QuizSyncStatus.merged) {
          merged++;
          // 服务端判定同题时会回传云端题目 ID。它是用户唯一的线索：
          // 没有它就不知道该去后台改/删哪一条。记下来供 UI 展示。
          final linked = result.linkedQuestionId?.trim() ?? '';
          if (linked.isNotEmpty) {
            mergedQuestionIds.add(linked);
          }
        } else if (localStatus == QuizSyncStatus.pendingReview) {
          pending++;
        }
      } catch (e) {
        failed++;
        final msg = e.toString();
        if (errors.length < 8) {
          errors.add('${_shortQuestion(item.question)}：$msg');
        }
        await QuizBankStorage.updateSyncMeta(
          item.id,
          syncStatus: QuizSyncStatus.localOnly,
          lastSubmitAt: DateTime.now(),
          lastSubmitError: msg,
        );
      }
    }

    try {
      await QuizBankCache.instance.reload();
    } catch (_) {}

    return QuizCloudPushResult(
      serverUrl: serverUrl,
      total: targets.length,
      submitted: submitted,
      pending: pending,
      merged: merged,
      skippedCloud: skippedCloud,
      invalid: invalid,
      failed: failed,
      errors: errors,
      mergedQuestionIds: List.unmodifiable(mergedQuestionIds),
    );
  }

  void dispose() => _sync.dispose();

  static String _shortQuestion(String q) {
    final t = q.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.length <= 18) return t;
    return '${t.substring(0, 18)}…';
  }
}

/// 把云端审核终态回写到本地题库。
/// 仅使用当前登录态接口，不接受也不发送 userId。
class QuizSubmissionReconciler {
  QuizSubmissionReconciler({
    QuizCloudSyncService? syncService,
    BoxAccountStore? accountStore,
    Future<List<QuizBankItem>> Function()? loadLocalItems,
    Future<void> Function(
      String id, {
      required String syncStatus,
      String? lastSubmitError,
      String? remoteSubmissionId,
      bool clearLastSubmitError,
    })?
    updateSyncMeta,
  }) : _sync = syncService ?? QuizCloudSyncService(),
       _accountStore = accountStore ?? BoxAccountStore(),
       _loadLocalItems = loadLocalItems ?? QuizBankStorage.loadAll,
       _updateSyncMeta = updateSyncMeta ?? QuizBankStorage.updateSyncMeta;

  final QuizCloudSyncService _sync;
  final BoxAccountStore _accountStore;
  final Future<List<QuizBankItem>> Function() _loadLocalItems;
  final Future<void> Function(
    String id, {
    required String syncStatus,
    String? lastSubmitError,
    String? remoteSubmissionId,
    bool clearLastSubmitError,
  })
  _updateSyncMeta;

  Future<QuizSubmissionReconcileResult> reconcile() async {
    final session = await _accountStore.loadSession();
    if (session == null || session.token.trim().isEmpty) {
      throw const QuizCloudSyncException('未登录，无法刷新投稿审核状态');
    }
    final remotes = await _sync.fetchMySubmissions(
      serverUrl: BoxAccountDefaults.normalizeServerUrl(session.serverUrl),
      token: session.token,
    );
    final decisions = decide(locals: await _loadLocalItems(), remotes: remotes);
    for (final decision in decisions) {
      await _updateSyncMeta(
        decision.localId,
        syncStatus: decision.syncStatus,
        lastSubmitError: decision.reviewNote,
        remoteSubmissionId: decision.remoteSubmissionId,
        clearLastSubmitError: decision.reviewNote.trim().isEmpty,
      );
    }
    return QuizSubmissionReconcileResult(
      checked: remotes.length,
      updated: decisions.length,
      decisions: decisions,
    );
  }

  static List<QuizSubmissionReconcileDecision> decide({
    required List<QuizBankItem> locals,
    required List<QuizCloudSubmission> remotes,
  }) {
    final byRemoteId = <String, QuizCloudSubmission>{
      for (final item in remotes)
        if (item.id.trim().isNotEmpty && item.isSettled) item.id.trim(): item,
    };
    final byFingerprint = <String, List<QuizCloudSubmission>>{};
    for (final item in remotes) {
      if (!item.isSettled) continue;
      final fingerprint = _fingerprintRemote(item);
      if (fingerprint.isEmpty) continue;
      (byFingerprint[fingerprint] ??= []).add(item);
    }
    final decisions = <QuizSubmissionReconcileDecision>[];
    for (final local in locals) {
      if (local.isCloud || local.syncStatus != QuizSyncStatus.pendingReview) {
        continue;
      }
      final id = local.remoteSubmissionId?.trim() ?? '';
      final remoteById = id.isEmpty ? null : byRemoteId[id];
      final fallbackMatches = byFingerprint[_fingerprintLocal(local)];
      final remote =
          remoteById ??
          (fallbackMatches != null && fallbackMatches.length == 1
              ? fallbackMatches.single
              : null);
      final status = remote?.localSyncStatus;
      if (remote == null || status == null) continue;
      decisions.add(
        QuizSubmissionReconcileDecision(
          localId: local.id,
          syncStatus: status,
          remoteSubmissionId: remote.id,
          reviewNote: remote.reviewNote,
        ),
      );
    }
    return List<QuizSubmissionReconcileDecision>.unmodifiable(decisions);
  }

  static String _fingerprintLocal(QuizBankItem item) => _fingerprintParts(
    item.question,
    item.options,
    imageSha256: item.imageSha256,
    imagePerceptualHash: item.imagePerceptualHash,
  );

  static String _fingerprintRemote(QuizCloudSubmission item) =>
      _fingerprintParts(
        item.question,
        item.options,
        imageSha256: item.imageSha256,
        imagePerceptualHash: item.imagePerceptualHash,
      );

  static String _fingerprintParts(
    String question,
    List<String> options, {
    String? imageSha256,
    String? imagePerceptualHash,
  }) {
    String normalize(String value) =>
        value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final q = normalize(question);
    if (q.isEmpty) return '';
    final phash = normalize(imagePerceptualHash ?? '');
    final sha256 = normalize(imageSha256 ?? '');
    final image = phash.isNotEmpty
        ? '|phash:$phash'
        : (sha256.isNotEmpty ? '|sha256:$sha256' : '');
    return '$q|${options.map(normalize).join('|')}$image';
  }

  void dispose() => _sync.dispose();
}

class QuizSubmissionReconcileDecision {
  const QuizSubmissionReconcileDecision({
    required this.localId,
    required this.syncStatus,
    required this.remoteSubmissionId,
    this.reviewNote = '',
  });
  final String localId;
  final String syncStatus;
  final String remoteSubmissionId;
  final String reviewNote;
}

class QuizSubmissionReconcileResult {
  const QuizSubmissionReconcileResult({
    required this.checked,
    required this.updated,
    required this.decisions,
  });
  final int checked;
  final int updated;
  final List<QuizSubmissionReconcileDecision> decisions;
}

class QuizCloudPushResult {
  const QuizCloudPushResult({
    required this.serverUrl,
    required this.total,
    required this.submitted,
    required this.pending,
    required this.merged,
    required this.skippedCloud,
    required this.invalid,
    required this.failed,
    this.errors = const [],
    this.mergedQuestionIds = const [],
  });

  final String serverUrl;
  final int total;
  final int submitted;
  final int pending;
  final int merged;
  final int skippedCloud;
  final int invalid;
  final int failed;
  final List<String> errors;

  /// 被服务端判定为同题（merged）的云端题目 ID。
  /// 用户要改/删云端那条时，靠它定位。
  final List<String> mergedQuestionIds;

  String get summaryText {
    final parts = <String>[
      '提交 $submitted',
      if (pending > 0) '待审 $pending',
      if (merged > 0) '云端已有 $merged',
      if (skippedCloud > 0) '跳过云镜像 $skippedCloud',
      if (invalid > 0) '校验失败 $invalid',
      if (failed > 0) '失败 $failed',
    ];
    final base = parts.join(' · ');
    // 「提交成功但后台没有待审核投稿」最常见的原因是服务端判定同题
    // （merged / 云端已有），而不是推送失败。把它说明白，省掉一轮排查。
    if (submitted > 0 && pending == 0 && merged > 0) {
      final ids = mergedQuestionIds.take(3).join('、');
      return '$base\n服务端判定为云端已有同题，未新建待审核记录。'
          '这道题云端已存在，不会再进审核队列；'
          '要补图请在后台「题库」里直接编辑它'
          '${ids.isEmpty ? '' : '（题目 ID：$ids）'}。';
    }
    if (submitted == 0 && merged == 0 && pending == 0) {
      return '$base\n没有任何题进入待审核队列，请检查上面的失败原因。';
    }
    return base;
  }
}

class QuizCloudPushException implements Exception {
  const QuizCloudPushException(this.message);
  final String message;
  @override
  String toString() => message;
}
