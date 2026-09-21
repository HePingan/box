import 'package:box/features/quiz_plugin/data/quiz_cloud_pull.dart';
import 'package:box/features/quiz_plugin/data/quiz_cloud_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('题库覆盖率校验（同步中断可诊断）', () {
    test('本地题数少于云端目录数时判定为不完整，并给出缺口', () {
      final coverage = QuizBankCoverage.evaluate(
        localCount: 1500,
        catalogs: const [
          QuizCloudCatalog(id: '驾驶理论题库-20260719', name: '驾驶理论题库-20260719', count: 3509),
        ],
      );

      expect(coverage.isComplete, isFalse);
      expect(coverage.expectedCount, 3509);
      expect(coverage.missingCount, 2009);
      expect(coverage.summaryText, contains('1500'));
      expect(coverage.summaryText, contains('3509'));
    });

    test('本地题数达标时判定为完整', () {
      final coverage = QuizBankCoverage.evaluate(
        localCount: 3509,
        catalogs: const [
          QuizCloudCatalog(id: '驾驶理论题库-20260719', name: '驾驶理论题库-20260719', count: 3509),
        ],
      );

      expect(coverage.isComplete, isTrue);
      expect(coverage.missingCount, 0);
    });

    test('本地多于云端（含本地自建题）不误报缺失', () {
      final coverage = QuizBankCoverage.evaluate(
        localCount: 3600,
        catalogs: const [
          QuizCloudCatalog(id: 'x', name: 'x', count: 3509),
        ],
      );

      expect(coverage.isComplete, isTrue);
      expect(coverage.missingCount, 0);
    });

    test('目录为空时不判定缺失（未登录/离线不打扰用户）', () {
      final coverage = QuizBankCoverage.evaluate(
        localCount: 0,
        catalogs: const [],
      );

      expect(coverage.isComplete, isTrue);
      expect(coverage.expectedCount, 0);
    });

    test('多目录取总数为期望值', () {
      final coverage = QuizBankCoverage.evaluate(
        localCount: 100,
        catalogs: const [
          QuizCloudCatalog(id: 'a', name: 'a', count: 60),
          QuizCloudCatalog(id: 'b', name: 'b', count: 90),
        ],
      );

      expect(coverage.expectedCount, 150);
      expect(coverage.missingCount, 50);
      expect(coverage.isComplete, isFalse);
    });

    test('同步结果 summaryText 在不完整时暴露缺口，完整时不出缺口文案', () {
      final gap = QuizCloudPullResult(
        serverUrl: 'https://example.com',
        categories: const ['驾驶理论题库-20260719'],
        inserted: 0,
        cloudDeletes: 0,
        catalogCount: 1,
        localCount: 1500,
        coverage: QuizBankCoverage.evaluate(
          localCount: 1500,
          catalogs: const [
            QuizCloudCatalog(id: 'c', name: 'c', count: 3509),
          ],
        ),
      );
      expect(gap.summaryText, contains('缺 2009 题'));

      final full = QuizCloudPullResult(
        serverUrl: 'https://example.com',
        categories: const ['驾驶理论题库-20260719'],
        inserted: 0,
        cloudDeletes: 0,
        catalogCount: 1,
        localCount: 3509,
        coverage: QuizBankCoverage.evaluate(
          localCount: 3509,
          catalogs: const [
            QuizCloudCatalog(id: 'c', name: 'c', count: 3509),
          ],
        ),
      );
      expect(full.summaryText, isNot(contains('缺')));
      expect(full.summaryText, contains('本地 3509'));
    });
  });
}
