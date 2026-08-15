import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/account/domain/personal_center_models.dart';

void main() {
  group('PersonalPluginPage', () {
    test('parses the server /api/me/plugins response', () {
      final page = PersonalPluginPage.fromJson({
        'items': [
          {
            'id': 'sub_1',
            'pluginId': 'plg_quiz_ocr',
            'title': '题库 OCR 助手',
            'subtitle': '拍照识别题目并入库',
            'version': '1.2.0',
            'status': 'published',
            'permissions': ['camera', 'storage'],
            'tags': ['题库', 'OCR'],
            'reviewNote': '通过审核',
            'createdAt': '2026-08-10T20:00:00.000',
            'reviewedAt': '2026-08-11T09:30:00.000',
          },
          {
            'id': 'sub_2',
            'pluginId': 'plg_video',
            'name': '视频增强',
            'description': '倍速与后台播放',
            'status': 'pending_review',
          },
        ],
        'total': 5,
        'offset': 0,
        'limit': 20,
        'hasMore': true,
      });

      expect(page.items.length, 2);
      expect(page.total, 5);
      expect(page.offset, 0);
      expect(page.limit, 20);
      expect(page.hasMore, isTrue);

      final first = page.items.first;
      expect(first.id, 'sub_1');
      expect(first.pluginId, 'plg_quiz_ocr');
      expect(first.title, '题库 OCR 助手');
      expect(first.version, '1.2.0');
      expect(first.statusLabel, '已发布');
      expect(first.permissions, ['camera', 'storage']);
      expect(first.tags, ['题库', 'OCR']);
      expect(first.reviewNote, '通过审核');
      expect(first.createdAt, isNotNull);
      expect(first.reviewedAt, isNotNull);
    });

    test('falls back to name/description aliases', () {
      final page = PersonalPluginPage.fromJson({
        'items': [
          {
            'id': 'sub_2',
            'name': '视频增强',
            'description': '倍速与后台播放',
            'status': 'pending_review',
          },
        ],
        'total': 1,
        'limit': 20,
        'hasMore': false,
      });

      final item = page.items.single;
      expect(item.title, '视频增强');
      expect(item.subtitle, '倍速与后台播放');
      expect(item.statusLabel, '审核中');
      expect(item.permissions, isEmpty);
      expect(item.tags, isEmpty);
      expect(item.createdAt, isNull);
    });

    test('handles an empty payload without throwing', () {
      final page = PersonalPluginPage.fromJson(const {});

      expect(page.items, isEmpty);
      expect(page.total, 0);
      expect(page.offset, 0);
      expect(page.hasMore, isFalse);
    });

    test('accepts count as a total alias and string numbers', () {
      final page = PersonalPluginPage.fromJson({
        'items': const [],
        'count': '7',
        'offset': '20',
        'limit': '20',
        'hasMore': true,
      });

      expect(page.total, 7);
      expect(page.offset, 20);
      expect(page.limit, 20);
      expect(page.hasMore, isTrue);
    });

    test('maps every review status to a Chinese label', () {
      PersonalPluginItem itemWith(String status) =>
          PersonalPluginItem.fromJson({'id': 'x', 'status': status});

      expect(itemWith('published').statusLabel, '已发布');
      expect(itemWith('approved').statusLabel, '已发布');
      expect(itemWith('rejected').statusLabel, '已拒绝');
      expect(itemWith('yanked').statusLabel, '已下架');
      expect(itemWith('draft').statusLabel, '草稿');
      expect(itemWith('pending_review').statusLabel, '审核中');
      expect(itemWith('anything-else').statusLabel, '审核中');
    });

    test('defaults status to pending_review when absent', () {
      final item = PersonalPluginItem.fromJson(const {'id': 'sub_9'});

      expect(item.status, 'pending_review');
      expect(item.statusLabel, '审核中');
    });

    test('drops non-string permission entries safely', () {
      final item = PersonalPluginItem.fromJson({
        'id': 'sub_10',
        'permissions': ['camera', '', 'storage'],
        'tags': 'not-a-list',
      });

      expect(item.permissions, ['camera', 'storage']);
      expect(item.tags, isEmpty);
    });
  });

  group('PersonalQuizPage pagination', () {
    test('parses offset for the paginated quiz contract', () {
      final page = PersonalQuizPage.fromJson({
        'questions': [
          {
            'id': 'qs_1',
            'question': {'question': '题1'},
            'status': 'pending',
          },
        ],
        'total': 41,
        'offset': 20,
        'limit': 20,
        'hasMore': true,
      });

      expect(page.questions.length, 1);
      expect(page.total, 41);
      expect(page.offset, 20);
      expect(page.limit, 20);
      expect(page.hasMore, isTrue);
    });

    test('defaults offset to zero when the server omits it', () {
      final page = PersonalQuizPage.fromJson({
        'questions': const [],
        'total': 0,
        'limit': 20,
        'hasMore': false,
      });

      expect(page.offset, 0);
      expect(page.hasMore, isFalse);
    });
  });
}
