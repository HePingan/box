import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:flutter_test/flutter_test.dart';

/// 判断题选项前缀归一化。
///
/// 用户题库里这道题的选项存成：
/// ```
/// 正确. 正确
/// 错误. 错误 ✓
/// ```
/// 前缀不是 A./B. 而是选项自身的中文文字。
///
/// normalizeOption 的前缀正则只剥 `^[a-dａ-ｄ][.、．:：)）]`，
/// 剥不掉「正确.」「错误.」，于是题库侧归一化成 `正确.正确`，
/// 而卷面 OCR 读到的是 `正确`，两边对不上 => oScore 被压低
/// => baseScore 跌破 70 => 误报「请人工确认」。
void main() {
  group('normalizeOption 判断题中文前缀', () {
    test('「正确. 正确」应归一化为「正确」', () {
      expect(QuizBankTextNormalizer.normalizeOption('正确. 正确'), '正确');
    });

    test('「错误. 错误」应归一化为「错误」', () {
      expect(QuizBankTextNormalizer.normalizeOption('错误. 错误'), '错误');
    });

    test('中文顿号/冒号/括号形态的重复前缀也要剥掉', () {
      const cases = {
        '正确、正确': '正确',
        '错误、错误': '错误',
        '正确：正确': '正确',
        '错误：错误': '错误',
        '正确)正确': '正确',
        '错误）错误': '错误',
        '正确．正确': '正确',
      };
      cases.forEach((input, expected) {
        expect(
          QuizBankTextNormalizer.normalizeOption(input),
          expected,
          reason: '输入 $input',
        );
      });
    });

    test('字母前缀原有行为不变', () {
      expect(QuizBankTextNormalizer.normalizeOption('A. 停车让行'), '停车让行');
      expect(QuizBankTextNormalizer.normalizeOption('B、加速通过'), '加速通过');
      expect(QuizBankTextNormalizer.normalizeOption('Ｃ：减速慢行'), '减速慢行');
    });

    test('不得误伤正文以「正确/错误」开头但非重复前缀的选项', () {
      // 「正确使用灯光」不是「正确.」前缀 + 正文，必须整条保留
      expect(
        QuizBankTextNormalizer.normalizeOption('正确使用灯光'),
        '正确使用灯光',
      );
      // 有分隔符但后半不是同一个词：属于正常正文，不能剥
      expect(
        QuizBankTextNormalizer.normalizeOption('正确、安全的驾驶方式'),
        '正确、安全的驾驶方式',
      );
      expect(
        QuizBankTextNormalizer.normalizeOption('错误：未系安全带'),
        '错误：未系安全带',
      );
    });

    test('单独的「正确」「错误」保持原样', () {
      expect(QuizBankTextNormalizer.normalizeOption('正确'), '正确');
      expect(QuizBankTextNormalizer.normalizeOption('错误'), '错误');
    });
  });
}
