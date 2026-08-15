import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/account/domain/personal_center_models.dart';

void main() {
  group('PersonalUsageRecord', () {
    test('parses a real server usage record', () {
      final record = PersonalUsageRecord.fromJson({
        'createdAt': '2026-06-14T13:01:15.484282',
        'userId': 'u_admin',
        'username': 'admin',
        'model': 'gpt-image-2',
        'cost': 1,
        'success': true,
        'statusCode': 200,
        'errorPreview': '',
      });

      expect(record.model, 'gpt-image-2');
      expect(record.modelLabel, 'gpt-image-2');
      expect(record.cost, 1);
      expect(record.success, isTrue);
      expect(record.statusCode, 200);
      expect(record.createdAt, isNotNull);
      expect(record.timeLabel, contains('2026-06-14'));
    });

    test('falls back gracefully on missing fields', () {
      final record = PersonalUsageRecord.fromJson({});

      expect(record.model, '');
      expect(record.modelLabel, '未知模型');
      expect(record.cost, 0);
      expect(record.success, isFalse);
      expect(record.statusCode, isNull);
      expect(record.createdAt, isNull);
      expect(record.timeLabel, '时间未知');
    });

    test('keeps the error preview for failed generations', () {
      final record = PersonalUsageRecord.fromJson({
        'createdAt': '2026-08-15T09:24:30.614464',
        'model': 'gpt-image-2',
        'cost': 1,
        'success': false,
        'statusCode': 500,
        'errorPreview': 'upstream timeout',
      });

      expect(record.success, isFalse);
      expect(record.errorPreview, 'upstream timeout');
      expect(record.statusCode, 500);
    });
  });

  group('PersonalQuotaSummary truncation', () {
    test('total reflects all matching records, returned only this page', () {
      // 与服务端修复后的真实响应一致：total=54, returned=5。
      final summary = PersonalQuotaSummary.fromJson({
        'transactions': List.generate(
          5,
          (i) => {
            'createdAt': '2026-08-1${i + 1}T10:00:00.000',
            'model': 'gpt-image-2',
            'cost': 1,
            'success': true,
            'statusCode': 200,
          },
        ),
        'summary': {
          'total': 54,
          'returned': 5,
          'totalCost': 61,
          'totalSuccess': 42,
          'totalFailed': 12,
        },
      });

      expect(summary.total, 54);
      expect(summary.returned, 5);
      expect(summary.transactions.length, 5);
      expect(summary.totalCost, 61);
      expect(summary.totalSuccess, 42);
      expect(summary.totalFailed, 12);
      expect(summary.truncated, isTrue);
      expect(summary.transactions.first, isA<PersonalUsageRecord>());
    });

    test('legacy response without returned falls back to record count', () {
      final summary = PersonalQuotaSummary.fromJson({
        'transactions': [
          {'model': 'gpt-image-2', 'cost': 1, 'success': true},
        ],
        'summary': {
          'total': 1,
          'totalCost': 1,
          'totalSuccess': 1,
          'totalFailed': 0,
        },
      });

      expect(summary.returned, 1);
      expect(summary.truncated, isFalse);
    });

    test('handles an empty transaction list', () {
      final summary = PersonalQuotaSummary.fromJson({
        'transactions': <dynamic>[],
        'summary': {
          'total': 0,
          'returned': 0,
          'totalCost': 0,
          'totalSuccess': 0,
          'totalFailed': 0,
        },
      });

      expect(summary.transactions, isEmpty);
      expect(summary.truncated, isFalse);
    });
  });

  group('PersonalUser nickname', () {
    test('reads nickname from the server payload', () {
      final user = PersonalUser.fromJson({
        'id': 'u_admin',
        'username': 'admin',
        'nickname': '管理员小号',
        'role': 'admin',
        'status': 'normal',
        'createdAt': '2026-06-14T11:52:00.807219',
        'lastLoginAt': '2026-08-15T09:24:30.614464',
      });

      expect(user.nickname, '管理员小号');
      expect(user.displayName, '管理员小号');
    });

    test('falls back to username when nickname is absent', () {
      final user = PersonalUser.fromJson({
        'id': 'u_1',
        'username': 'tester',
        'role': 'user',
        'status': 'normal',
      });

      expect(user.nickname, 'tester');
      expect(user.displayName, 'tester');
    });

    test('copyWith preserves timestamps while updating the nickname', () {
      final user = PersonalUser.fromJson({
        'id': 'u_1',
        'username': 'tester',
        'nickname': 'old',
        'role': 'user',
        'status': 'normal',
        'createdAt': '2026-06-14T11:52:00.807219',
        'lastLoginAt': '2026-08-15T09:24:30.614464',
      });

      final updated = user.copyWith(nickname: 'new');

      expect(updated.nickname, 'new');
      expect(updated.id, 'u_1');
      expect(updated.username, 'tester');
      expect(updated.createdAt, user.createdAt);
      expect(updated.lastLoginAt, user.lastLoginAt);
    });
  });
}
