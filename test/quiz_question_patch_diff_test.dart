import 'package:box/features/admin/domain/quiz_bank_models.dart';
import 'package:box/features/admin/domain/quiz_question_patch_diff.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「完整编辑」提交时只发真正改动的字段。
///
/// 真实故障：编辑已有题目时把 question + options 原样回传，
/// 服务端查重拿这份题干比库，命中这道题自己，
/// 报「题干与完整选项已存在，不能合并覆盖」。
void main() {
  QuizBankQuestion original() => const QuizBankQuestion(
    id: 'q1',
    question: '这个标志什么含义？',
    options: ['禁止通行', '允许通行'],
    answer: '禁止通行',
    status: 'approved',
    tags: ['标志'],
    explanation: '红圈白杠',
    category: '交规',
    type: 'single_choice',
    image: '',
  );

  Map<String, dynamic> fullForm({
    String? question,
    List<String>? options,
    String? answer,
    String? explanation,
    String image = '',
  }) => {
    'question': question ?? '这个标志什么含义？',
    'options': options ?? ['禁止通行', '允许通行'],
    'answer': answer ?? '禁止通行',
    'correctAnswer': answer ?? '禁止通行',
    'status': 'approved',
    'tags': ['标志'],
    'explanation': explanation ?? '红圈白杠',
    'analysis': explanation ?? '红圈白杠',
    'category': '交规',
    'type': 'single_choice',
    'image': image,
  };

  test('只改图片时，请求体不含题干与选项', () {
    final diff = QuizQuestionPatchDiff.minimize(
      payload: fullForm(image: 'https://cdn/x.png'),
      original: original(),
    );

    expect(diff.keys, ['image']);
    expect(diff['image'], 'https://cdn/x.png');
  });

  test('改了题干时必须发题干', () {
    final diff = QuizQuestionPatchDiff.minimize(
      payload: fullForm(question: '换了题干'),
      original: original(),
    );
    expect(diff['question'], '换了题干');
    expect(diff.containsKey('options'), isFalse, reason: '选项没动就不发');
  });

  test('改答案时同义别名一起发，避免只更新一半', () {
    final diff = QuizQuestionPatchDiff.minimize(
      payload: fullForm(answer: '允许通行'),
      original: original(),
    );
    expect(diff['answer'], '允许通行');
    expect(diff['correctAnswer'], '允许通行');
  });

  test('改解析时 explanation 与 analysis 一起发', () {
    final diff = QuizQuestionPatchDiff.minimize(
      payload: fullForm(explanation: '新解析'),
      original: original(),
    );
    expect(diff['explanation'], '新解析');
    expect(diff['analysis'], '新解析');
  });

  test('什么都没改时返回空，调用方可跳过请求', () {
    expect(
      QuizQuestionPatchDiff.minimize(
        payload: fullForm(),
        original: original(),
      ),
      isEmpty,
    );
  });

  test('新建题目（original 为 null）发全字段', () {
    final diff = QuizQuestionPatchDiff.minimize(
      payload: fullForm(),
      original: null,
    );
    expect(diff.containsKey('question'), isTrue);
    expect(diff.containsKey('options'), isTrue);
  });

  test('选项顺序变化算改动', () {
    final diff = QuizQuestionPatchDiff.minimize(
      payload: fullForm(options: ['允许通行', '禁止通行']),
      original: original(),
    );
    expect(diff['options'], ['允许通行', '禁止通行']);
  });

  test('仅前后空白差异不算改动', () {
    final diff = QuizQuestionPatchDiff.minimize(
      payload: fullForm(question: '  这个标志什么含义？  '),
      original: original(),
    );
    expect(diff.containsKey('question'), isFalse);
  });
}
