import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/quiz_vision_candidate.dart';

/// AI 读屏命中候选的本地留档仓库。
///
/// 用户 2026-09-13 拍板：「A 档不提交，保留该题的截图及 ai 识别的题目信息，
/// 后面我再手动补充」。
///
/// 因此这里做两件事：
///   1. 把**读屏截图**落盘到 documents/vision_candidates/（sha256 命名，幂等）
///   2. 把**识别信息**（题干/选项/答案/置信度）以 JSON 存进 SharedPreferences
///
/// 无论该题最终有没有被上报，留档都在——这是 A 档的核心。
class QuizVisionCandidateStore {
  QuizVisionCandidateStore._();

  static const _prefsKey = 'quiz_vision_candidates_v1';
  static const _dirName = 'vision_candidates';

  /// 留档容量上限：避免长期使用把设备存满。超出时丢弃最旧的。
  /// 调大 → 保留更多历史（占空间）；调小 → 更省空间（易丢线索）。
  static const int maxKept = 200;

  /// 保存读屏截图，返回落盘路径。sha256 命名 → 同一张图重复保存幂等。
  static Future<String?> persistScreenshot(Uint8List bytes) async {
    if (bytes.isEmpty) return null;
    final digest = sha256.convert(bytes).toString();
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _dirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File(p.join(dir.path, '$digest.png'));
    if (!await file.exists()) await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<List<QuizVisionCandidate>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => QuizVisionCandidate.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: true);
    } catch (_) {
      // 损坏数据不应让功能不可用：当作空队列。
      return const [];
    }
  }

  static Future<void> saveAll(List<QuizVisionCandidate> items) async {
    final prefs = await SharedPreferences.getInstance();
    final kept = items.length > maxKept
        ? items.sublist(items.length - maxKept)
        : items;
    await prefs.setString(
      _prefsKey,
      jsonEncode(kept.map((e) => e.toJson()).toList()),
    );
  }

  /// 追加一条留档；同一题干+答案已存在时不重复追加（避免答同一题刷屏）。
  static Future<List<QuizVisionCandidate>> add(
    QuizVisionCandidate candidate,
  ) async {
    final all = await loadAll();
    final dup = all.any(
      (e) =>
          e.stem.trim() == candidate.stem.trim() &&
          e.answer.trim() == candidate.answer.trim(),
    );
    if (!dup) {
      all.add(candidate);
      await saveAll(all);
    }
    return all;
  }

  static Future<List<QuizVisionCandidate>> removeById(String id) async {
    final all = await loadAll();
    all.removeWhere((e) => e.id == id);
    await saveAll(all);
    return all;
  }

  static Future<List<QuizVisionCandidate>> clear() async {
    await saveAll(const []);
    return const [];
  }
}
