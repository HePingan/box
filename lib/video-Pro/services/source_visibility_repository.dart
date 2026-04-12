import 'package:hive_flutter/hive_flutter.dart';
import '../models/source_visibility_record.dart';
import '../models/video_source.dart';

class SourceVisibilityRepository {
  static const String _boxName = 'video_source_visibility_box';

  // 🏆 优化：线程安全的同步 Box 获取器
  Box<dynamic>? get _box {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box(_boxName);
    }
    return null;
  }

  Future<void> init() async {
    // 🏆 优化：防并发开启检测
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
  }

  String keyOf(VideoSource source) {
    final id = source.id;
    if (id.trim().isNotEmpty && id != 'null') {
      return id.trim();
    }
    return source.url.trim();
  }

  SourceVisibilityRecord getRecord(VideoSource source) {
    return getRecordByKey(keyOf(source));
  }

  SourceVisibilityRecord getRecordByKey(String key) {
    // 🏆 优化：Hive 开启后常驻内存，直接同步读取无开销
    final raw = _box?.get(key);
    if (raw is Map) {
      return SourceVisibilityRecord.fromJson(Map<String, dynamic>.from(raw));
    }
    return SourceVisibilityRecord(key: key);
  }

  Future<void> saveRecord(SourceVisibilityRecord record) async {
    await init(); // 写入前确保已打开
    await Hive.box(_boxName).put(record.key, record.toJson());
  }

  Future<void> setManualHidden(
    VideoSource source,
    bool hidden, {
    String? reason,
  }) async {
    final record = getRecord(source);
    final updated = record.copyWith(
      manualHidden: hidden,
      lastReason: reason ?? record.lastReason,
      lastCheckedAt: DateTime.now(),
    );
    await saveRecord(updated);
  }

  Future<void> setAutoHidden(
    VideoSource source,
    bool hidden, {
    String? reason,
    int? failCount,
    bool? lastPlayable,
  }) async {
    final record = getRecord(source);
    final updated = record.copyWith(
      autoHidden: hidden,
      failCount: failCount ?? record.failCount,
      lastReason: reason ?? record.lastReason,
      lastPlayable: lastPlayable ?? record.lastPlayable,
      lastCheckedAt: DateTime.now(),
    );
    await saveRecord(updated);
  }

  Future<void> markSuccess(VideoSource source) async {
    final record = getRecord(source);
    final updated = record.copyWith(
      autoHidden: false,
      failCount: 0,
      lastPlayable: true,
      lastReason: 'ok',
      lastCheckedAt: DateTime.now(),
    );
    await saveRecord(updated);
  }

  Future<void> markFailure(
    VideoSource source, {
    required String reason,
    required bool autoHide,
  }) async {
    final record = getRecord(source);
    final updated = record.copyWith(
      autoHidden: autoHide,
      failCount: record.failCount + 1,
      lastPlayable: false,
      lastReason: reason,
      lastCheckedAt: DateTime.now(),
    );
    await saveRecord(updated);
  }

  bool isVisible(VideoSource source) {
    final record = getRecord(source);
    return !record.isHidden;
  }

  List<VideoSource> filterVisible(
    List<VideoSource> sources, {
    bool includeHidden = false,
  }) {
    if (includeHidden) return sources;
    return sources.where((s) => isVisible(s)).toList();
  }
}