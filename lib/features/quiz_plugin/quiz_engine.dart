import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../../design_system/app_tokens.dart';
import 'quiz_config.dart';
import 'quiz_bank.dart';

class QuizResult {
  const QuizResult({
    required this.question,
    this.answers = const [],
    this.error,
    this.elapsedMs = 0,
    this.source = '',
  });

  final String question;
  final List<QuizAnswer> answers;
  final String? error;
  final int elapsedMs;
  final String source;

  QuizResult copyWith({
    String? question,
    List<QuizAnswer>? answers,
    String? error,
    int? elapsedMs,
    String? source,
  }) {
    return QuizResult(
      question: question ?? this.question,
      answers: answers ?? this.answers,
      error: error ?? this.error,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      source: source ?? this.source,
    );
  }

  bool get isSuccess => error == null && answers.isNotEmpty;
}

class QuizAnswer {
  const QuizAnswer({
    required this.text,
    this.confidence = 0.0,
    this.source = '',
    this.options = const [],
    this.correctAnswer = '',
    this.analysis,
  });

  final String text;
  final double confidence;
  final String source;
  final List<String> options;
  final String correctAnswer;
  final String? analysis;
}

class QuizEngine {
  QuizEngine({required this.config});

  QuizConfig config;

  Future<QuizResult> search(String question) async {
    final stopwatch = Stopwatch()..start();
    final trimmed = question.trim();
    if (trimmed.isEmpty) {
      return QuizResult(question: question, error: '题目为空', elapsedMs: stopwatch.elapsedMilliseconds);
    }

    if (config.bankEnabled) {
      try {
        final bankResult = await _searchBank(trimmed);
        if (bankResult != null) {
          return QuizResult(
            question: question,
            answers: bankResult,
            elapsedMs: stopwatch.elapsedMilliseconds,
            source: '本地题库',
          );
        }
      } catch (_) {
        // 题库查失败不影响继续走外部
      }
    }

    if (!config.autoSearch) {
      return QuizResult(question: question, error: '未开启自动搜题', elapsedMs: stopwatch.elapsedMilliseconds);
    }

    if (config.apiUrl.isNotEmpty) {
      try {
        final result = await _searchCustomApi(trimmed);
        if (result.isSuccess) {
          return result.copyWith(elapsedMs: stopwatch.elapsedMilliseconds, source: result.source.isEmpty ? '远程API' : result.source);
        }
      } catch (_) {}
    }

    try {
      final result = await _searchBuiltIn(trimmed);
      return result.copyWith(elapsedMs: stopwatch.elapsedMilliseconds, source: result.source.isEmpty ? '内置检索' : result.source);
    } catch (e) {
      return QuizResult(question: question, error: '搜题失败：$e', elapsedMs: stopwatch.elapsedMilliseconds);
    }
  }

