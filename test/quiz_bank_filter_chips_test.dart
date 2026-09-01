import 'package:box/features/admin/domain/quiz_bank_filter.dart';
import 'package:flutter_test/flutter_test.dart';

/// 首屏筛选行的行为约束：
/// 「筛选 · N」角标、生效条件 chip 可逐个叉掉、搜索算一个条件、一键清除。
/// 这些是把三行平铺 chip 收进底部弹层后，用户判断「列表是否被过滤」的唯一线索，
/// 所以计数和清除必须准。
void main() {
  group('筛选按钮角标计数', () {
    test('无条件时角标为 0', () {
      expect(const QuizBankFilter().activeCount, 0);
    });

    test('状态/图片/题型/搜索各算一个条件', () {
      const filter = QuizBankFilter(
        status: QuizStatusFilter.pending,
        image: QuizImageFilter.withImage,
        type: QuizTypeFilter.judge,
        query: '安全',
      );
      expect(filter.activeCount, 4);
    });

    test('搜索词只有空白时不计入，避免角标虚高', () {
      const filter = QuizBankFilter(query: '   ');
      expect(filter.activeCount, 0);
      expect(filter.activeLabels, isEmpty);
    });
  });

  group('生效条件 chip', () {
    test('顺序固定为 状态 → 图片 → 题型 → 搜索', () {
      const filter = QuizBankFilter(
        status: QuizStatusFilter.approved,
        image: QuizImageFilter.withoutImage,
        type: QuizTypeFilter.multi,
        query: '电流',
      );
      expect(filter.activeLabels.map((l) => l.dimension).toList(), [
        QuizFilterDimension.status,
        QuizFilterDimension.image,
        QuizFilterDimension.type,
        QuizFilterDimension.query,
      ]);
    });

    test('chip 文案取枚举 label，搜索带前缀且去空白', () {
      const filter = QuizBankFilter(
        image: QuizImageFilter.withImage,
        query: '  欧姆定律 ',
      );
      expect(filter.activeLabels.map((l) => l.text).toList(), [
        '有图',
        '搜索：欧姆定律',
      ]);
    });

    test('叉掉图片维度只清图片，其余条件留着', () {
      const filter = QuizBankFilter(
        status: QuizStatusFilter.pending,
        image: QuizImageFilter.withImage,
        type: QuizTypeFilter.single,
      );
      final next = filter.without(QuizFilterDimension.image);
      expect(next.image, QuizImageFilter.any);
      expect(next.status, QuizStatusFilter.pending);
      expect(next.type, QuizTypeFilter.single);
      expect(next.activeCount, 2);
    });

    test('叉掉搜索维度等于清空搜索词', () {
      const filter = QuizBankFilter(
        query: '电压',
        type: QuizTypeFilter.judge,
      );
      final next = filter.without(QuizFilterDimension.query);
      expect(next.query, isEmpty);
      expect(next.type, QuizTypeFilter.judge);
    });

    test('逐个叉完后回到无条件状态', () {
      var filter = const QuizBankFilter(
        status: QuizStatusFilter.rejected,
        image: QuizImageFilter.withoutImage,
        type: QuizTypeFilter.sort,
        query: '排序',
      );
      for (final dimension in QuizFilterDimension.values) {
        filter = filter.without(dimension);
      }
      expect(filter.activeCount, 0);
      expect(filter.isActive, isFalse);
    });
  });

  group('一键清除', () {
    test('clearAll 抹掉全部四个维度', () {
      const filter = QuizBankFilter(
        status: QuizStatusFilter.pending,
        image: QuizImageFilter.withImage,
        type: QuizTypeFilter.multi,
        query: '关键词',
      );
      expect(filter.clearAll().activeCount, 0);
    });
  });

  group('搜索框收起态与筛选状态解耦', () {
    test('弹层选的条件与搜索词可以叠加，copyWith 不互相覆盖', () {
      const base = QuizBankFilter(
        status: QuizStatusFilter.pending,
        type: QuizTypeFilter.judge,
      );
      // 首屏把输入框文字并进 filter：copyWith(query: ...) 不能丢掉弹层选的项
      final withQuery = base.copyWith(query: '继电器');
      expect(withQuery.status, QuizStatusFilter.pending);
      expect(withQuery.type, QuizTypeFilter.judge);
      expect(withQuery.query, '继电器');
      expect(withQuery.activeCount, 3);
    });
  });
}
