import 'package:hive_flutter/hive_flutter.dart';

import '../models/video_source.dart';

/// 记住用户在某一部影片里手动选择的线路。
///
/// 键：`sourceKey::vodId`
/// 值：{ lineName, lineIndex, savedAt }
///
/// 说明：
/// - 优先用 lineName 复原，因为重新拉取详情后线路顺序可能变化，
///   索引会漂移，名字更稳定。
/// - lineIndex 仅作为名字都对不上的兜底。
class PlayLineMemoryRepository {
  static const String _boxName = 'video_play_line_memory_box';

  Box<dynamic>? get _box {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box(_boxName);
    }
    return null;
  }

  Future<void> init() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
  }

  String _sourceKey(VideoSource source) {
    final id = source.id;
    if (id.trim().isNotEmpty && id != 'null') {
      return id.trim();
    }
    return source.url.trim();
  }

  String keyOf(VideoSource source, int vodId) {
    return '${_sourceKey(source)}::$vodId';
  }

  /// 读取记忆的线路。返回 null 表示没有记录。
  PlayLineMemory? getMemory(VideoSource source, int vodId) {
    final raw = _box?.get(keyOf(source, vodId));
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final lineName = (map['lineName'] as String?)?.trim() ?? '';
      final lineIndex = (map['lineIndex'] as num?)?.toInt() ?? 0;
      if (lineName.isEmpty && lineIndex <= 0) return null;
      return PlayLineMemory(lineName: lineName, lineIndex: lineIndex);
    }
    return null;
  }

  Future<void> saveMemory(
    VideoSource source,
    int vodId, {
    required String lineName,
    required int lineIndex,
  }) async {
    await init();
    await Hive.box(_boxName).put(keyOf(source, vodId), <String, dynamic>{
      'lineName': lineName.trim(),
      'lineIndex': lineIndex,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> clear(VideoSource source, int vodId) async {
    await init();
    await Hive.box(_boxName).delete(keyOf(source, vodId));
  }
}

class PlayLineMemory {
  const PlayLineMemory({required this.lineName, required this.lineIndex});

  final String lineName;
  final int lineIndex;
}