  Future<List<QuizAnswer>?> _searchBank(String question) async {
    final all = await QuizBankStorage.loadAll();
    if (all.isEmpty) return null;

    String clean(String text) {
      final q = text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
      // 去掉常见题干前缀：单选题/判断题/选择题/多选题/题型标记
      var t = q;
      t = t.replaceAll(RegExp(r'^(\[单选题\]|\[多选题\]|\[判断题\]|\[选择题\]|\[单选题\]|\[问答题\]|【单选题】|【多选题】|【判断题】|【选择题】|\[单选\]|\[判断\])'), '');
      // 去掉括号及内容：(图片)(图文)(材料一)(节选自...)【图片】【说明】
      t = t.replaceAll(RegExp(r'(\([^）]*\)|（[^）]*）|【[^】]*】)'), '');
      // 去掉题号 1. 2. 12.
      t = t.replaceAll(RegExp(r'^\d+[.、]'), '');
      return t.trim();
    }

    final hay = clean(question);
    if (hay.isEmpty) return null;

    final scored = <({QuizBankItem item, int score})>[];
    for (final item in all) {
      final target = clean(item.question);
      if (target.isEmpty) continue;

      final normHay = hay;
      final normTarget = target;

      int score = 0;
      if (normHay == normTarget) {
        score = 100;
      } else if (normTarget.contains(normHay) || normHay.contains(normTarget)) {
        score = 65;
      } else {
        // 字符集交集得分
        final setHay = normHay.split('').toSet();
        final setTarget = normTarget.split('').toSet();
        final inter = setHay.intersection(setTarget).length;
        final minLen = min(setHay.length, setTarget.length);
        if (minLen > 0) score = (inter / minLen * 70).toInt();
        if (score < 30 && minLen >= 5) {
          // 滑动窗口公共子串加分
          final smaller = minLen == setHay.length ? normHay : normTarget;
          final bigger = minLen == setHay.length ? normTarget : normHay;
          final window = (smaller.length / 3).floor().clamp(3, smaller.length);
          int matches = 0;
          for (var i = 0; i <= smaller.length - window; i++) {
            final sub = smaller.substring(i, i + window);
            if (bigger.contains(sub)) matches++;
          }
          score = max(score, (matches * 6).clamp(30, 64));
        }
      }

      if (score >= 35) scored.add((item: item, score: score));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final top = scored.take(config.bankMaxMatches).toList();
    if (top.isEmpty || top.first.score < 35) return null;

    return top.map((entry) {
      final item = entry.item;
      return QuizAnswer(
        text: item.options.join('\n'),
        confidence: entry.score / 100,
        source: '本地题库',
        options: item.options,
        correctAnswer: item.correctAnswer,
        analysis: item.analysis,
      );
    }).toList();
  }

  Future<QuizResult> _searchCustomApi(String question) async {
    final uri = Uri.parse(config.apiUrl).replace(queryParameters: {
      'question': question,
      if (config.apiKey.isNotEmpty) 'key': config.apiKey,
    });

    final response = await http.get(uri).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      return QuizResult(question: question, error: 'API 返回 ${response.statusCode}');
    }

    final body = jsonDecode(response.body);
    final answers = <QuizAnswer>[];

    if (body is Map) {
      final data = body['data'] ?? body['result'] ?? body['answer'];
      if (data is List) {
        for (final item in data) {
          if (item is Map) {
            final text = (item['answer'] ?? item['text'] ?? item['content'] ?? '').toString();
            final conf = (item['confidence'] as num?)?.toDouble() ?? 0.0;
            if (text.isNotEmpty) answers.add(QuizAnswer(text: text, confidence: conf, source: 'API'));
          } else {
            answers.add(QuizAnswer(text: item.toString(), source: 'API'));
          }
        }
      } else if (data is String && data.isNotEmpty) {
        answers.add(QuizAnswer(text: data, source: 'API'));
      } else if (body['answer'] is String) {
        answers.add(QuizAnswer(text: body['answer'] as String, source: 'API'));
      }
    }

    return QuizResult(question: question, answers: answers, error: answers.isEmpty ? '未解析到答案' : null);
  }

  Future<QuizResult> _searchBuiltIn(String question) async {
    const apis = [
      'https://api.oioweb.cn/api/ti',
      'https://api.66mz8.com/api/ti.php',
    ];

    for (final api in apis) {
      try {
        final uri = Uri.parse(api).replace(queryParameters: {'question': question, 'type': 'json'});
        final response = await http.get(uri, headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final answers = _parseBuiltInResponse(response.body);
          if (answers.isNotEmpty) {
            return QuizResult(question: question, answers: answers, error: null);
          }
        }
      } catch (_) {
        continue;
      }
    }

    return QuizResult(question: question, error: '内置搜题无结果');
  }

  List<QuizAnswer> _parseBuiltInResponse(String body) {
    final answers = <QuizAnswer>[];
    try {
      final json = jsonDecode(body);
      if (json is Map) {
        for (final key in ['data', 'result', 'answer', 'msg', 'text', 'content']) {
          final val = json[key];
          if (val is String && val.isNotEmpty) {
            for (final line in val.split('\n')) {
              final trimmed = line.trim();
              if (trimmed.isNotEmpty) {
                answers.add(QuizAnswer(text: trimmed, source: '内置', confidence: answers.isEmpty ? 0.9 : 0.5));
              }
            }
            if (answers.isNotEmpty) break;
          }
        }
        final data = json['data'];
        if (answers.isEmpty && data is Map) {
          for (final key in ['answer', 'result', 'text']) {
            final val = data[key];
            if (val is String && val.isNotEmpty) {
              answers.add(QuizAnswer(text: val, source: '内置', confidence: 0.8));
              break;
            }
          }
        }
      } else if (json is List) {
        for (final item in json) {
          if (item is String && item.isNotEmpty) {
            answers.add(QuizAnswer(text: item, source: '内置'));
          } else if (item is Map) {
            final text = (item['answer'] ?? item['text'] ?? item['content'] ?? '').toString();
            if (text.isNotEmpty) answers.add(QuizAnswer(text: text, source: '内置'));
          }
        }
      }
    } catch (_) {
      final lines = body.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty && l.length > 2).toList();
      if (lines.isNotEmpty) {
        answers.addAll(lines.map((l) => QuizAnswer(text: l, source: '内置')));
      }
    }
    return answers;
  }
}
