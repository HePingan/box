import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:flutter_test/flutter_test.dart';

QuizBankItem _item(String status) => QuizBankItem(
  id: 'q1',
  question: '本地已投稿的题',
  type: QuizQuestionType.singleChoice,
  options: const ['甲', '乙'],
  correctAnswer: '甲',
  origin: 'local',
  syncStatus: status,
  remoteSubmissionId: 'submission-1',
  lastSubmitError: '历史错误',
);

void main() {
  group('local quiz revisions', () {
    test('editing a pending submission makes it a fresh pushable revision', () {
      final revised = _item(QuizSyncStatus.pendingReview).asLocalRevision();

      expect(revised.syncStatus, QuizSyncStatus.localOnly);
      expect(revised.remoteSubmissionId, isNull);
      expect(revised.lastSubmitError, isNull);
      expect(revised.isUnpushedLocal, isTrue);
      expect(revised.canPushToCloud, isTrue);
    });

    test('editing an already published local item also becomes unpushed', () {
      final revised = _item(QuizSyncStatus.published).asLocalRevision();

      expect(revised.syncStatus, QuizSyncStatus.localOnly);
      expect(revised.isUnpushedLocal, isTrue);
      expect(revised.canPushToCloud, isTrue);
    });

    test(
      'replacing only the question image makes a fresh pushable revision',
      () {
        final revised = _item(QuizSyncStatus.pendingReview).withQuestionImage(
          imageUrl: '/app/documents/quiz_question_images/new.png',
          imageSha256: 'a' * 64,
          imagePerceptualHash: '0123456789abcdef',
        );

        expect(revised.question, '本地已投稿的题');
        expect(revised.options, const ['甲', '乙']);
        expect(revised.imageUrl, '/app/documents/quiz_question_images/new.png');
        expect(revised.imageSha256, 'a' * 64);
        expect(revised.imagePerceptualHash, '0123456789abcdef');
        expect(revised.syncStatus, QuizSyncStatus.localOnly);
        expect(revised.remoteSubmissionId, isNull);
        expect(revised.lastSubmitError, isNull);
        expect(revised.isUnpushedLocal, isTrue);
        expect(revised.canPushToCloud, isTrue);
      },
    );

    test(
      'a local revision copied from a cloud mirror remains visible as local',
      () {
        const revised = QuizBankItem(
          id: 'cloud-copy',
          question: '云端题的本地修改',
          type: QuizQuestionType.singleChoice,
          options: ['甲', '乙'],
          correctAnswer: '甲',
          origin: 'local',
          source: '云端题库（本地修改）',
          syncStatus: QuizSyncStatus.localOnly,
        );

        expect(revised.isCloud, isFalse);
        expect(revised.isUnpushedLocal, isTrue);
        expect(revised.canPushToCloud, isTrue);
      },
    );

    test('round-tripping a local cloud-copy keeps it unpushed', () {
      final restored = QuizBankItem.fromJson({
        'id': 'cloud-copy',
        'question': '云端题的本地修改',
        'type': 'single_choice',
        'options': ['甲', '乙'],
        'correctAnswer': '甲',
        'origin': 'local',
        'source': '云端题库（本地修改）',
        'syncStatus': QuizSyncStatus.localOnly,
      });

      expect(restored.isCloud, isFalse);
      expect(restored.isUnpushedLocal, isTrue);
      expect(restored.canPushToCloud, isTrue);
    });
  });
}
