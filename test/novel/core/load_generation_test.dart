import 'dart:async';

import 'package:box/novel/core/load_generation.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归：慢响应的旧请求不得覆盖新请求的结果。
///
/// 缺陷背景（novel_list_page.dart:_loadSearchPage）：响应路径只有 `mounted`
/// 守卫，没有请求身份校验。搜「斗罗」后立刻搜「遮天」，若前者更慢返回，
/// `reset: true` 会把「斗罗」的结果写进列表，而搜索框显示「遮天」。
void main() {
  group('LoadGeneration', () {
    test('单次加载：token 始终有效', () {
      final gen = LoadGeneration();
      final t = gen.begin('斗罗');
      expect(gen.isCurrent(t), isTrue);
    });

    test('新一代开启后，旧 token 立即失效', () {
      final gen = LoadGeneration();
      final slow = gen.begin('斗罗');
      final fast = gen.begin('遮天');

      expect(gen.isCurrent(slow), isFalse, reason: '旧请求必须被作废');
      expect(gen.isCurrent(fast), isTrue);
    });

    test('意图相同但代号更新时，旧 token 仍失效（防重复触发串写）', () {
      final gen = LoadGeneration();
      final first = gen.begin('斗罗');
      final second = gen.begin('斗罗');

      expect(gen.isCurrent(first), isFalse);
      expect(gen.isCurrent(second), isTrue);
    });

    test('invalidate 作废全部在途请求（取消搜索/离开页面）', () {
      final gen = LoadGeneration();
      final t = gen.begin('斗罗');
      gen.invalidate();
      expect(gen.isCurrent(t), isFalse);
    });

    test('端到端：慢的旧响应不覆盖快的新响应（核心回归）', () async {
      final gen = LoadGeneration();
      final books = <String>[];

      Future<void> load(String kw, Duration delay, List<String> result) async {
        final token = gen.begin(kw);
        await Future.delayed(delay);
        if (!gen.isCurrent(token)) return; // 关键守卫
        books
          ..clear()
          ..addAll(result);
      }

      // 先发「斗罗」（慢 60ms），紧接着发「遮天」（快 10ms）
      final slow = load('斗罗', const Duration(milliseconds: 60), ['斗罗大陆']);
      final fast = load('遮天', const Duration(milliseconds: 10), ['遮天']);
      await Future.wait([slow, fast]);

      expect(books, ['遮天'],
          reason: '列表必须停留在最新搜索词的结果，而非慢响应的旧结果');
    });

    test('端到端：旧请求的异常也不得写进错误态', () async {
      final gen = LoadGeneration();
      String error = '';

      Future<void> load(String kw, Duration delay, {bool fail = false}) async {
        final token = gen.begin(kw);
        try {
          await Future.delayed(delay);
          if (fail) throw Exception('boom');
        } catch (e) {
          if (!gen.isCurrent(token)) return; // error 路径也要守卫
          error = '加载失败：$e';
          return;
        }
        if (!gen.isCurrent(token)) return;
        error = '';
      }

      final slowFail =
          load('斗罗', const Duration(milliseconds: 60), fail: true);
      final fastOk = load('遮天', const Duration(milliseconds: 10));
      await Future.wait([slowFail, fastOk]);

      expect(error, '', reason: '被作废请求的失败不应污染新请求的 UI 状态');
    });
  });
}
