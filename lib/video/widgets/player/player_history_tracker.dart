import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../../utils/app_logger.dart';
import '../../controller/history_controller.dart';
import 'video_play_args.dart';

class PlayerHistoryTracker {
  PlayerHistoryTracker({required this.historyController, required this.args});

  final HistoryController historyController;
  final VideoPlayArgs args;

  VideoPlayerController? _controller;
  Timer? _timer;
  bool _isPlaying = false;
  int _lastSavedPositionMs = -1;
  Future<void> _pendingSave = Future<void>.value();

  void attach(VideoPlayerController controller) {
    _controller = controller;
  }

  /// 播放状态变化时调用：
  /// - playing = true：启动定时保存
  /// - playing = false：停止定时器
  void setPlaying(bool playing) {
    if (_isPlaying == playing) return;
    _isPlaying = playing;

    if (!playing) {
      _timer?.cancel();
      _timer = null;
      return;
    }

    if (_controller == null) return;
    if (_timer != null) return;

    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(saveNow());
    });
  }

  Future<void> saveNow({bool force = false}) {
    _pendingSave = _pendingSave.catchError((_) {}).then((_) async {
      final controller = _controller;
      if (controller == null) return;
      if (!controller.value.isInitialized) return;

      final posMs = controller.value.position.inMilliseconds;
      final durMs = controller.value.duration.inMilliseconds;
      await _persist(posMs, durMs, force);
    });
    return _pendingSave;
  }

  /// 同步抓取当前进度后在后台写入。
  ///
  /// 用于切集 / dispose 前：pos/dur 在调用时刻立即读出，随后即使
  /// controller 被 dispose 也不会污染这次保存。切集时本地 IO 不再
  /// 串行阻塞新流解析。
  Future<void> saveSnapshot() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return _pendingSave;
    }

    final posMs = controller.value.position.inMilliseconds;
    final durMs = controller.value.duration.inMilliseconds;

    _pendingSave = _pendingSave
        .catchError((_) {})
        .then((_) => _persist(posMs, durMs, true));
    return _pendingSave;
  }

  Future<void> _persist(int posMs, int durMs, bool force) async {
    if (posMs <= 0 || durMs <= 0 || args.vodId.trim().isEmpty) return;
    if (!force && _lastSavedPositionMs >= 0) {
      final delta = (posMs - _lastSavedPositionMs).abs();
      if (delta < 3000) return;
    }

    _lastSavedPositionMs = posMs;
    try {
      if (kDebugMode || args.showDebugInfo) {
        AppLogger.instance.log(
          '保存历史: vodId=${args.vodId}, pos=$posMs, dur=$durMs, episode=${args.episodeName}',
          tag: 'HISTORY',
        );
      }
      await historyController.saveProgress(
        vodId: args.vodId,
        vodName: args.title,
        vodPic: args.vodPic,
        sourceId: args.sourceId,
        sourceName: args.sourceName,
        episodeName: args.episodeName,
        episodeUrl: args.url,
        position: posMs,
        duration: durMs,
      );
    } catch (e, st) {
      AppLogger.instance.logError(e, st, 'HISTORY');
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _isPlaying = false;
  }
}
