import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:flutter_test/flutter_test.dart';

QuizBankItem _item({required String status, String origin = 'local'}) =>
    QuizBankItem(
      id: 'q1',
      question: '题干',
      type: QuizQuestionType.singleChoice,
      options: const ['甲', '乙'],
      correctAnswer: '甲',
      origin: origin,
      syncStatus: status,
    );

void main() {
  group('canPushToCloud gates repeated submissions', () {
    test('local-only drafts can be pushed', () {
      expect(_item(status: QuizSyncStatus.localOnly).canPushToCloud, isTrue);
    });

    test('rejected items can be revised and pushed again', () {
      expect(_item(status: QuizSyncStatus.rejected).canPushToCloud, isTrue);
    });

    test('pending review items cannot be pushed again', () {
      expect(
        _item(status: QuizSyncStatus.pendingReview).canPushToCloud,
        isFalse,
        reason: '审核中重复投稿会在服务端产生重复题',
      );
    });

    test('merged items cannot be pushed again', () {
      expect(
        _item(status: QuizSyncStatus.merged).canPushToCloud,
        isFalse,
        reason: '已合并的题再投稿等于重复提交',
      );
    });

    test('published items cannot be pushed again', () {
      expect(_item(status: QuizSyncStatus.published).canPushToCloud, isFalse);
    });

    test('cloud mirrors cannot be pushed back', () {
      expect(
        _item(status: QuizSyncStatus.localOnly, origin: 'cloud').canPushToCloud,
        isFalse,
      );
    });
  });
}
