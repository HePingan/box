import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/data/quiz_engine.dart';
import 'package:box/features/quiz_plugin/presentation/quiz_plugin_entry.dart';

void main() {
  QuizResult resultWith(List<QuizAnswer> answers) =>
      QuizResult(question: '测试题', answers: answers);

  const a = QuizAnswer(text: '答案：A', correctAnswer: 'A', confidence: 0.95);
  const b = QuizAnswer(text: '答案：B', correctAnswer: 'B', confidence: 0.65);
  const c = QuizAnswer(text: '答案：C', correctAnswer: 'C', confidence: 0.90);
  const d = QuizAnswer(text: '答案：D', correctAnswer: 'D', confidence: 0.92);

  group('Quiz ambiguity and confidence threshold', () {
    test('high-confidence single answer is safe to auto-answer', () {
      final result = resultWith([a]);
      final decision = QuizPluginEntry.overlayDecisionForResult(result, ['A']);
      expect(decision.status, 'hit');
      expect(decision.answerKey, 'A');
    });

    test('low-confidence answer requires manual confirmation', () {
      final result = resultWith([b]);
      final decision = QuizPluginEntry.overlayDecisionForResult(result, ['B']);
      expect(decision.status, 'ambiguous');
      expect(decision.answerKey, isNull);
      expect(decision.lowConfidence, isTrue);
    });

    test('multiple candidate answers require manual confirmation', () {
      final result = resultWith([a, c]);
      final decision = QuizPluginEntry.overlayDecisionForResult(result, [
        'A',
        'C',
      ]);
      expect(decision.status, 'ambiguous');
      expect(decision.answerKey, isNull);
    });

    test('two close candidates are below the confidence-gap threshold', () {
      final result = resultWith([a, c]);
      final gap = (result.answers[0].confidence - result.answers[1].confidence)
          .abs();
      expect(gap, lessThan(0.08));
    });

    test('clear winner is above confidence and gap thresholds', () {
      final result = resultWith([d, b]);
      final gap = (result.answers[0].confidence - result.answers[1].confidence)
          .abs();
      expect(result.answers.first.confidence, greaterThanOrEqualTo(0.70));
      expect(gap, greaterThanOrEqualTo(0.08));
    });

    test('miss has no answer candidates', () {
      const result = QuizResult(question: '未知题', error: '未找到匹配');
      expect(result.isSuccess, isFalse);
      expect(result.answers, isEmpty);
    });

    test('overlay similarity remains derived from structured confidence', () {
      expect(QuizPluginEntry.similarityPercentForAnswer(a), 95);
    });
  });
}
