import 'dart:convert';

import 'package:box/features/quiz_plugin/presentation/quiz_question_image_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uploaded question image dHash uses shared 64-bit hex format', () async {
    // A valid 9×8 PNG; production code decodes it to the fixed 9×8 dHash grid.
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAkAAAAICAIAAACkr0LiAAAAFUlEQVR4nGNkYGCQxAGYGHCDoSIHAPCbAmjw5/saAAAAAElFTkSuQmCC',
    );

    final hash = await QuizQuestionImageStore.computeDHash(png);

    expect(hash, matches(RegExp(r'^[0-9a-f]{16}$')));
    expect(hash.length, 16);
  });

  test(
    'uploaded cropped question image is also a region fingerprint',
    () async {
      final image = QuizQuestionImage(
        path: '/tmp/sign.png',
        sha256: 'a' * 64,
        perceptualHash: '0011223344556677',
      );

      expect(image.regionHash, equals(image.perceptualHash));
    },
  );
}
