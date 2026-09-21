import 'package:flutter_test/flutter_test.dart';

import '../tool/image_platform_quota_server.dart';

/// 「问题题标记说明」持久化回归测试（RED -> GREEN）。
///
/// 实测踩到的坑（本测试就是为它建的）：
///   服务端给标记题写了自定义说明（如「答案被车牌水印覆盖，需按图确认」），
///   写盘正常（`toJson` 有 issueReason 字段），但**服务重启后读回来变成空**，
///   于是残缺队列里所有标记题都退回默认文案「需按图确认答案」，分不出谁是谁。
///
///   根因：`QuizQuestion` 有三个反序列化入口
///     - `fromRequest`  （HTTP body）      —— 当时只修了这个
///     - `fromJson`     （磁盘加载）       —— **漏了，就是它**
///     - complete/bulk 分支的原地重建      —— 也要显式带上
///   只修 fromRequest 时，内存里对、一落盘一重启就丢。
///
/// 契约：
///   1) toJson 必须写出 issueReason（哪怕为空也要在，供后续 fromJson 读）
///   2) fromJson 必须读回 issueReason  —— 本次修的核心
///   3) 两者往返必须无损
void main() {
  group('问题题标记说明 issueReason 持久化', () {
    QuizQuestion sample({
      String id = 'q_plate01',
      String status = 'incomplete',
      String issueReason = '答案被车牌水印覆盖，需按图确认',
    }) {
      return QuizQuestion(
        id: id,
        identityKey: 'k_$id',
        question: '图中这辆上路学习驾驶的自学直考车有什么违法行为？',
        type: 'single_choice',
        options: const ['鄂K·R1234', '未按规定悬挂号牌', '未随车携带证件', '非法改装'],
        correctAnswer: '未按规定悬挂号牌',
        analysis: '速记口诀',
        category: '交通法规',
        source: 'import',
        status: status,
        revision: 8,
        createdAt: DateTime.parse('2026-09-01T10:00:00Z'),
        updatedAt: DateTime.parse('2026-09-13T10:00:00Z'),
        image: '',
        issueReason: issueReason,
      );
    }

    test('toJson 写出 issueReason', () {
      final j = sample().toJson();
      expect(j['issueReason'], '答案被车牌水印覆盖，需按图确认');
    });

    test('fromJson 读回 issueReason（此前漏读 → 重启后退回默认文案）', () {
      final j = sample().toJson();
      final back = QuizQuestion.fromJson(j);
      expect(back.issueReason, '答案被车牌水印覆盖，需按图确认',
          reason: 'fromJson 不读 issueReason 时，服务重启后标记说明会全部丢失');
    });

    test('toJson -> fromJson 往返无损', () {
      final src = sample();
      final back = QuizQuestion.fromJson(src.toJson());
      expect(back.id, src.id);
      expect(back.status, 'incomplete');
      expect(back.issueReason, src.issueReason);
      expect(back.correctAnswer, src.correctAnswer);
      expect(back.revision, src.revision);
    });

    test('旧数据无 issueReason 字段时不崩，回退为空串', () {
      final j = sample().toJson()..remove('issueReason');
      final back = QuizQuestion.fromJson(j);
      expect(back.issueReason, '');
    });

    test('未标记的普通题 issueReason 为空', () {
      final q = sample(status: 'published', issueReason: '');
      expect(QuizQuestion.fromJson(q.toJson()).issueReason, '');
    });
  });
}
