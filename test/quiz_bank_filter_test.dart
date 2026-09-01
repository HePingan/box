import 'package:box/features/admin/domain/quiz_bank_filter.dart';
import 'package:box/features/admin/domain/quiz_bank_models.dart';
import 'package:flutter_test/flutter_test.dart';

QuizBankQuestion q({
  String id = 'q',
  String question = '题干',
  List<String> options = const ['A选项', 'B选项', 'C选项', 'D选项'],
  String answer = 'A',
  String status = 'approved',
  String type = 'single_choice',
  String image = '',
  List<String> tags = const [],
  String category = '',
  String explanation = '',
}) => QuizBankQuestion(
  id: id,
  question: question,
  options: options,
  answer: answer,
  status: status,
  tags: tags,
  type: type,
  image: image,
  category: category,
  explanation: explanation,
);

void main() {
  group('有图/无图筛选', () {
    test('筛有图只留 image 非空的题', () {
      final items = [
        q(id: '1', image: 'https://cdn/a.png'),
        q(id: '2'),
        q(id: '3', image: '   '),
      ];
      const filter = QuizBankFilter(image: QuizImageFilter.withImage);
      expect(filter.apply(items).map((x) => x.id), ['1']);
    });

    test('筛无图时空白字符串算无图', () {
      final items = [
        q(id: '1', image: 'https://cdn/a.png'),
        q(id: '2'),
        q(id: '3', image: '   '),
      ];
      const filter = QuizBankFilter(image: QuizImageFilter.withoutImage);
      expect(filter.apply(items).map((x) => x.id), ['2', '3']);
    });

    test('统计有图数量供 UI 显示徽标', () {
      final counts = QuizBankFilter.imageCounts([
        q(id: '1', image: 'https://cdn/a.png'),
        q(id: '2'),
      ]);
      expect(counts[QuizImageFilter.withImage], 1);
      expect(counts[QuizImageFilter.withoutImage], 1);
      expect(counts[QuizImageFilter.any], 2);
    });

    test('相对路径题图带 base 时要算进有图', () {
      // 生产库里 image 全是 /api/quiz/images/xxx，不传 base 会被判成占位
      // → 弹层显示「有图 (0)」，和列表里实际显示的图对不上。
      final items = [
        q(id: '1', image: '/api/quiz/images/a.jpg'),
        q(id: '2', image: '/api/quiz/images/b.jpg'),
        q(id: '3'),
      ];
      final counts = QuizBankFilter.imageCounts(
        items,
        base: 'https://background.hpa888.top',
      );
      expect(counts[QuizImageFilter.withImage], 2);
      expect(counts[QuizImageFilter.withoutImage], 1);
    });

    test('脏 data URL 在计数和筛选里要一致地算无图', () {
      // 计数走 parse（脏数据降级占位），筛选原来只看 isNotEmpty，
      // 两边判定不一致会让「有图 (N)」点进去出来 N+1 条。
      final items = [
        q(id: '1', image: 'https://cdn/a.png'),
        q(id: '2', image: 'data:image/png;base64,!!!broken!!!'),
      ];
      final counts = QuizBankFilter.imageCounts(items);
      expect(counts[QuizImageFilter.withImage], 1);

      const filter = QuizBankFilter(image: QuizImageFilter.withImage);
      expect(
        filter.apply(items).map((x) => x.id),
        ['1'],
        reason: '脏 data URL 显示的是占位图，不该被「有图」筛出来',
      );
    });
  });

  group('题型筛选', () {
    test('判断题按 type 字段命中', () {
      final items = [
        q(id: '1', type: 'judge', options: ['正确', '错误'], answer: '正确'),
        q(id: '2', type: 'single_choice'),
      ];
      const filter = QuizBankFilter(type: QuizTypeFilter.judge);
      expect(filter.apply(items).map((x) => x.id), ['1']);
    });

    test('中文 type 值也能命中', () {
      final items = [
        q(id: '1', type: '判断题', options: ['正确', '错误'], answer: '正确'),
      ];
      const filter = QuizBankFilter(type: QuizTypeFilter.judge);
      expect(filter.apply(items), hasLength(1));
    });

    test('服务端 type 缺失时按选项结构反推判断题', () {
      final items = [
        q(id: '1', type: '', options: ['正确', '错误'], answer: '正确'),
        q(id: '2', type: '', options: ['甲', '乙', '丙', '丁'], answer: 'A'),
      ];
      const filter = QuizBankFilter(type: QuizTypeFilter.judge);
      expect(filter.apply(items).map((x) => x.id), ['1']);
    });

    test('type 缺失且答案含多字母时反推多选', () {
      final items = [
        q(id: '1', type: '', answer: 'AC'),
        q(id: '2', type: '', answer: 'A'),
      ];
      expect(
        const QuizBankFilter(type: QuizTypeFilter.multi)
            .apply(items)
            .map((x) => x.id),
        ['1'],
      );
      expect(
        const QuizBankFilter(type: QuizTypeFilter.single)
            .apply(items)
            .map((x) => x.id),
        ['2'],
      );
    });

    test('多选题别名 multiple_choice 命中', () {
      final items = [q(id: '1', type: 'multiple_choice', answer: 'AB')];
      expect(
        const QuizBankFilter(type: QuizTypeFilter.multi).apply(items),
        hasLength(1),
      );
    });

    test('排序题命中', () {
      final items = [
        q(id: '1', type: 'sort', answer: '②①③④'),
        q(id: '2', type: 'single_choice'),
      ];
      expect(
        const QuizBankFilter(type: QuizTypeFilter.sort)
            .apply(items)
            .map((x) => x.id),
        ['1'],
      );
    });
  });

  group('状态筛选', () {
    test('待审核兼容 pending 与 pending_review 两种写法', () {
      final items = [
        q(id: '1', status: 'pending'),
        q(id: '2', status: 'pending_review'),
        q(id: '3', status: 'approved'),
      ];
      expect(
        const QuizBankFilter(status: QuizStatusFilter.pending)
            .apply(items)
            .map((x) => x.id),
        ['1', '2'],
      );
    });
  });

  group('组合筛选与搜索', () {
    test('有图 + 判断题同时生效', () {
      final items = [
        q(
          id: '1',
          type: 'judge',
          options: ['正确', '错误'],
          image: 'https://cdn/a.png',
        ),
        q(id: '2', type: 'judge', options: ['正确', '错误']),
        q(id: '3', type: 'single_choice', image: 'https://cdn/b.png'),
      ];
      const filter = QuizBankFilter(
        image: QuizImageFilter.withImage,
        type: QuizTypeFilter.judge,
      );
      expect(filter.apply(items).map((x) => x.id), ['1']);
    });

    test('关键词搜题干、选项、标签、解析', () {
      final items = [
        q(id: '1', question: '这个标志什么含义'),
        q(id: '2', options: ['禁止通行', '允许通行']),
        q(id: '3', tags: ['交通标志']),
        q(id: '4', explanation: '红圈白杠表示禁止'),
        q(id: '5', question: '无关题目'),
      ];
      expect(
        const QuizBankFilter(query: '标志').apply(items).map((x) => x.id),
        ['1', '3'],
      );
      expect(
        const QuizBankFilter(query: '禁止').apply(items).map((x) => x.id),
        ['2', '4'],
      );
    });

    test('无筛选时 isActive 为假，全部返回', () {
      const filter = QuizBankFilter();
      expect(filter.isActive, isFalse);
      final items = [q(id: '1'), q(id: '2')];
      expect(filter.apply(items), hasLength(2));
    });

    test('设了任一筛选则 isActive 为真', () {
      expect(
        const QuizBankFilter(image: QuizImageFilter.withImage).isActive,
        isTrue,
      );
      expect(
        const QuizBankFilter(type: QuizTypeFilter.judge).isActive,
        isTrue,
      );
    });
  });
}
