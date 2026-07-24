import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/domain/quiz_capture_session.dart';

void main() {
  test('只接受当前截图请求的结果，旧请求结果不能串入新请求', () {
    final coordinator = QuizCaptureSessionCoordinator();
    final first = coordinator.begin();
    final second = coordinator.begin();

    expect(coordinator.accept(first, [1, 2, 3]), isFalse);
    expect(coordinator.accept(second, [4, 5]), isTrue);
    expect(coordinator.take(second), [4, 5]);
    expect(coordinator.take(first), isNull);
  });

  test('读取一次后移除截图，避免下一次请求复用旧图', () {
    final coordinator = QuizCaptureSessionCoordinator();
    final id = coordinator.begin();
    coordinator.accept(id, [9]);

    expect(coordinator.take(id), [9]);
    expect(coordinator.take(id), isNull);
  });
}
