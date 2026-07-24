import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/domain/quiz_capture_session.dart';

void main() {
  test('题目 A→B→A 必须形成三次不同捕获代次，不能因回到 A 被永久抑制', () {
    final coordinator = QuizCaptureSessionCoordinator();
    final a1 = coordinator.begin();
    coordinator.accept(a1, [1]);
    final b = coordinator.begin();
    coordinator.accept(b, [2]);
    final a2 = coordinator.begin();
    coordinator.accept(a2, [3]);

    expect(a2, greaterThan(a1));
    expect(coordinator.take(a2), [3]);
  });
}
