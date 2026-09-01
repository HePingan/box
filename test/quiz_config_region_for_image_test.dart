import 'dart:ui';

import 'package:box/features/quiz_plugin/domain/quiz_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('regionForImage 默认 null', () {
    expect(const QuizConfig().regionForImage, isNull);
  });

  test('regionForImage 序列化往返一致', () {
    const region = Rect.fromLTRB(0.1, 0.2, 0.9, 0.8);
    const cfg = QuizConfig(regionForImage: region);
    final json = cfg.toJson();
    expect(json['regionForImage'], isNotNull);
    expect((json['regionForImage'] as Map)['left'], closeTo(0.1, 1e-6));
    expect(QuizConfig.fromJson(json).regionForImage, region);
  });

  test('regionForImage 空对象时解析为 null', () {
    expect(QuizConfig.fromJson({}).regionForImage, isNull);
    expect(
      QuizConfig.fromJson({'regionForImage': null}).regionForImage,
      isNull,
    );
    expect(
      QuizConfig.fromJson({
        'regionForImage': <String, dynamic>{},
      }).regionForImage,
      isNull,
    );
  });

  test('regionForImage 非法值解析为 null', () {
    expect(
      QuizConfig.fromJson({
        'regionForImage': {'left': -1, 'top': 0, 'right': 1, 'bottom': 1},
      }).regionForImage,
      isNull,
    );
    expect(
      QuizConfig.fromJson({
        'regionForImage': {'left': 0, 'top': 0, 'right': 0, 'bottom': 1},
      }).regionForImage,
      isNull,
    );
    expect(
      QuizConfig.fromJson({
        'regionForImage': {'left': 0, 'top': 1, 'right': 1, 'bottom': 0},
      }).regionForImage,
      isNull,
    );
  });

  test('copyWith 可单独更新 regionForImage', () {
    const region = Rect.fromLTRB(0.1, 0.2, 0.9, 0.8);
    const base = QuizConfig();
    final updated = base.copyWith(regionForImage: region);
    expect(updated.regionForImage, region);
    expect(updated.enabled, base.enabled);
  });
}
