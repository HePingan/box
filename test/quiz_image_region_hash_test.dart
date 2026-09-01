import 'package:box/features/quiz_plugin/data/quiz_engine.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:box/features/quiz_plugin/domain/quiz_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// B1/B2 回归：题图区域专属 dHash（imageRegionHash）
///
/// 背景：旧实现只有 imagePerceptualHash（整题截图 dHash）。整块截图包含题干与
/// 选项文字，「同题干同选项、仅题图不同」的题之间 dHash 差异极小，区分度不足。
/// B1 引入 imageRegionHash：用户单独框选题图区域，只对该区域算 dHash，
/// 匹配时只与题库的 imageRegionHash 比对；旧整题 hash 仅保留为存量字段，
/// 不再跨区域参与题图消歧，避免把题干和选项文字误当成视觉证据。
void main() {
  QuizEngine engine() => QuizEngine(
    config: const QuizConfig(
      enabled: true,
      bankEnabled: true,
      autoSearch: false,
      allowExternalApi: false,
      bankMaxMatches: 1,
    ),
  );

  const question = '下图所示的电路属于哪种连接？';
  const options = ['串联', '并联', '混联', '无法判断'];

  group('B1 — imageRegionHash 持久化往返', () {
    test('JSON 往返保留 imageRegionHash，且与整题 hash 分开存储', () {
      const item = QuizBankItem(
        id: 'q1',
        question: question,
        type: QuizQuestionType.singleChoice,
        options: options,
        correctAnswer: '串联',
        imagePerceptualHash: '00112233445566ff',
        imageRegionHash: 'aabbccddeeff0011',
      );
      final back = QuizBankItem.fromJson(item.toJson());
      expect(back.imageRegionHash, equals('aabbccddeeff0011'));
      expect(back.imagePerceptualHash, equals('00112233445566ff'));
    });

    test('数据库映射往返保留 imageRegionHash', () {
      const item = QuizBankItem(
        id: 'q2',
        question: question,
        type: QuizQuestionType.singleChoice,
        options: options,
        correctAnswer: '串联',
        imageRegionHash: 'ffee0011ffee0011',
      );
      final back = QuizBankItem.fromDb(item.toDb());
      expect(back.imageRegionHash, equals('ffee0011ffee0011'));
    });

    test('copyWith 可独立更新 imageRegionHash', () {
      const item = QuizBankItem(
        id: 'q3',
        question: question,
        type: QuizQuestionType.singleChoice,
        options: options,
        correctAnswer: '串联',
        imageRegionHash: '1111111111111111',
      );
      final updated = item.copyWith(imageRegionHash: '2222222222222222');
      expect(updated.imageRegionHash, equals('2222222222222222'));
      expect(item.imageRegionHash, equals('1111111111111111'));
    });

    test('存量题（无 imageRegionHash）反序列化为 null，不抛异常', () {
      final legacy = <String, dynamic>{
        'id': 'legacy-1',
        'question': question,
        'type': 'singleChoice',
        'options': options,
        'correctAnswer': '串联',
        'imagePerceptualHash': '00112233445566ff',
      };
      final back = QuizBankItem.fromJson(legacy);
      expect(back.imageRegionHash, isNull);
      expect(back.imagePerceptualHash, equals('00112233445566ff'));
    });

    test('服务端 snake_case（image_region_hash）也能解析', () {
      final remote = <String, dynamic>{
        'id': 'remote-1',
        'question': question,
        'type': 'singleChoice',
        'options': options,
        'correctAnswer': '串联',
        'image_region_hash': 'abcdefabcdefabcd',
      };
      final back = QuizBankItem.fromJson(remote);
      expect(back.imageRegionHash, equals('abcdefabcdefabcd'));
    });
  });

  group('B1 — 题图区域 hash 优先参与匹配消歧', () {
    const probeRegionHash = 'ffffffff00000000';

    test('两变体均有 imageRegionHash 时，命中题图一致的那道', () async {
      QuizBankCache.instance.assign(const [
        QuizBankItem(
          id: 'variant-other',
          question: question,
          type: QuizQuestionType.singleChoice,
          options: options,
          correctAnswer: '并联',
          // 整块 hash 与另一变体仅差 1 bit（区分度不足）
          imagePerceptualHash: '0f0f0f0f0f0f0f0e',
          // 题图区域 hash 与探针完全相反
          imageRegionHash: '00000000ffffffff',
          source: 'test',
        ),
        QuizBankItem(
          id: 'variant-match',
          question: question,
          type: QuizQuestionType.singleChoice,
          options: options,
          correctAnswer: '串联',
          imagePerceptualHash: '0f0f0f0f0f0f0f0f',
          imageRegionHash: probeRegionHash,
          source: 'test',
        ),
      ]);

      final result = await engine().search(
        question,
        probeOptions: options,
        imagePerceptualHash: probeRegionHash,
      );

      expect(result.isSuccess, isTrue);
      expect(
        result.answers.single.correctAnswer,
        '串联',
        reason: '题图区域 hash 一致的候选应胜出',
      );
    });

    test('题库有 region hash 时不被误导性的整题 hash 干扰', () async {
      QuizBankCache.instance.assign(const [
        QuizBankItem(
          id: 'misleading',
          question: question,
          type: QuizQuestionType.singleChoice,
          options: options,
          correctAnswer: '并联',
          // 整块 hash 与探针完全一致（误导信号）
          imagePerceptualHash: probeRegionHash,
          // 但 region hash 与探针完全相反
          imageRegionHash: '00000000ffffffff',
          source: 'test',
        ),
        QuizBankItem(
          id: 'variant-match',
          question: question,
          type: QuizQuestionType.singleChoice,
          options: options,
          correctAnswer: '串联',
          imagePerceptualHash: '0f0f0f0f0f0f0f0f',
          imageRegionHash: probeRegionHash,
          source: 'test',
        ),
      ]);

      final result = await engine().search(
        question,
        probeOptions: options,
        imagePerceptualHash: probeRegionHash,
      );

      expect(result.isSuccess, isTrue);
      expect(
        result.answers.single.correctAnswer,
        '串联',
        reason: 'imageRegionHash 应优先于 imagePerceptualHash',
      );
    });

    test('题库侧无 imageRegionHash 时不得用旧整题 hash 自动选答案', () async {
      QuizBankCache.instance.assign(const [
        QuizBankItem(
          id: 'legacy-b',
          question: question,
          type: QuizQuestionType.singleChoice,
          options: options,
          correctAnswer: '并联',
          imagePerceptualHash: '00000000ffffffff',
          source: 'test',
        ),
        QuizBankItem(
          id: 'legacy-a',
          question: question,
          type: QuizQuestionType.singleChoice,
          options: options,
          correctAnswer: '串联',
          imagePerceptualHash: probeRegionHash,
          source: 'test',
        ),
      ]);

      final result = await engine().search(
        question,
        probeOptions: options,
        imagePerceptualHash: probeRegionHash,
      );

      expect(result.isSuccess, isTrue);
      expect(result.answers, hasLength(2));
      expect(
        result.answers.map((answer) => answer.correctAnswer).toSet(),
        containsAll(<String>{'串联', '并联'}),
      );
      expect(result.answers.first.imageMatchHint, contains('题库题图指纹缺失'));
    });

    test('只有整题 hash 的多候选不会误报为题图区域匹配不足', () async {
      QuizBankCache.instance.assign(const [
        QuizBankItem(
          id: 'legacy-other',
          question: question,
          type: QuizQuestionType.singleChoice,
          options: options,
          correctAnswer: '并联',
          imagePerceptualHash: '00000000ffffffff',
          source: 'test',
        ),
        QuizBankItem(
          id: 'legacy-same',
          question: question,
          type: QuizQuestionType.singleChoice,
          options: options,
          correctAnswer: '串联',
          imagePerceptualHash: probeRegionHash,
          source: 'test',
        ),
      ]);

      final result = await engine().search(
        question,
        probeOptions: options,
        imagePerceptualHash: probeRegionHash,
      );

      expect(result.isSuccess, isTrue);
      expect(result.answers.first.imageMatchHint, contains('题库题图指纹缺失'));
      expect(result.answers.first.imageMatchHint, isNot(contains('题图匹配不足')));
    });

    test('低绝对分即使最佳题图区域领先，也必须保留候选确认', () async {
      // 实机框选通常比题库参考图多出少量留白；低于可靠门槛的 dHash
      // 即使相对领先，也不能静默把排序第一条当正确答案。
      const looseFrameProbe = 'ffffffff00000000';
      QuizBankCache.instance.assign(const [
        QuizBankItem(
          id: 'screen-frame-match',
          question: question,
          type: QuizQuestionType.singleChoice,
          options: options,
          correctAnswer: '串联',
          // 与 probe 相距 19 bit，45/64，低于旧绝对门槛 48。
          imageRegionHash: 'ffffffffaaaa5557',
          source: 'test',
        ),
        QuizBankItem(
          id: 'screen-frame-other',
          question: question,
          type: QuizQuestionType.singleChoice,
          options: options,
          correctAnswer: '并联',
          // 32/64，和最佳候选相差 13，足以表示相对视觉证据。
          imageRegionHash: '00000000ffffffff',
          source: 'test',
        ),
      ]);

      final result = await engine().search(
        question,
        probeOptions: options,
        imagePerceptualHash: looseFrameProbe,
      );

      expect(result.isSuccess, isTrue);
      expect(result.answers, hasLength(2));
      expect(
        result.answers.map((answer) => answer.correctAnswer).toSet(),
        containsAll(<String>{'串联', '并联'}),
      );
      expect(result.answers.first.imageMatchHint, contains('候选答案'));
      expect(result.answers.first.imageMatchHint, contains('串联'));
      expect(result.answers.first.imageMatchHint, contains('并联'));
      expect(result.answers.first.imageMatchHint, isNot(contains('题图消歧已启用')));
    });

    test('低绝对分且未明显领先时保持题图匹配不足', () async {
      const looseFrameProbe = 'ffffffff00000000';
      QuizBankCache.instance.assign(const [
        QuizBankItem(
          id: 'screen-frame-close-a',
          question: question,
          type: QuizQuestionType.singleChoice,
          options: options,
          correctAnswer: '串联',
          imageRegionHash: 'ffffffffaaaa5557',
          source: 'test',
        ),
        QuizBankItem(
          id: 'screen-frame-close-b',
          question: question,
          type: QuizQuestionType.singleChoice,
          options: options,
          correctAnswer: '并联',
          // 与首名仅差 1 分，不能把噪声当成唯一答案。
          imageRegionHash: 'ffffffffaaaa555f',
          source: 'test',
        ),
      ]);

      final result = await engine().search(
        question,
        probeOptions: options,
        imagePerceptualHash: looseFrameProbe,
      );

      expect(result.isSuccess, isTrue);
      expect(result.answers.first.imageMatchHint, contains('题图匹配不足'));
      expect(result.answers.first.imageMatchHint, isNot(contains('题图消歧已启用')));
    });

    test('探针无 hash 时图片信号不参与，退回文字匹配且不崩溃', () async {
      QuizBankCache.instance.assign(const [
        QuizBankItem(
          id: 'variant-match',
          question: question,
          type: QuizQuestionType.singleChoice,
          options: options,
          correctAnswer: '串联',
          imageRegionHash: probeRegionHash,
          source: 'test',
        ),
        QuizBankItem(
          id: 'variant-other',
          question: question,
          type: QuizQuestionType.singleChoice,
          options: options,
          correctAnswer: '并联',
          imageRegionHash: '00000000ffffffff',
          source: 'test',
        ),
      ]);

      final result = await engine().search(question, probeOptions: options);
      expect(result.isSuccess, isTrue);
    });

    test('探针 hash 非法时安全降级，不因 region 比对抛异常', () async {
      QuizBankCache.instance.assign(const [
        QuizBankItem(
          id: 'variant-match',
          question: question,
          type: QuizQuestionType.singleChoice,
          options: options,
          correctAnswer: '串联',
          imageRegionHash: probeRegionHash,
          source: 'test',
        ),
      ]);

      final result = await engine().search(
        question,
        probeOptions: options,
        imagePerceptualHash: 'not-a-valid-dhash',
      );
      expect(result.isSuccess, isTrue);
    });
  });
}
