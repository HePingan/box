import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/data/quiz_cloud_push.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:box/features/quiz_plugin/data/quiz_cloud_sync.dart';

void main() {
  group('云端对账图片指纹 — QuizSubmissionReconciler', () {
    test('同文同选项不同图片指纹：decide 不会错误关联不同图片版本', () {
      // 本地有两道同题干同选项但图片不同的待审核题
      final locals = [
        QuizBankItem(
          id: 'local-a',
          question: '以下哪项是正确的？',
          type: QuizQuestionType.singleChoice,
          options: const ['选项A', '选项B', '选项C', '选项D'],
          correctAnswer: 'A',
          imageSha256: 'aaaaaa',
          imagePerceptualHash: 'ffff0000ffff0000',
          syncStatus: QuizSyncStatus.pendingReview,
          remoteSubmissionId: 'remote-a',
        ),
        QuizBankItem(
          id: 'local-b',
          question: '以下哪项是正确的？',
          type: QuizQuestionType.singleChoice,
          options: const ['选项A', '选项B', '选项C', '选项D'],
          correctAnswer: 'A',
          imageSha256: 'bbbbbb',
          imagePerceptualHash: '0000ffff0000ffff',
          syncStatus: QuizSyncStatus.pendingReview,
          remoteSubmissionId: 'remote-b',
        ),
      ];

      // 云端有两条对应的投稿（均已审核通过）
      final remotes = [
        QuizCloudSubmission(
          id: 'remote-a',
          status: 'approved',
          question: '以下哪项是正确的？',
          options: const ['选项A', '选项B', '选项C', '选项D'],
          imageSha256: 'aaaaaa',
          imagePerceptualHash: 'ffff0000ffff0000',
        ),
        QuizCloudSubmission(
          id: 'remote-b',
          status: 'approved',
          question: '以下哪项是正确的？',
          options: const ['选项A', '选项B', '选项C', '选项D'],
          imageSha256: 'bbbbbb',
          imagePerceptualHash: '0000ffff0000ffff',
        ),
      ];

      final decisions = QuizSubmissionReconciler.decide(
        locals: locals,
        remotes: remotes,
      );

      // 应有两条决策：local-a 关联 remote-a，local-b 关联 remote-b
      expect(decisions.length, equals(2));
      final decisionA = decisions.firstWhere((d) => d.localId == 'local-a');
      final decisionB = decisions.firstWhere((d) => d.localId == 'local-b');
      expect(decisionA.remoteSubmissionId, equals('remote-a'));
      expect(decisionB.remoteSubmissionId, equals('remote-b'));
    });

    test('同文同选项同图片指纹：decide 正确关联同一图片版本', () {
      final locals = [
        QuizBankItem(
          id: 'local-1',
          question: '以下哪项是正确的？',
          type: QuizQuestionType.singleChoice,
          options: const ['选项A', '选项B', '选项C', '选项D'],
          correctAnswer: 'A',
          imageSha256: 'aaaaaa',
          imagePerceptualHash: 'ffff0000ffff0000',
          syncStatus: QuizSyncStatus.pendingReview,
        ),
      ];

      final remotes = [
        QuizCloudSubmission(
          id: 'remote-same',
          status: 'approved',
          question: '以下哪项是正确的？',
          options: const ['选项A', '选项B', '选项C', '选项D'],
          imageSha256: 'aaaaaa',
          imagePerceptualHash: 'ffff0000ffff0000',
        ),
      ];

      final decisions = QuizSubmissionReconciler.decide(
        locals: locals,
        remotes: remotes,
      );

      expect(decisions.length, equals(1));
      expect(decisions.first.remoteSubmissionId, equals('remote-same'));
      expect(decisions.first.syncStatus, equals(QuizSyncStatus.published));
    });

    test('无图片指纹时回退到题干+选项指纹进行兜底关联', () {
      final locals = [
        QuizBankItem(
          id: 'local-noimage',
          question: '以下哪项是正确的？',
          type: QuizQuestionType.singleChoice,
          options: const ['选项A', '选项B', '选项C', '选项D'],
          correctAnswer: 'A',
          syncStatus: QuizSyncStatus.pendingReview,
        ),
      ];

      final remotes = [
        QuizCloudSubmission(
          id: 'remote-noimage',
          status: 'approved',
          question: '以下哪项是正确的？',
          options: const ['选项A', '选项B', '选项C', '选项D'],
          // 无 imageSha256/imagePerceptualHash
        ),
      ];

      final decisions = QuizSubmissionReconciler.decide(
        locals: locals,
        remotes: remotes,
      );

      // 兜底指纹匹配成功
      expect(decisions.length, equals(1));
      expect(decisions.first.remoteSubmissionId, equals('remote-noimage'));
    });

    test('云端同文同选项多版本时，仅单匹配才关联', () {
      final locals = [
        QuizBankItem(
          id: 'local-ambiguous',
          question: '以下哪项是正确的？',
          type: QuizQuestionType.singleChoice,
          options: const ['选项A', '选项B', '选项C', '选项D'],
          correctAnswer: 'A',
          syncStatus: QuizSyncStatus.pendingReview,
          // 无图片指纹，使用兜底文本指纹
        ),
      ];

      final remotes = [
        QuizCloudSubmission(
          id: 'remote-v1',
          status: 'approved',
          question: '以下哪项是正确的？',
          options: const ['选项A', '选项B', '选项C', '选项D'],
          imageSha256: 'version1',
          imagePerceptualHash: 'hash1',
        ),
        QuizCloudSubmission(
          id: 'remote-v2',
          status: 'approved',
          question: '以下哪项是正确的？',
          options: const ['选项A', '选项B', '选项C', '选项D'],
          imageSha256: 'version2',
          imagePerceptualHash: 'hash2',
        ),
      ];

      final decisions = QuizSubmissionReconciler.decide(
        locals: locals,
        remotes: remotes,
      );

      // 兜底指纹命中多个版本，不关联（防止错误覆盖）
      expect(decisions.length, equals(0));
    });

    test('QuizCloudSubmission.fromJson 正确解析图片指纹字段', () {
      final json = <String, dynamic>{
        'id': 'remote-123',
        'status': 'approved',
        'question': {
          'question': '以下哪项是正确的？',
          'options': ['选项A', '选项B', '选项C', '选项D'],
          'imageSha256': 'aaaaaa',
          'imagePerceptualHash': 'ffff0000ffff0000',
        },
      };

      final submission = QuizCloudSubmission.fromJson(json);

      expect(submission.imageSha256, equals('aaaaaa'));
      expect(submission.imagePerceptualHash, equals('ffff0000ffff0000'));
      expect(submission.question, equals('以下哪项是正确的？'));
      expect(submission.options, equals(['选项A', '选项B', '选项C', '选项D']));
    });

    test('QuizCloudSubmission.fromJson 兼容顶层图片指纹字段', () {
      final json = <String, dynamic>{
        'id': 'remote-456',
        'status': 'pending',
        'imageSha256': 'bbbbbb',
        'imagePerceptualHash': '0000ffff0000ffff',
        'question': {
          'question': '以下哪项是正确的？',
          'options': ['选项A', '选项B', '选项C', '选项D'],
        },
      };

      final submission = QuizCloudSubmission.fromJson(json);

      expect(submission.imageSha256, equals('bbbbbb'));
      expect(submission.imagePerceptualHash, equals('0000ffff0000ffff'));
    });

    test('QuizCloudSubmission.fromJson 嵌套字段优先于顶层字段', () {
      final json = <String, dynamic>{
        'id': 'remote-789',
        'status': 'rejected',
        'imageSha256': 'top-level',
        'imagePerceptualHash': 'top-level-hash',
        'question': {
          'question': '以下哪项是正确的？',
          'options': ['选项A', '选项B'],
          'imageSha256': 'nested-sha',
          'imagePerceptualHash': 'nested-hash',
        },
      };

      final submission = QuizCloudSubmission.fromJson(json);

      // 嵌套字段优先
      expect(submission.imageSha256, equals('nested-sha'));
      expect(submission.imagePerceptualHash, equals('nested-hash'));
    });
  });
}
