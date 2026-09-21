import 'package:box/features/quiz_plugin/data/quiz_cloud_pull.dart';
import 'package:box/features/quiz_plugin/data/quiz_cloud_sync.dart';
import 'package:flutter_test/flutter_test.dart';

QuizCloudPullResult _result({
  required bool reachedPageLimit,
  QuizBankCoverage? coverage,
  int localCount = 9999,
  int inserted = 9999,
}) => QuizCloudPullResult(
  serverUrl: 'https://example.com',
  categories: const ['驾驶理论题库-20260719'],
  inserted: inserted,
  cloudDeletes: 0,
  pages: 100,
  catalogCount: 1,
  localCount: localCount,
  reachedPageLimit: reachedPageLimit,
  coverage: coverage,
);

void main() {
  group('达页数上限不得静默截断（题库过万）', () {
    test('reachedPageLimit=true 时 summaryText 明确标注「本次未拉完」', () {
      final r = _result(reachedPageLimit: true);
      expect(r.summaryText, contains('未拉完'));
      expect(r.summaryText, contains('上限'));
      // 旧文案把「已达上限」说得像成功，须明确是「还需继续拉」。
      expect(r.summaryText, isNot(contains('安全上限，请继续更新')));
    });

    test('reachedPageLimit=true 时 isPartial 为真，供 UI 常驻提示', () {
      expect(_result(reachedPageLimit: true).isPartial, isTrue);
      expect(_result(reachedPageLimit: false).isPartial, isFalse);
    });

    test('覆盖率不完整时也是 isPartial', () {
      final coverage = QuizBankCoverage.evaluate(
        localCount: 100,
        catalogs: const [
          QuizCloudCatalog(id: 'a', name: 'a', count: 500),
        ],
      );
      final r = _result(
        reachedPageLimit: false,
        coverage: coverage,
        localCount: 100,
        inserted: 100,
      );
      expect(r.isPartial, isTrue);
    });

    test('正常同步（无上限、覆盖率完整）isPartial 为假', () {
      final coverage = QuizBankCoverage.evaluate(
        localCount: 500,
        catalogs: const [
          QuizCloudCatalog(id: 'a', name: 'a', count: 500),
        ],
      );
      final r = _result(
        reachedPageLimit: false,
        coverage: coverage,
        localCount: 500,
        inserted: 500,
      );
      expect(r.isPartial, isFalse);
      expect(r.summaryText, isNot(contains('未拉完')));
    });
  });
}
