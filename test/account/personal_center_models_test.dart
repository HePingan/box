import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/account/domain/personal_center_models.dart';

void main() {
  group('PersonalQuota', () {
    test('parses the server overview quota response', () {
      final quota = PersonalQuota.fromJson({
        'remaining': 101,
        'dailyLimit': 20,
        'usedToday': 48,
        'totalLimit': 20,
        'status': 'normal',
        'message': '平台额度可用',
      });

      expect(quota.remaining, 101);
      expect(quota.dailyLimit, 20);
      expect(quota.usedToday, 48);
      expect(quota.totalLimit, 20);
      expect(quota.status, 'normal');
      expect(quota.message, '平台额度可用');
      expect(quota.progress, 1.0); // used >= totalLimit
    });

    test('parses legacy quota response aliases', () {
      final quota = PersonalQuota.fromJson({
        'remainingQuota': 72,
        'dailyQuota': 100,
        'dailyUsed': 28,
        'status': 'normal',
      });

      expect(quota.remaining, 72);
      expect(quota.dailyLimit, 100);
      expect(quota.usedToday, 28);
    });
  });

  group('PersonalQuizItem', () {
    test('maps server submission response', () {
      final item = PersonalQuizItem.fromJson({
        'id': 'qs_BiERXieh080a',
        'question': {
          'id': 'qs_BiERXieh080a',
          'question': '造成致人轻微伤或者财产损失的交通事故后逃逸？',
          'type': 'single_choice',
          'options': ['12分', '2分', '3分', '6分'],
          'correctAnswer': '6分',
          'analysis': '速记口诀',
          'source': 'OCR录入',
          'status': 'pending',
          'revision': 1,
          'createdAt': '2026-08-10T20:47:34.517386',
          'updatedAt': '2026-08-10T20:47:34.517386',
        },
        'status': 'approved',
        'submittedAt': '2026-08-10T20:47:34.517519',
        'reviewNote': '',
        'linkedQuestionId': 'q_yseETp0r6b5x',
        'reviewedAt': '2026-08-10T20:47:51.997944',
      });

      expect(item.id, 'qs_BiERXieh080a');
      expect(item.title, '造成致人轻微伤或者财产损失的交通事故后逃逸？');
      expect(item.status, 'approved');
      expect(item.statusLabel, '已发布');
      expect(item.category, '');
      expect(item.reviewNote, '');
      expect(item.linkedQuestionId, 'q_yseETp0r6b5x');
      expect(item.createdAt, isNotNull);
    });

    test('handles missing nested question', () {
      final item = PersonalQuizItem.fromJson({
        'id': 'qs_test',
        'question': '简单题干',
        'status': 'pending',
      });

      expect(item.id, 'qs_test');
      expect(item.title, '简单题干');
      expect(item.statusLabel, '审核中');
    });
  });

  group('PersonalOverview', () {
    test('parses server overview response', () {
      final overview = PersonalOverview.fromJson({
        'user': {
          'id': 'u_admin',
          'username': 'admin',
          'role': 'admin',
          'status': 'normal',
          'createdAt': '2026-06-14T11:52:00.807219',
          'lastLoginAt': '2026-08-15T09:24:30.614464',
        },
        'quota': {
          'remaining': 101,
          'dailyLimit': 20,
          'usedToday': 48,
          'totalLimit': 20,
          'status': 'normal',
          'message': '平台额度可用',
        },
        'stats': {
          'todayRequests': 0,
          'todaySuccess': 0,
          'todayCost': 0,
          'mySubmissions': 41,
          'myPendingSubmissions': 0,
          'myMergedSubmissions': 5,
          'myApprovedSubmissions': 36,
          'publishedQuestions': 1970,
        },
      });

      expect(overview.user.id, 'u_admin');
      expect(overview.user.username, 'admin');
      expect(overview.user.role, 'admin');
      expect(overview.quota.remaining, 101);
      expect(overview.quota.usedToday, 48);
      expect(overview.stats.todayRequests, 0);
      expect(overview.stats.mySubmissions, 41);
      expect(overview.stats.publishedQuestions, 1970);
    });
  });

  group('PersonalQuizPage', () {
    test('parses quiz list response', () {
      final page = PersonalQuizPage.fromJson({
        'questions': [
          {
            'id': 'qs_1',
            'question': {'question': '题1', 'category': '科目一'},
            'status': 'approved',
            'submittedAt': '2026-08-10T20:00:00Z',
          },
          {
            'id': 'qs_2',
            'question': {'question': '题2', 'category': '科目四'},
            'status': 'pending',
            'submittedAt': '2026-08-11T20:00:00Z',
          },
        ],
        'total': 2,
        'limit': 50,
        'hasMore': false,
      });

      expect(page.questions.length, 2);
      expect(page.total, 2);
      expect(page.hasMore, false);
      expect(page.questions[0].title, '题1');
      expect(page.questions[0].statusLabel, '已发布');
      expect(page.questions[1].statusLabel, '审核中');
    });
  });

  group('PersonalQuotaSummary', () {
    test('parses transactions response', () {
      final summary = PersonalQuotaSummary.fromJson({
        'transactions': [
          {
            'createdAt': '2026-06-14T13:01:15.484282',
            'userId': 'u_admin',
            'model': 'gpt-image-2',
            'cost': 1,
            'success': true,
            'statusCode': 200,
          },
        ],
        'summary': {
          'total': 1,
          'totalCost': 1,
          'totalSuccess': 1,
          'totalFailed': 0,
        },
      });

      expect(summary.total, 1);
      expect(summary.totalCost, 1);
      expect(summary.totalSuccess, 1);
      expect(summary.totalFailed, 0);
      expect(summary.transactions.length, 1);
    });
  });

  group('PersonalActivityDay', () {
    test('parses activity day', () {
      final day = PersonalActivityDay.fromJson({
        'date': '2026-08-15',
        'requests': 5,
        'success': 4,
        'cost': 5,
      });

      expect(day.date, '2026-08-15');
      expect(day.requests, 5);
      expect(day.success, 4);
      expect(day.cost, 5);
    });
  });
}
