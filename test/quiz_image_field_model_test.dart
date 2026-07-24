import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('QuizBankItem serializes image/category/origin fields', () {
    const item = QuizBankItem(
      id: 'q1',
      question: '如图所示，指示灯表示什么？',
      type: QuizQuestionType.singleChoice,
      options: ['A', 'B'],
      correctAnswer: 'A',
      imageUrl: '/api/quiz/images/demo.png',
      category: '驾驶理论题库-20260719',
      origin: 'cloud',
      source: '云端题库',
    );

    final json = item.toJson();
    expect(json['image'], '/api/quiz/images/demo.png');
    expect(json['category'], '驾驶理论题库-20260719');
    expect(json['origin'], 'cloud');

    final restored = QuizBankItem.fromJson({
      ...json,
      'image': 'https://box.example/api/quiz/images/demo.png',
    });
    expect(restored.imageUrl, 'https://box.example/api/quiz/images/demo.png');
    expect(restored.category, '驾驶理论题库-20260719');
    expect(restored.origin, 'cloud');
    expect(restored.isCloud, isTrue);

    final db = restored.toDb();
    expect(db['image'], 'https://box.example/api/quiz/images/demo.png');
    expect(db['category'], '驾驶理论题库-20260719');
    expect(db['origin'], 'cloud');
    expect(db['syncStatus'], QuizSyncStatus.published);

    final fromDb = QuizBankItem.fromDb({
      'id': 'q1',
      'question': '如图所示，指示灯表示什么？',
      'type': 'single_choice',
      'options': '["A","B"]',
      'correctAnswer': 'A',
      'analysis': null,
      'source': '云端题库',
      'createdAt': null,
      'image': '/data/user/0/com.example.box/files/quiz_images/abc.png',
      'category': '驾驶理论题库-20260719',
      'origin': 'cloud',
      'syncStatus': 'published',
    });
    expect(
      fromDb.imageUrl,
      '/data/user/0/com.example.box/files/quiz_images/abc.png',
    );
    expect(fromDb.category, '驾驶理论题库-20260719');
    expect(fromDb.isCloud, isTrue);
    expect(fromDb.syncStatus, QuizSyncStatus.published);

    final localInferred = QuizBankItem.fromJson({
      'id': 'q2',
      'question': '本地题',
      'type': 'single_choice',
      'options': ['A'],
      'correctAnswer': 'A',
      'source': '录入',
    });
    expect(localInferred.origin, 'local');
    expect(localInferred.isCloud, isFalse);
    expect(localInferred.syncStatus, QuizSyncStatus.localOnly);
    expect(localInferred.isUnpushedLocal, isTrue);
  });
}
