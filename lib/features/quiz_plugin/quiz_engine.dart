import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

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

  Future<QuizResult> search(String question, {bool forceExternalSearch = false}) async {
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

    if (!forceExternalSearch && !config.autoSearch) {
      return QuizResult(question: question, error: '未开启自动搜题', elapsedMs: stopwatch.elapsedMilliseconds);
    }

    if (config.allowExternalApi && config.apiUrl.isNotEmpty) {
      try {
        final result = await _searchCustomApi(trimmed);
        if (result.isSuccess) {
          return result.copyWith(elapsedMs: stopwatch.elapsedMilliseconds, source: result.source.isEmpty ? '远程API' : result.source);
        }
      } catch (_) {}
    }

    if (config.allowExternalApi) {
      try {
        final result = await _searchBuiltIn(trimmed);
        return result.copyWith(elapsedMs: stopwatch.elapsedMilliseconds, source: result.source.isEmpty ? '内置检索' : result.source);
      } catch (e) {
        return QuizResult(question: question, error: '搜题失败：$e', elapsedMs: stopwatch.elapsedMilliseconds);
      }
    }

    return QuizResult(question: question, error: '本地题库未找到；外部搜题已关闭', elapsedMs: stopwatch.elapsedMilliseconds);
  }

  Future<List<QuizAnswer>?> _searchBank(String question) async {
    await QuizBankCache.instance.ensureLoaded();
    final hay = QuizBankTextNormalizer.cleanForMatch(question);
    if (hay.isEmpty) return null;

    final candidates = QuizBankCache.instance.candidatesFor(hay);
    if (candidates.isEmpty) return null;

    final scored = <({QuizBankItem item, int score})>[];
    for (final item in candidates) {
      final target = QuizBankTextNormalizer.cleanForMatch(item.question);
      if (target.isEmpty) continue;

      int score = 0;
      if (hay == target) {
        score = 100;
      } else if (target.contains(hay) || hay.contains(target)) {
        final shorter = min(hay.length, target.length);
        final longer = max(hay.length, target.length);
        score = longer == 0 ? 0 : (72 + shorter / longer * 24).round();
      } else {
        score = _similarityScore(hay, target);
      }

      if (score >= 55) scored.add((item: item, score: score));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final top = scored.take(config.bankMaxMatches).toList();
    if (top.isEmpty || top.first.score < 60) return null;

    return top.map((entry) {
      final item = entry.item;
      final formatted = _formatBankAnswer(item, entry.score);
      return QuizAnswer(
        text: formatted,
        confidence: entry.score / 100,
        source: '本地题库',
        options: item.options,
        correctAnswer: item.correctAnswer,
        analysis: item.analysis,
      );
    }).toList();
  }

  String _formatBankAnswer(QuizBankItem item, int score) {
    final lines = <String>[
      '匹配题目：${item.question}',
      if (item.correctAnswer.trim().isNotEmpty) '答案：${_resolveCorrectAnswerText(item)}',
      if (item.options.isNotEmpty) '选项：\n${item.options.join('\n')}',
      if ((item.analysis ?? '').trim().isNotEmpty) '解析：${item.analysis}',
      '相似度：$score%',
    ];
    return lines.join('\n');
  }

  String _resolveCorrectAnswerText(QuizBankItem item) {
    final raw = item.correctAnswer.trim();
    if (raw.isEmpty) return '';
    final normalized = raw.toUpperCase();
    final optionMatch = RegExp(r'^[A-H]$').firstMatch(normalized);
    if (optionMatch != null) {
      final index = normalized.codeUnitAt(0) - 'A'.codeUnitAt(0);
      if (index >= 0 && index < item.options.length) {
        return '$normalized. ${item.options[index]}';
      }
    }
    final number = int.tryParse(raw);
    if (number != null && number >= 1 && number <= item.options.length) {
      return '$raw. ${item.options[number - 1]}';
    }
    return raw;
  }


  int _similarityScore(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final lcs = _longestCommonSubsequenceLength(a, b);
    final lcsScore = (lcs * 200 / (a.length + b.length)).round();
    final setA = a.split('').toSet();
    final setB = b.split('').toSet();
    final union = setA.union(setB).length;
    final inter = setA.intersection(setB).length;
    final jaccard = union == 0 ? 0 : (inter * 100 / union).round();
    // 字符集合重叠容易把“机动车/道路/正确/错误”等通用词误判，作为弱信号限幅。
    return max(lcsScore, min(jaccard, 72));
  }

  int _longestCommonSubsequenceLength(String a, String b) {
    final previous = List<int>.filled(b.length + 1, 0);
    final current = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        current[j] = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1)
            ? previous[j - 1] + 1
            : max(previous[j], current[j - 1]);
      }
      for (var j = 0; j <= b.length; j++) {
        previous[j] = current[j];
        current[j] = 0;
      }
    }
    return previous[b.length];
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
