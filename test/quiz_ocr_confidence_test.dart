import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/data/quiz_ocr_client.dart';

void main() {
  test('无置信度的旧 OCR 服务保持兼容', () {
    const result = OcrResult(fullText: '题目');
    expect(result.meetsAutoSearchConfidence(), isTrue);
  });

  test('低置信度 OCR 阻止自动搜题并给出诊断', () {
    const result = OcrResult(fullText: '题目', scores: [0.2, 0.4]);
    expect(result.meetsAutoSearchConfidence(), isFalse);
    expect(result.confidenceDiagnostic(), contains('低于自动搜题阈值'));
  });

  test('高置信度 OCR 允许自动搜题', () {
    const result = OcrResult(fullText: '题目', scores: [0.8, 0.9]);
    expect(result.meetsAutoSearchConfidence(), isTrue);
  });
}
